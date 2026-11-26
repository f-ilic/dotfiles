#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["textual>=0.80"]
# ///
"""Install what these dotfiles need and link them: ``./start.sh``

No options. The screen shows what is installed and what is missing, lists what Apply will do, and does it when you
press Apply:
  - installs the missing tools (Homebrew on macOS; apt, snap and release downloads on Ubuntu/Debian)
  - makes ~/.zshrc load ~/.config/zsh/init.zsh
  - replaces files in your home that are byte-identical to the repo copy with links, then runs ``stow .``
Nothing of yours is deleted or overwritten: a file that differs from the repo copy is listed as "needs you".

``./start.sh --check`` prints the same status without a UI (stdlib only) and exits 1 if something needed is missing
or blocked. ``./start.sh --plain`` is the same flow as plain text with a y/N question, for machines where the UI can't
run (it is also what start.sh falls back to when neither uv nor a venv is available).

Per-machine settings never go into tracked files: ~/.config/zsh/local.zsh (zsh) and ~/.config/ghostty/config.local
(ghostty) are gitignored and picked up automatically.
"""

from __future__ import annotations

import argparse
import filecmp
import os
import platform
import plistlib
import pwd
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[1]  # ~/dotfiles
TARGET = REPO.parent  # where `stow .`, run inside REPO, puts its links
HOME = Path.home()
HOME_R = HOME.resolve()  # stow reports resolved paths (macOS: /tmp is really /private/tmp), so compare both
ZSHRC = HOME / ".zshrc"

BOOTSTRAP_LINE = 'source "${HOME}/.config/zsh/init.zsh"'
BOOT_RE = re.compile(r"config/zsh/init\.zsh")
CONFLICT_PATTERNS = [
    re.compile(r"cannot stow (?P<src>\S+) over existing target (?P<tgt>\S+) since"),
    re.compile(r"cannot stow non-directory (?P<src>\S+) over existing directory target (?P<tgt>\S+)"),
    re.compile(r"existing target is not owned by stow: (?P<tgt>\S+)"),
    re.compile(r"existing target is neither a link nor a directory: (?P<tgt>\S+)"),
    re.compile(r"existing target is stowed to a different package: (?P<tgt>\S+)"),
]

# Where to look. Module-level so the tests can point them into a sandbox.
EXTRA_PATH = [  # where tools live that a non-login shell's PATH often misses
    HOME / "bin", HOME / ".local/bin", HOME / ".cargo/bin", HOME / ".fzf/bin",
    Path("/opt/homebrew/bin"), Path("/usr/local/bin"), Path("/snap/bin"),
]
BREW_CANDIDATES = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
APP_DIRS = [Path("/Applications"), HOME / "Applications"]
FONT_DIRS = [HOME / "Library/Fonts", Path("/Library/Fonts")]
SYNTAX_HL_PATHS = [
    "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
    "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
    "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
]

LIVE = False  # True while steps run in the real terminal: sudo can ask for a password and installer output is visible


# ----------------------------------------------------------------------------------------------------------------------
# platform + helpers


def os_name() -> str:
    return {"Darwin": "mac", "Linux": "linux"}.get(platform.system(), platform.system().lower())


def is_desktop() -> bool:
    """A Mac, or a Linux box with a graphical session or a desktop installed (headless VMs have neither)."""
    if os_name() == "mac":
        return True
    return bool(
        os.environ.get("DISPLAY")
        or os.environ.get("WAYLAND_DISPLAY")
        or Path("/usr/share/xsessions").is_dir()
        or Path("/usr/share/wayland-sessions").is_dir()
    )


def machine_kind() -> str:
    return "macOS" if os_name() == "mac" else ("Linux desktop" if is_desktop() else "Linux headless")


def sh(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not found"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def find(name: str) -> str | None:
    """`which`, plus the places installers put things that a non-login shell's PATH often misses."""
    return shutil.which(name) or shutil.which(name, path=os.pathsep.join(str(p) for p in EXTRA_PATH))


def git_dirty_tracked() -> list[str]:
    """Tracked files that differ from HEAD: local edits that can block `git pull`."""
    rc, out = sh(["git", "-C", str(REPO), "status", "--porcelain", "-uno"])
    return [line[3:] for line in out.splitlines()] if rc == 0 else []


def zsh_syntax_ok(text: str) -> tuple[bool, str]:
    if not shutil.which("zsh"):
        return True, "zsh not found; syntax not checked"
    with tempfile.NamedTemporaryFile("w", suffix=".zsh", delete=False) as f:
        f.write(text)
        name = f.name
    try:
        p = subprocess.run(["zsh", "-n", name], capture_output=True, text=True)
        return p.returncode == 0, p.stderr.strip().replace(name, "<new file>")
    finally:
        Path(name).unlink(missing_ok=True)


# ----------------------------------------------------------------------------------------------------------------------
# what the dotfiles need. One table, one source of truth: the screen, --check and Apply all read it.

LAZYGIT_SH = r"""
set -euo pipefail
case "$(uname -m)" in x86_64) A=x86_64;; aarch64|arm64) A=arm64;; *) echo "no lazygit release for $(uname -m)" >&2; exit 1;; esac
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
U=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazygit/releases/latest)
V=${U##*/v}
curl -fsSL -o "$T/lazygit.tgz" "https://github.com/jesseduffield/lazygit/releases/download/v${V}/lazygit_${V}_linux_${A}.tar.gz"
tar -xf "$T/lazygit.tgz" -C "$T" lazygit
$SUDO install "$T/lazygit" /usr/local/bin/lazygit
"""
UV_SH = "set -euo pipefail; curl -LsSf https://astral.sh/uv/install.sh | sh"  # UV_NO_MODIFY_PATH keeps it out of your shell rc
KMONAD_SH = r"""
set -euo pipefail
[ "$(uname -m)" = x86_64 ] || { echo "kmonad publishes an x86_64 binary only" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -fsSL -o "$T/kmonad" https://github.com/kmonad/kmonad/releases/latest/download/kmonad
$SUDO install "$T/kmonad" /usr/local/bin/kmonad
"""


def _syntax_hl() -> bool:
    return any(Path(p).is_file() for p in SYNTAX_HL_PATHS)


def _fira_code() -> bool:
    if os_name() == "mac":
        return any(list(d.glob("FiraCode*")) or list(d.glob("Fira*Code*")) for d in FONT_DIRS if d.is_dir())
    rc, out = sh(["fc-list"])
    return rc == 0 and "fira code" in out.lower()


@dataclass(frozen=True)
class Tool:
    name: str
    why: str
    group: str  # core (the configs break without it) | extra (one feature needs it) | app (desktop apps)
    exe: str = ""  # a command whose presence means "installed"
    ver: str = "--version"  # flag that prints its version; "" = don't ask
    only: str = ""  # "" everywhere | "mac" | "desktop" (a Mac or a Linux desktop) | "linux-desktop"
    brew: str = ""  # Homebrew formula, or "cask:<name>" for an app
    apt: str = ""
    snap: str = ""  # installed with --classic
    pipx: str = ""
    sh: str = ""  # Linux: shell snippet (release downloads). $SUDO is "sudo", "sudo -n" or empty
    sh_desc: str = ""
    app: str = ""  # macOS: /Applications/<app>.app means "installed"
    hint: str = ""  # what to do by hand when this installer has no way to do it here
    check: Callable[[], bool] | None = None


TOOLS: list[Tool] = [
    # needed: the shell config, tmux config and file manager all assume these
    Tool("git", "version control", "core", "git", brew="git", apt="git"),
    Tool("zsh", "the shell", "core", "zsh", brew="zsh", apt="zsh"),
    Tool("stow", "links these dotfiles", "core", "stow", brew="stow", apt="stow"),
    Tool("tmux", "terminal multiplexer", "core", "tmux", "-V", brew="tmux", apt="tmux"),
    Tool("fzf", "fuzzy finder: Ctrl-R, Alt-T", "core", "fzf", brew="fzf", apt="fzf"),
    Tool("micro", "editor", "core", "micro", "-version", brew="micro", apt="micro"),
    Tool("yazi", "file manager: Ctrl-O", "core", "yazi", brew="yazi", snap="yazi"),
    Tool("zsh-syntax-highlighting", "colours the command line", "core", "", "", brew="zsh-syntax-highlighting",
         apt="zsh-syntax-highlighting", check=_syntax_hl),
    # optional: one feature each
    Tool("lazygit", "git UI, the `lg` alias", "extra", "lazygit", brew="lazygit", sh=LAZYGIT_SH, sh_desc="download the release from GitHub"),
    Tool("tree", "fzf Alt-C preview", "extra", "tree", brew="tree", apt="tree"),
    Tool("rich-cli", "yazi file previews", "extra", "rich", brew="rich-cli", pipx="rich-cli"),
    Tool("uv", "runs the bin/tui-* scripts and this tool", "extra", "uv", brew="uv", sh=UV_SH, sh_desc="official installer from astral.sh"),
    Tool("clippy", "yazi `y` copies files to the Mac clipboard", "extra", "clippy", only="mac", brew="neilberkman/clippy/clippy"),
    Tool("xclip", "tmux copy to the X11 clipboard", "extra", "xclip", "-version", only="linux-desktop", apt="xclip"),
    Tool("chafa", "bin/preview: images in the terminal", "extra", "chafa", only="desktop", brew="chafa", apt="chafa"),
    Tool("ffmpeg", "bin/collage", "extra", "ffmpeg", "-version", only="desktop", brew="ffmpeg", apt="ffmpeg"),
    Tool("gifski", "bin/collage: better-looking GIFs", "extra", "gifski", only="desktop", brew="gifski", hint="cargo install gifski"),
    # desktop apps
    Tool("ghostty", "terminal", "app", "ghostty", only="desktop", brew="cask:ghostty", snap="ghostty", app="Ghostty"),
    Tool("Fira Code", "terminal font", "app", "", "", only="desktop", brew="cask:font-fira-code", apt="fonts-firacode", check=_fira_code),
    Tool("hammerspoon", "key remapping and automation", "app", "", "", only="mac", brew="cask:hammerspoon", app="Hammerspoon"),
    Tool("rectangle", "window snapping", "app", "", "", only="mac", brew="cask:rectangle", app="Rectangle"),
    Tool("alt-tab", "window switcher", "app", "", "", only="mac", brew="cask:alt-tab", app="AltTab"),
    Tool("kmonad", "keyboard remap; then run kmonad/install.sh", "app", "kmonad", only="linux-desktop", sh=KMONAD_SH, sh_desc="download the release from GitHub"),
]


def applies(t: Tool) -> bool:
    if t.only == "mac":
        return os_name() == "mac"
    if t.only == "desktop":
        return is_desktop()
    if t.only == "linux-desktop":
        return os_name() == "linux" and is_desktop()
    return True


@dataclass
class ToolState:
    tool: Tool
    installed: bool
    version: str = ""


VER_RE = re.compile(r"\d+\.\d+(?:\.\d+)*[a-z]?")


def version_of(path: str, flag: str) -> str:
    if not flag:
        return ""
    try:
        p = subprocess.run([path, flag], capture_output=True, text=True, timeout=4, stdin=subprocess.DEVNULL)
    except (subprocess.TimeoutExpired, OSError):
        return ""
    m = VER_RE.search((p.stdout or "") + (p.stderr or ""))
    return m.group(0) if m else ""


def app_path(name: str) -> Path | None:
    return next((d / f"{name}.app" for d in APP_DIRS if (d / f"{name}.app").is_dir()), None)


def app_version(path: Path) -> str:
    try:
        return str(plistlib.loads((path / "Contents/Info.plist").read_bytes()).get("CFBundleShortVersionString", ""))
    except (OSError, plistlib.InvalidFileException, ValueError):
        return ""


def probe(t: Tool) -> ToolState:
    if t.check:
        return ToolState(t, bool(t.check()))
    exe = find(t.exe) if t.exe else None
    if exe:
        return ToolState(t, True, version_of(exe, t.ver))
    if os_name() == "mac" and t.app and (p := app_path(t.app)):
        return ToolState(t, True, app_version(p))
    return ToolState(t, False)


def probe_all() -> list[ToolState]:
    tools = [t for t in TOOLS if applies(t)]
    with ThreadPoolExecutor(max_workers=8) as ex:
        return list(ex.map(probe, tools))


# ----------------------------------------------------------------------------------------------------------------------
# what stow says


@dataclass
class Conflict:
    label: str  # path as stow reports it, relative to TARGET
    target: Path | None  # the existing file in the way
    kind: str  # identical | differs | other
    detail: str = ""


@dataclass
class Preflight:
    links: list[str] = field(default_factory=list)
    conflicts: list[Conflict] = field(default_factory=list)
    error: str = ""
    missing_stow: bool = False


def classify(target: Path, repo_file: Path) -> tuple[str, str]:
    if target.is_symlink():
        return "other", f"is a symlink to {target.readlink()}"
    if target.is_dir():
        return "other", "is a directory"
    if target.is_file() and repo_file.is_file():
        if filecmp.cmp(target, repo_file, shallow=False):
            return "identical", "same content as the repo copy"
        return "differs", "differs from the repo copy"
    return "other", "is not a plain file"


def stow_preflight() -> Preflight:
    stow = find("stow")
    if not stow:
        return Preflight(missing_stow=True)
    rc, out = sh([stow, "-n", "-v", "."], cwd=REPO)
    pre = Preflight()
    in_conflicts = False
    for line in out.splitlines():
        if line.startswith("LINK:"):
            pre.links.append(line.split(":", 1)[1].strip())
        elif "would cause conflicts" in line:
            in_conflicts = True
        elif in_conflicts and line.lstrip().startswith("*"):
            msg = line.lstrip()[1:].strip()
            for pat in CONFLICT_PATTERNS:
                m = pat.search(msg)
                if m:
                    rel = m.group("tgt")
                    kind, detail = classify(TARGET / rel, REPO / rel)
                    pre.conflicts.append(Conflict(rel, TARGET / rel, kind, detail))
                    break
            else:
                pre.conflicts.append(Conflict(msg, None, "other", "stow reported something this tool can't resolve"))
    if rc != 0 and not pre.conflicts:  # stow gave up without naming a conflict (2.3.x does this for a directory where a file belongs)
        m = re.search(r"called with non-directory path: (\S+)", out)
        errs = [ln.strip() for ln in out.splitlines() if "ERROR" in ln]
        if m:
            rel = m.group(1).split("/", 1)[-1]
            pre.error = f"{rel}: a directory is in the way of a file the repo links"
        else:
            pre.error = errs[0] if errs else f"stow exited {rc}: {out.strip()[-200:]}"
    return pre


def zsh_has_bootstrap() -> bool:
    return ZSHRC.is_file() and bool(BOOT_RE.search(ZSHRC.read_text()))


def login_shell() -> str:
    try:
        return pwd.getpwuid(os.getuid()).pw_shell
    except KeyError:
        return os.environ.get("SHELL", "")


def have_locale() -> bool:
    rc, out = sh(["locale", "-a"])
    return rc != 0 or bool(re.search(r"en_US\.utf-?8", out, re.I))  # if `locale` itself is missing, don't nag


# ----------------------------------------------------------------------------------------------------------------------
# status


@dataclass
class Check:
    status: str  # ok | warn | fail | info
    title: str
    detail: str = ""
    quiet: bool = False  # --check prints it, the UI leaves it out


def run_checks(pre: Preflight) -> list[Check]:
    out: list[Check] = []
    if pre.missing_stow:
        out.append(Check("info", "links wait for stow", "it is not installed yet"))
    elif pre.error:
        out.append(Check("fail", "stow can't run", pre.error))
    elif pre.conflicts:
        names = ", ".join(c.label for c in pre.conflicts[:4]) + (" ..." if len(pre.conflicts) > 4 else "")
        out.append(Check("fail", f"{len(pre.conflicts)} file{'s' if len(pre.conflicts) != 1 else ''} in your home block stow", names))
    else:
        out.append(Check("ok", "stow is clean", f"{len(pre.links)} new link{'s' if len(pre.links) != 1 else ''} to make" if pre.links else "everything is linked"))
    if TARGET.resolve() != HOME_R:
        out.append(Check("warn", "repo is not inside your home directory", f"stow links into {TARGET}, not {HOME}", quiet=True))

    if not ZSHRC.is_file():
        out.append(Check("fail", "~/.zshrc is missing", "the shared zsh config would not load"))
    elif zsh_has_bootstrap():
        out.append(Check("ok", "zsh loads the shared config"))
    else:
        out.append(Check("fail", "~/.zshrc does not load the shared zsh config"))

    if os.path.basename(login_shell()) != "zsh":
        out.append(Check("warn", "zsh is not your login shell", login_shell() or "unknown"))
    if os_name() == "linux" and not have_locale():
        out.append(Check("warn", "locale en_US.UTF-8 is missing", "exports.zsh sets it, so every command would warn"))

    dirty = git_dirty_tracked()
    if dirty:
        shown = ", ".join(dirty[:5]) + (f" (+{len(dirty) - 5} more)" if len(dirty) > 5 else "")
        out.append(Check("warn", f"{len(dirty)} tracked file(s) modified locally", shown, quiet=True))
    if os_name() != "mac" and ((REPO / "Library").exists() or (REPO / ".hammerspoon").exists()):
        out.append(Check("info", "Library/ and .hammerspoon/ are macOS-only", "stow still links them here; harmless", quiet=True))
    return out


# ----------------------------------------------------------------------------------------------------------------------
# what Apply does. Each action returns (level, message) or raises. Nothing of yours is deleted: the only file ever
# removed is one that is byte-identical to the copy in the repo.

Result = tuple[str, str]


def run(cmd: list[str], env: dict[str, str] | None = None, cwd: Path | None = None) -> tuple[int, str]:
    try:
        if LIVE:
            return subprocess.run(cmd, env=env, cwd=cwd).returncode, ""
        p = subprocess.run(cmd, env=env, cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
        return p.returncode, ((p.stdout or "") + (p.stderr or "")).strip()
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not found"


def must(cmd: list[str], what: str, env: dict[str, str] | None = None) -> None:
    rc, out = run(cmd, env=env)
    if rc:
        raise RuntimeError(f"{what} failed (exit {rc})" + (f": {out[-300:]}" if out else ""))


def sudo_cmd() -> list[str]:
    if os.geteuid() == 0:
        return []
    if not shutil.which("sudo"):
        raise RuntimeError("sudo is not installed and you are not root")
    return ["sudo"] if LIVE else ["sudo", "-n"]  # without a terminal sudo can't ask: fail fast instead of hanging


def brew_bin() -> str | None:
    for p in (shutil.which("brew"), *BREW_CANDIDATES):
        if p and os.access(p, os.X_OK):
            return p
    return None


def do_homebrew() -> Result:
    env = os.environ.copy()
    if not LIVE:
        env["NONINTERACTIVE"] = "1"
    must(["/bin/bash", "-c", 'eval "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'], "the Homebrew installer", env)
    if not brew_bin():
        raise RuntimeError("Homebrew installed but `brew` was not found afterwards")
    return "ok", "installed Homebrew"


def do_brew(kind: str, names: list[str]) -> Result:
    b = brew_bin()
    if not b:
        raise RuntimeError("Homebrew is not installed")
    args = ["install", *(["--cask"] if kind == "cask" else []), *names]
    must([b, *args], f"brew {' '.join(args)}")
    return "ok", f"installed with brew: {', '.join(names)}"


def apt_candidate(pkg: str) -> bool:
    rc, out = sh(["apt-cache", "policy", pkg])
    m = re.search(r"Candidate:\s*(\S+)", out)
    return rc == 0 and bool(m) and m.group(1) != "(none)"


def do_apt(pkgs: list[str]) -> Result:
    s = sudo_cmd()
    must([*s, "apt-get", "update"], "apt-get update")
    have = [p for p in pkgs if apt_candidate(p)]  # asked after the update: stale lists would hide real packages
    lacking = [p for p in pkgs if p not in have]
    if have:
        must([*s, "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", *have], "apt-get install")
    if lacking:
        return "warn", f"installed with apt: {', '.join(have) or 'nothing'}; this system's apt has no: {', '.join(lacking)}"
    return "ok", f"installed with apt: {', '.join(have)}"


def do_snap(name: str) -> Result:
    must([*sudo_cmd(), "snap", "install", name, "--classic"], f"snap install {name}")
    return "ok", f"installed {name} with snap"


def do_pipx(pkg: str) -> Result:
    p = find("pipx")
    if not p:
        raise RuntimeError("pipx is not installed")
    must([p, "install", pkg], f"pipx install {pkg}")
    return "ok", f"installed {pkg} with pipx"


def do_sh(t: Tool) -> Result:
    env = {**os.environ, "SUDO": " ".join(sudo_cmd()), "UV_NO_MODIFY_PATH": "1"}
    must(["bash", "-c", t.sh], f"installing {t.name}", env)
    return "ok", f"installed {t.name}"


def do_locale() -> Result:
    s = sudo_cmd()
    must([*s, "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "locales"], "installing locales")
    must([*s, "locale-gen", "en_US.UTF-8"], "locale-gen")
    must([*s, "update-locale", "LANG=en_US.UTF-8"], "update-locale")
    return "ok", "generated the en_US.UTF-8 locale"


def zsh_for_chsh() -> str | None:
    try:
        listed = {ln.strip() for ln in Path("/etc/shells").read_text().splitlines()}
    except OSError:
        listed = set()
    for p in ("/usr/bin/zsh", "/bin/zsh", find("zsh")):
        if p and os.path.exists(p) and (p in listed or not listed):
            return p
    return None


def do_chsh() -> Result:
    z = zsh_for_chsh()
    if not z:
        raise RuntimeError("no zsh listed in /etc/shells")
    user = pwd.getpwuid(os.getuid()).pw_name
    must([*sudo_cmd(), "chsh", "-s", z, user], "chsh")  # sudo: cloud accounts have no password, plain chsh fails
    return "ok", f"login shell set to {z} (takes effect on next login)"


def do_replace(cf: Conflict) -> Result:
    t = cf.target
    if t is None or (not t.exists() and not t.is_symlink()):
        return "ok", f"{cf.label}: already gone"
    if t.is_symlink() or not t.is_file():
        raise RuntimeError(f"{cf.label}: not a plain file, resolve by hand")
    if not filecmp.cmp(t, REPO / cf.label, shallow=False):  # asked again right before removing
        raise RuntimeError(f"{cf.label}: changed since the check, not touching it")
    t.unlink()
    return "ok", f"{cf.label}: replaced by a link (it was identical to the repo copy)"


def do_bootstrap() -> Result:
    if not ZSHRC.exists():
        template = REPO / ".zshrc"  # the repo's starter file (not linked: installers append to ~/.zshrc)
        ZSHRC.write_text(template.read_text() if template.is_file() and BOOT_RE.search(template.read_text()) else BOOTSTRAP_LINE + "\n")
        return "ok", "created ~/.zshrc from the repo's template"
    real = ZSHRC.resolve()
    old = real.read_text()
    if BOOT_RE.search(old):
        return "ok", "~/.zshrc already loads init.zsh"
    new = BOOTSTRAP_LINE + "\n\n" + old
    ok, err = zsh_syntax_ok(new)
    if not ok:
        raise RuntimeError(f"refusing to write ~/.zshrc, syntax check failed: {err}")
    tmp = real.with_name(real.name + ".dotfiles-tmp")
    tmp.write_text(new)
    shutil.copymode(real, tmp)
    os.replace(tmp, real)  # one atomic swap; the change is a single added line at the top
    return "ok", "added the init.zsh line to the top of ~/.zshrc"


def do_stow() -> Result:
    pre = stow_preflight()
    if pre.missing_stow:
        raise RuntimeError("stow is still not installed")
    if pre.error:
        return "warn", pre.error
    if pre.conflicts:
        return "warn", f"not linked yet: {len(pre.conflicts)} file{'s' if len(pre.conflicts) != 1 else ''} still in the way"
    rc, out = sh([find("stow") or "stow", "-v", "."], cwd=REPO)
    if rc != 0:
        raise RuntimeError(out.strip()[-400:])
    n = sum(1 for ln in out.splitlines() if ln.startswith("LINK:"))
    return "ok", f"linked {n} item{'s' if n != 1 else ''}" if n else "nothing new to link"


@dataclass
class Step:
    desc: str
    fn: Callable[[], Result]


@dataclass
class Plan:
    install: list[Step] = field(default_factory=list)  # system changes; may need sudo, so they run in the real terminal
    dotfiles: list[Step] = field(default_factory=list)  # changes in your home
    blockers: list[str] = field(default_factory=list)  # things only the user can fix
    notes: list[str] = field(default_factory=list)  # optional things this installer can't do here

    @property
    def steps(self) -> list[Step]:
        return self.install + self.dotfiles


def install_steps(missing: list[Tool]) -> tuple[list[Step], list[str], list[str], set[str]]:
    """-> (steps, blockers, notes, stuck tool names). A needed tool with no way to install it is a blocker, an optional one
    a note; tools stuck for the same reason share one line."""
    steps: list[Step] = []
    stuck: set[str] = set()
    why_not: dict[tuple[bool, str], list[str]] = {}

    def cannot(t: Tool, why: str) -> None:
        stuck.add(t.name)
        why_not.setdefault((t.group == "core", why), []).append(t.name + (f" ({t.hint})" if t.hint else ""))

    if os_name() == "mac":
        formulae, casks = [], []
        for t in missing:
            if not t.brew:
                cannot(t, "no Homebrew package known")
            elif t.brew.startswith("cask:"):
                casks.append(t.brew[5:])
            else:
                formulae.append(t.brew)
        if (formulae or casks) and not brew_bin():
            steps.append(Step("install Homebrew (the official installer from brew.sh)", do_homebrew))
        if formulae:
            steps.append(Step(f"install with brew: {', '.join(formulae)}", lambda f=formulae: do_brew("formula", f)))
        if casks:
            steps.append(Step(f"install apps with brew: {', '.join(casks)}", lambda c=casks: do_brew("cask", c)))
    else:
        have_apt = bool(shutil.which("apt-get"))
        # With fresh package lists we already know which packages this release lacks (22.04 has no git-delta, say).
        # On a new VM the lists are empty, so everything is asked again after `apt-get update` (see do_apt).
        lists_fresh = have_apt and apt_candidate("git")
        apt_pkgs, snaps, pipxs, shs = [], [], [], []
        for t in missing:
            if t.apt and have_apt and lists_fresh and not apt_candidate(t.apt):
                cannot(t, "this system's apt has no package for it")
            elif t.apt and have_apt:
                apt_pkgs.append(t.apt)
            elif t.snap and find("snap"):
                snaps.append(t)
            elif t.pipx and have_apt:
                pipxs.append(t)
            elif t.sh:
                shs.append(t)
            elif t.apt:
                cannot(t, "this installer only knows apt (Ubuntu/Debian)")
            elif t.snap:
                cannot(t, "snap is not installed")
            else:
                cannot(t, "no package for this system")
        if pipxs and not find("pipx"):
            apt_pkgs.append("pipx")
        if shs and not find("curl") and have_apt:
            apt_pkgs.append("curl")
        if apt_pkgs:
            steps.append(Step(f"install with apt: {', '.join(apt_pkgs)}", lambda p=apt_pkgs: do_apt(p)))
        for t in snaps:
            steps.append(Step(f"install {t.name} with snap", lambda n=t.snap: do_snap(n)))
        for t in pipxs:
            steps.append(Step(f"install {t.name} with pipx", lambda p=t.pipx: do_pipx(p)))
        for t in shs:
            steps.append(Step(f"install {t.name} ({t.sh_desc})", lambda t=t: do_sh(t)))
    blockers = [f"{', '.join(names)}: {why}" for (core, why), names in why_not.items() if core]
    notes = [f"{', '.join(names)}: {why}" for (core, why), names in why_not.items() if not core]
    return steps, blockers, notes, stuck


def make_plan(pre: Preflight, states: list[ToolState]) -> Plan:
    plan = Plan()
    plan.install, plan.blockers, plan.notes, stuck = install_steps([s.tool for s in states if not s.installed])

    if os_name() == "linux" and not have_locale() and shutil.which("apt-get"):
        plan.install.append(Step("generate the en_US.UTF-8 locale", do_locale))
    if os.path.basename(login_shell()) != "zsh" and (find("zsh") or any(s.tool.name == "zsh" and not s.installed for s in states)):
        plan.install.append(Step("make zsh your login shell (sudo chsh)", do_chsh))

    if pre.error:
        plan.blockers.append(pre.error)
    if pre.missing_stow and "stow" not in stuck:  # the real list of links and conflicts is only known once stow exists: Apply re-plans after installing
        plan.dotfiles.append(Step("link everything with stow", do_stow))
    # A file that differs from the repo copy (or a symlink, or a directory) is something only you can judge. While any
    # of those exist nothing is replaced and nothing is linked, so the home directory is never left half-linked.
    unresolved = [cf for cf in pre.conflicts if cf.kind != "identical"]
    plan.blockers += [f"{cf.label} {cf.detail}" for cf in unresolved]
    if not zsh_has_bootstrap():
        plan.dotfiles.append(Step("make ~/.zshrc load the shared zsh config", do_bootstrap))
    if not unresolved and not pre.error and not pre.missing_stow:
        for cf in pre.conflicts:  # same bytes as the repo copy: removing it loses nothing
            plan.dotfiles.append(Step(f"replace {cf.label} with a link", lambda cf=cf: do_replace(cf)))
        if pre.links or pre.conflicts:
            plan.dotfiles.append(Step("link everything with stow", do_stow))
    return plan


def build_plan() -> tuple[Preflight, list[ToolState], Plan]:
    pre, states = stow_preflight(), probe_all()
    return pre, states, make_plan(pre, states)


def run_steps(steps: list[Step], log: Callable[[str, str], None], announce: Callable[[str], None] | None = None) -> bool:
    for s in steps:
        if announce:
            announce(s.desc)
        try:
            level, msg = s.fn()
        except Exception as exc:  # stop at the first failure rather than leave a half-applied mix
            log("fail", f"{s.desc}: {exc}")
            return False
        log(level, msg)
    return True


def run_plan(plan: Plan, log: Callable[[str, str], None], announce: Callable[[str], None] | None = None) -> bool:
    """Installs first, then the dotfiles part, which is re-planned afterwards: with stow now present its conflicts are known."""
    if plan.install:
        if not run_steps(plan.install, log, announce):
            return False
        plan = build_plan()[2]
    return run_steps(plan.dotfiles, log, announce)


# ----------------------------------------------------------------------------------------------------------------------
# text interface (--check, --plain)

SYM = {"ok": "✔", "warn": "⚠", "fail": "✖", "info": "•"}


def print_status(pre: Preflight, states: list[ToolState], plan: Plan) -> None:
    print(f"{machine_kind()} {platform.machine()} · {socket.gethostname()}")
    print(f"repo {REPO}  ->  links into {TARGET}\n")
    for key, label in (("core", "Needed"), ("extra", "Optional"), ("app", "Desktop apps")):
        rows = [s for s in states if s.tool.group == key]
        if not rows:
            continue
        print(label)
        for s in rows:
            if s.installed:
                print(f"  ✔ {s.tool.name:<24} {s.version}")
            else:
                mark, word = ("✖", "missing") if key == "core" else ("○", "not installed")
                print(f"  {mark} {s.tool.name:<24} {word}  ({s.tool.why})")
    print()
    for c in run_checks(pre):
        print(f"{SYM[c.status]} {c.title}" + (f"  ({c.detail})" if c.detail else ""))
    if plan.steps or plan.blockers or plan.notes:
        print("\nApply would:")
        for i, s in enumerate(plan.steps, 1):
            print(f"  {i}. {s.desc}")
        for b in plan.blockers:
            print(f"  ! needs you: {b}")
        for n in plan.notes:
            print(f"  - can't install here: {n}")


def exit_code(pre: Preflight, states: list[ToolState]) -> int:
    needed_missing = any(not s.installed and s.tool.group == "core" for s in states)
    return 1 if needed_missing or any(c.status == "fail" for c in run_checks(pre)) else 0


def apply_live(plan: Plan, log: Callable[[str, str], None]) -> bool:
    """Run in the real terminal: sudo can prompt, installers print as they go."""
    global LIVE
    LIVE = True
    # Ctrl-C at a sudo or apt prompt has to stop that command, not this tool. A handler that does nothing (unlike "ignore")
    # is reset to the default in the child, so the child still dies, while we carry on and report the failed step.
    previous = signal.signal(signal.SIGINT, lambda *_: None)
    try:
        return run_plan(plan, log, announce=lambda d: print(f"\n\033[1m▶ {d}\033[0m", flush=True))
    finally:
        signal.signal(signal.SIGINT, previous)
        LIVE = False


def cli(plain: bool) -> int:
    pre, states, plan = build_plan()
    print_status(pre, states, plan)
    if not plain:
        return exit_code(pre, states)
    if not plan.steps:
        return exit_code(pre, states)
    try:
        answer = input(f"\nApply these {len(plan.steps)} step{'s' if len(plan.steps) != 1 else ''}? [y/N] ")
    except EOFError:
        answer = ""
    if answer.strip().lower() not in ("y", "yes"):
        print("Nothing changed.")
        return exit_code(pre, states)
    ok = apply_live(plan, lambda level, msg: print(f"  {SYM.get(level, '•')} {msg}", flush=True))
    pre, states, plan = build_plan()
    print("\nAfter:")
    print_status(pre, states, plan)
    return 0 if ok and exit_code(pre, states) == 0 else 1


# ----------------------------------------------------------------------------------------------------------------------
# UI


def make_app():
    """One-screen Textual UI. textual is imported here so `--check` and `--plain` need nothing installed."""
    from rich.console import Group
    from rich.markup import escape
    from rich.table import Table
    from rich.text import Text
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Horizontal, Vertical, VerticalScroll
    from textual.widgets import Button, Footer, Header, Static

    try:
        from textual.app import SuspendNotSupported
    except ImportError:  # older textual
        SuspendNotSupported = RuntimeError  # type: ignore[misc,assignment]

    ICON = {"ok": "[green]✔[/]", "warn": "[yellow]⚠[/]", "fail": "[red]✖[/]", "info": "[dim]•[/]"}

    def tool_column(states: list[ToolState], groups: list[tuple[str, str]]) -> Table:
        t = Table.grid(padding=(0, 2))
        t.add_column(width=1)
        t.add_column(no_wrap=True)
        t.add_column(no_wrap=True)
        first = True
        for key, label in groups:
            rows = [s for s in states if s.tool.group == key]
            if not rows:
                continue
            if not first:
                t.add_row("", "", "")
            first = False
            t.add_row("", Text(label, style="bold dim"), "")
            for s in rows:
                if s.installed:
                    t.add_row(Text("✔", "green"), Text(s.tool.name), Text(s.version, "dim"))
                elif s.tool.group == "core":
                    t.add_row(Text("✖", "red"), Text(s.tool.name, "red"), Text("missing", "red"))
                else:
                    t.add_row(Text("○", "yellow"), Text(s.tool.name), Text("not installed", "yellow"))
        return t

    class SetupApp(App):
        TITLE = "Dotfiles setup"
        CSS = """
        Screen { layout: vertical; }
        #main { padding: 1 2; align-horizontal: center; }
        #body { width: 100%; max-width: 96; height: auto; }
        #banner { height: auto; padding: 0 1 1 1; text-style: bold; }
        .panel { border: round $primary; border-title-color: $accent; border-title-style: bold; padding: 1 2; margin-bottom: 1; height: auto; }
        #btn-row { height: 3; align-horizontal: right; }
        #btn-apply { margin-right: 1; }
        """
        BINDINGS = [
            Binding("ctrl+q", "quit", "Quit"),
            Binding("q", "quit", "Quit", show=False),
            Binding("enter", "apply", "Apply"),
            Binding("r", "refresh", "Re-check"),
        ]

        plan: Plan

        def compose(self) -> ComposeResult:
            yield Header(show_clock=False, icon="")
            with VerticalScroll(id="main"):
                with Vertical(id="body"):
                    yield Static(id="banner")
                    yield Static(id="status", classes="panel")
                    yield Static(id="plan", classes="panel")
                    yield Static(id="result", classes="panel")
                    with Horizontal(id="btn-row"):
                        yield Button("Apply", variant="primary", id="btn-apply")
                        yield Button("Quit", variant="default", id="btn-quit")
            yield Footer()

        def on_mount(self) -> None:
            self.sub_title = f"{machine_kind()} · {socket.gethostname()}"
            self.query_one("#status").border_title = "Status"
            self.query_one("#plan").border_title = "Apply will"
            self.query_one("#result").border_title = "Result"
            self.query_one("#result").display = False
            self.reload()

        def reload(self) -> None:
            pre, states, self.plan = build_plan()
            grid = Table.grid(expand=True, padding=(0, 3))
            grid.add_column(ratio=1)
            grid.add_column(ratio=1)
            grid.add_row(tool_column(states, [("core", "Needed"), ("app", "Desktop apps")]), tool_column(states, [("extra", "Optional")]))
            rows = [c for c in run_checks(pre) if not c.quiet]
            dot = Text.from_markup("\n".join(f"{ICON[c.status]}  {escape(c.title)}" + (f"  [dim]{escape(c.detail)}[/]" if c.detail else "") for c in rows))
            self.query_one("#status", Static).update(Group(grid, Text(""), dot))

            p = self.plan
            rows = Table.grid(padding=(0, 2))  # a marker column, so a long line wraps under its own text
            rows.add_column(width=2, no_wrap=True)
            rows.add_column(ratio=1)
            for i, s in enumerate(p.steps, 1):
                rows.add_row(Text(str(i), "dim"), Text(s.desc))
            for b in p.blockers:
                rows.add_row(Text("✖", "red"), Text.assemble(("needs you: ", "bold"), b))
            for n in p.notes:
                rows.add_row(Text("·", "dim"), Text(f"can't install here: {n}", "dim"))
            parts: list = [rows]
            if p.blockers:
                parts += [Text(""), Text("Linking waits for these. Compare each with the repo copy (diff), delete the one you don't want, then press r.", "dim")]
            plan_box = self.query_one("#plan", Static)
            plan_box.update(Group(*parts))
            plan_box.display = bool(p.steps or p.blockers or p.notes)

            n = len(p.steps)
            if p.blockers:
                head = "[b red]Needs you[/]" + (f"  [dim]· {n} thing{'s' if n != 1 else ''} Apply can do meanwhile[/]" if n else "")
            elif n:
                head = f"[b yellow]{n} thing{'s' if n != 1 else ''} to do[/]"
            else:
                head = "[b green]All set.[/] Nothing to do on this machine."
            self.query_one("#banner", Static).update(head)
            self.query_one("#btn-apply", Button).disabled = not n

        def action_apply(self) -> None:
            if not self.plan.steps:
                self.notify("Nothing to do")
                return
            results: list[str] = []
            log = lambda level, msg: results.append(f"{ICON.get(level, ICON['info'])}  {escape(msg)}")  # noqa: E731
            ok = None
            if self.plan.install:  # installers need the real terminal: sudo asks for a password, brew/apt print progress
                try:
                    with self.suspend():
                        print("\n\033[1mDotfiles setup\033[0m: applying\n", flush=True)
                        ok = apply_live(self.plan, lambda level, msg: (log(level, msg), print(f"  {SYM.get(level, '•')} {msg}", flush=True)))
                        try:
                            input("\nPress Enter to go back to the setup screen ")
                        except EOFError:
                            pass
                except SuspendNotSupported:
                    ok = None
            if ok is None:
                ok = run_plan(self.plan, log)
            box = self.query_one("#result", Static)
            box.update("\n".join(results))
            box.display = True
            if not ok:
                self.notify("Stopped on an error", severity="error")
            self.reload()

        def action_refresh(self) -> None:
            self.reload()

        def on_button_pressed(self, event: Button.Pressed) -> None:
            if event.button.id == "btn-quit":
                self.exit()
            elif event.button.id == "btn-apply":
                self.action_apply()

    return SetupApp()


def main() -> int:
    ap = argparse.ArgumentParser(description="Install what these dotfiles need and link them.")
    ap.add_argument("--check", action="store_true", help="print the status and exit 1 if something needed is missing or blocked (no UI)")
    ap.add_argument("--plain", action="store_true", help="the same flow as plain text with a y/N question (no UI)")
    args = ap.parse_args()
    if args.check or args.plain:
        return cli(plain=args.plain)
    make_app().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())

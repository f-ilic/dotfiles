#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["textual>=0.80"]
# ///
"""Set up these dotfiles on any machine: stow preflight, conflict resolution, zsh bootstrap, local override files.

Day to day it is just ``git pull && stow .``. Run ``./start.sh`` the first time on a machine, or whenever
``stow .`` complains. Nothing is ever deleted: a file that gets replaced is moved to ``~/.dotfiles-backup/<timestamp>/``.
Every change is listed and confirmed before anything is touched.

``./start.sh --check`` prints the same checks without a UI (stdlib only, no textual needed) and exits 1 if something is
blocking, so it also works over a bare SSH session or in a script.

What belongs where:
  tracked files (this repo)   identical on every machine; OS differences are detected in code, never toggled by hand
  ``~/.config/zsh/local.zsh``    this machine only, gitignored, sourced last by init.zsh
  ``~/.config/ghostty/config.local``  this machine only, gitignored, pulled in by ``config-file = ?config.local``
  ``~/.zshrc``                  one-line bootstrap, plus whatever installers (conda, gcloud, ...) append to it
"""

from __future__ import annotations

import argparse
import difflib
import filecmp
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[1]  # ~/dotfiles
TARGET = REPO.parent  # where `stow .`, run inside REPO, puts its links
HOME = Path.home()
HOME_R = HOME.resolve()  # paths from stow come back resolved (macOS: /tmp is really /private/tmp), so compare both
ZSHRC = HOME / ".zshrc"
LOCAL_ZSH = REPO / ".config/zsh/local.zsh"
GHOSTTY_CFG = REPO / ".config/ghostty/config"
GHOSTTY_LOCAL = REPO / ".config/ghostty/config.local"
BACKUP_ROOT = HOME / ".dotfiles-backup"

BOOTSTRAP_LINE = 'source "${HOME}/.config/zsh/init.zsh"'
BOOT_RE = re.compile(r"config/zsh/init\.zsh")
SECRET_RE = re.compile(r"(TOKEN|SECRET|PASSW(OR)?D|API_?KEY|PRIVATE_?KEY|ACCESS_?KEY)\w*\s*=", re.I)
MANAGED_RE = re.compile(r"^#\s*>>>\s*(.+?)\s*>>>\s*$")  # e.g. "# >>> conda initialize >>>"
GHOSTTY_INCLUDE_RE = re.compile(r"^\s*config-file\s*=\s*\?config\.local\s*$", re.M)
CONFLICT_PATTERNS = [
    re.compile(r"cannot stow (?P<src>\S+) over existing target (?P<tgt>\S+) since"),
    re.compile(r"existing target is not owned by stow: (?P<tgt>\S+)"),
    re.compile(r"existing target is neither a link nor a directory: (?P<tgt>\S+)"),
    re.compile(r"existing target is stowed to a different package: (?P<tgt>\S+)"),
]

LOCAL_ZSH_TEMPLATE = """# Machine-local zsh settings for THIS machine. Gitignored; init.zsh sources it last.
# Put whatever differs per machine here instead of editing tracked files, e.g.:
#   PROMPT="%n@myhost:%{$fg[cyan]%}%~%{$reset_color%}> "
"""
GHOSTTY_LOCAL_TEMPLATE = """# Machine-local ghostty settings for THIS machine. Gitignored; included by `config-file = ?config.local`.
# Later keys override the tracked config, e.g.:
#   window-decoration = true
"""


# ----------------------------------------------------------------------------------------------------------------------
# helpers


def sh(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not found"
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def stow_version() -> str:
    rc, out = sh(["stow", "--version"])
    return out.strip().splitlines()[0] if rc == 0 and out.strip() else "?"


def git_dirty_tracked() -> list[str]:
    """Tracked files that differ from HEAD: per-machine edits that block `git pull` when upstream touches them."""
    rc, out = sh(["git", "-C", str(REPO), "status", "--porcelain", "-uno"])
    return [line[3:] for line in out.splitlines()] if rc == 0 else []


def git_clean(path: Path) -> bool:
    return sh(["git", "-C", str(REPO), "diff", "--quiet", "HEAD", "--", str(path)])[0] == 0


def mask(line: str) -> str:
    """Never show a secret's value anywhere in the UI or the log."""
    if SECRET_RE.search(line) and "=" in line:
        return line.split("=", 1)[0] + "=<hidden>"
    return line


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


def backup_dest(path: Path, stamp: str) -> Path:
    rel = Path(path.name)
    for base in (HOME, HOME_R):
        if path.is_relative_to(base):
            rel = path.relative_to(base)
            break
    dest = BACKUP_ROOT / stamp / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    return dest


# ----------------------------------------------------------------------------------------------------------------------
# stow preflight


@dataclass
class Conflict:
    label: str  # path as stow reports it, relative to TARGET
    target: Path | None  # the existing file in the way
    repo: Path | None  # the repo file stow wants to link there
    kind: str  # identical | differs | other
    detail: str = ""
    diff: str = ""

    @property
    def replaceable(self) -> bool:
        return self.kind in ("identical", "differs")


@dataclass
class Preflight:
    links: list[str] = field(default_factory=list)
    conflicts: list[Conflict] = field(default_factory=list)
    error: str = ""


def classify(target: Path, repo_file: Path) -> tuple[str, str, str]:
    if target.is_symlink():
        return "other", f"is a symlink to {target.readlink()}", ""
    if target.is_dir():
        return "other", "is a directory", ""
    if target.is_file() and repo_file.is_file():
        if filecmp.cmp(target, repo_file, shallow=False):
            return "identical", "same content as the repo copy", ""
        try:
            a = target.read_text().splitlines()
            b = repo_file.read_text().splitlines()
            diff = list(difflib.unified_diff(a, b, "your file", "repo file", lineterm="", n=1))
            shown = "\n".join(mask(d) for d in diff[:14]) + ("\n..." if len(diff) > 14 else "")
        except UnicodeDecodeError:
            shown = "(binary file)"
        return "differs", "content differs from the repo copy", shown
    return "other", "unexpected file type", ""


def stow_preflight() -> Preflight:
    if not shutil.which("stow"):
        return Preflight(error="stow is not installed (brew install stow / apt install stow)")
    _rc, out = sh(["stow", "-n", "-v", "."], cwd=REPO)
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
                    kind, detail, diff = classify(TARGET / rel, REPO / rel)
                    pre.conflicts.append(Conflict(rel, TARGET / rel, REPO / rel, kind, detail, diff))
                    break
            else:
                pre.conflicts.append(Conflict(msg, None, None, "other", "stow reported something this tool can't resolve"))
    return pre


# ----------------------------------------------------------------------------------------------------------------------
# ~/.zshrc: split into blocks so the user can pick what moves to local.zsh


@dataclass
class Seg:
    kind: str  # blank | comment | movable | managed | secret | bootstrap
    lines: list[str]

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


def parse_zshrc(text: str) -> list[Seg]:
    lines = text.splitlines()
    segs: list[Seg] = []
    cur: list[str] = []

    def flush() -> None:
        if not cur:
            return
        body = "\n".join(cur)
        if BOOT_RE.search(body):
            kind = "bootstrap"
        elif SECRET_RE.search(body):
            kind = "secret"
        elif all(ln.lstrip().startswith("#") for ln in cur):
            kind = "comment"
        else:
            kind = "movable"
        segs.append(Seg(kind, list(cur)))
        cur.clear()

    i = 0
    while i < len(lines):
        line = lines[i]
        m = MANAGED_RE.match(line)
        if m:  # a block an installer manages and rewrites in place (conda init): never move it
            flush()
            end = re.compile(r"^#\s*<<<\s*" + re.escape(m.group(1)) + r"\s*<<<\s*$")
            j = i
            while j < len(lines) and not end.match(lines[j]):
                j += 1
            segs.append(Seg("managed", lines[i : j + 1]))
            i = j + 1
        elif not line.strip():
            flush()
            if segs and segs[-1].kind == "blank":
                segs[-1].lines.append("")
            else:
                segs.append(Seg("blank", [""]))
            i += 1
        else:
            cur.append(line)
            i += 1
    flush()
    return segs


def render_zshrc(segs: list[Seg]) -> str:
    out: list[str] = []
    for s in segs:
        if s.kind == "blank":
            if out and out[-1] != "":
                out.append("")  # collapse runs of blank lines
        else:
            out.extend(s.lines)
    return "\n".join(out).strip("\n") + "\n"


def load_segs() -> list[Seg] | None:
    return parse_zshrc(ZSHRC.read_text()) if ZSHRC.is_file() else None


def zsh_has_bootstrap() -> bool:
    return ZSHRC.is_file() and bool(BOOT_RE.search(ZSHRC.read_text()))


# ----------------------------------------------------------------------------------------------------------------------
# checks (shared by the TUI and --check)


@dataclass
class Check:
    status: str  # ok | warn | fail | info
    title: str
    detail: str = ""


def ghostty_state() -> str:
    """ok | missing (safe to add the include) | dirty (tracked file has local edits: leave it) | absent"""
    if not GHOSTTY_CFG.is_file():
        return "absent"
    if GHOSTTY_INCLUDE_RE.search(GHOSTTY_CFG.read_text(errors="ignore")):
        return "ok"
    return "missing" if git_clean(GHOSTTY_CFG) else "dirty"


def run_checks(pre: Preflight) -> list[Check]:
    out: list[Check] = []
    if pre.error:
        out.append(Check("fail", "stow", pre.error))
    elif pre.conflicts:
        names = ", ".join(c.label for c in pre.conflicts[:4]) + (" ..." if len(pre.conflicts) > 4 else "")
        out.append(Check("fail", f"`stow .` would hit {len(pre.conflicts)} conflict(s)", names))
    else:
        out.append(Check("ok", "`stow .` is clean", f"{len(pre.links)} link(s) pending" if pre.links else "everything is linked"))
    if TARGET.resolve() != HOME_R:
        out.append(Check("warn", "repo is not inside your home directory", f"stow links into {TARGET}, not {HOME}"))

    if not ZSHRC.is_file():
        out.append(Check("fail", "~/.zshrc is missing", "zsh config would not load"))
    elif zsh_has_bootstrap():
        out.append(Check("ok", "~/.zshrc loads init.zsh"))
    else:
        out.append(Check("fail", "~/.zshrc does not load init.zsh", "the shared zsh config is not active"))
    out.append(Check("info", "local.zsh " + ("exists" if LOCAL_ZSH.is_file() else "not created yet"), "per-machine zsh settings, gitignored"))

    gs = ghostty_state()
    if gs == "ok":
        out.append(Check("info", "ghostty config includes config.local " + ("(exists)" if GHOSTTY_LOCAL.is_file() else "(not created yet)")))
    elif gs == "missing":
        out.append(Check("warn", "ghostty config has no `config-file = ?config.local` line", "the tool can add it (tracked file, you commit it)"))
    elif gs == "dirty":
        out.append(Check("warn", "ghostty config has local edits vs the repo", "per-machine tweaks belong in config.local; clean the tracked file first"))

    dirty = git_dirty_tracked()
    if dirty:
        shown = ", ".join(dirty[:5]) + (f" (+{len(dirty) - 5} more)" if len(dirty) > 5 else "")
        out.append(Check("warn", f"{len(dirty)} tracked file(s) modified locally", shown))
    if platform.system() != "Darwin" and ((REPO / "Library").exists() or (REPO / ".hammerspoon").exists()):
        out.append(Check("info", "Library/ and .hammerspoon/ are macOS-only", "stow still links them here; harmless"))
    return out


def machine_summary() -> str:
    _rc, branch = sh(["git", "-C", str(REPO), "rev-parse", "--abbrev-ref", "HEAD"])
    return f"{platform.system()} {platform.machine()} · {socket.gethostname()} · {stow_version()} · git {branch.strip() or '?'}\nrepo {REPO}  ->  links into {TARGET}"


# ----------------------------------------------------------------------------------------------------------------------
# actions. Each returns (level, message) and raises on a real failure; none of them deletes anything.


Result = tuple[str, str]


def do_replace(cf: Conflict, stamp: str) -> Result:
    assert cf.target is not None
    if not cf.target.exists() and not cf.target.is_symlink():
        return "ok", f"{cf.label}: already gone"
    if not cf.replaceable or cf.target.is_symlink() or cf.target.is_dir():
        raise RuntimeError(f"{cf.label}: not a plain file, resolve by hand")
    dest = backup_dest(cf.target, stamp)
    shutil.move(str(cf.target), str(dest))
    return "ok", f"{cf.label}: old copy moved to {dest}"


def do_bootstrap(stamp: str) -> Result:
    if not ZSHRC.exists():
        ZSHRC.write_text(BOOTSTRAP_LINE + "\n")
        return "ok", "created ~/.zshrc with the init.zsh bootstrap"
    old = ZSHRC.read_text()
    if BOOT_RE.search(old):
        return "ok", "~/.zshrc already loads init.zsh"
    new = BOOTSTRAP_LINE + "\n\n" + old
    ok, err = zsh_syntax_ok(new)
    if not ok:
        raise RuntimeError(f"refusing to write ~/.zshrc, syntax check failed: {err}")
    shutil.copy2(ZSHRC, backup_dest(ZSHRC, stamp))
    ZSHRC.write_text(new)
    return "ok", f"added the bootstrap line to ~/.zshrc (backup in {BACKUP_ROOT / stamp})"


def do_migrate(texts: list[str], stamp: str) -> Result:
    """Move the chosen blocks from ~/.zshrc into local.zsh. Works from the file as it is NOW, matches blocks by text."""
    if not zsh_has_bootstrap():
        raise RuntimeError("~/.zshrc does not load init.zsh yet, so moved blocks would stop running; add the bootstrap first")
    segs = parse_zshrc(ZSHRC.read_text())
    wanted, moved, kept = set(texts), [], []
    for s in segs:
        if s.kind == "movable" and s.text in wanted:
            moved.append(s)
        else:
            kept.append(s)
    if not moved:
        return "warn", "none of the chosen blocks are in ~/.zshrc any more"
    new_rc = render_zshrc(kept)
    head = f"\n# --- moved from ~/.zshrc by dotfiles setup on {datetime.now():%Y-%m-%d} ---\n"
    new_local = (LOCAL_ZSH.read_text() if LOCAL_ZSH.is_file() else LOCAL_ZSH_TEMPLATE).rstrip("\n") + "\n" + head
    new_local += "\n\n".join(s.text for s in moved) + "\n"
    for name, body in (("~/.zshrc", new_rc), ("local.zsh", new_local)):
        ok, err = zsh_syntax_ok(body)
        if not ok:
            raise RuntimeError(f"nothing written: the new {name} fails `zsh -n` ({err})")
    shutil.copy2(ZSHRC, backup_dest(ZSHRC, stamp))
    if LOCAL_ZSH.is_file():
        shutil.copy2(LOCAL_ZSH, backup_dest(LOCAL_ZSH, stamp))
    LOCAL_ZSH.parent.mkdir(parents=True, exist_ok=True)
    LOCAL_ZSH.write_text(new_local)
    ZSHRC.write_text(new_rc)
    return "ok", f"moved {len(moved)} block(s) into local.zsh; originals backed up in {BACKUP_ROOT / stamp}"


def do_make_local(path: Path, template: str) -> Result:
    if path.exists():
        return "ok", f"{path.name} already exists"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(template)
    return "ok", f"created {path.relative_to(REPO)}"


def do_ghostty_include() -> Result:
    state = ghostty_state()
    if state != "missing":
        return "warn", f"ghostty include not added (state: {state})"
    with GHOSTTY_CFG.open("a") as f:
        f.write("\n# per-machine overrides (gitignored)\nconfig-file = ?config.local\n")
    return "ok", "added `config-file = ?config.local` to the tracked ghostty config; commit it when you are ready"


def do_stow() -> Result:
    pre = stow_preflight()
    if pre.error:
        return "warn", pre.error
    if pre.conflicts:
        return "warn", f"stow skipped: {len(pre.conflicts)} conflict(s) remain"
    rc, out = sh(["stow", "-v", "."], cwd=REPO)
    if rc != 0:
        raise RuntimeError(out.strip()[-400:])
    n = sum(1 for ln in out.splitlines() if ln.startswith("LINK:"))
    return "ok", f"stow . linked {n} item(s)" if n else "stow . had nothing to do"


@dataclass
class Choices:
    replace: list[Conflict] = field(default_factory=list)
    bootstrap: bool = False
    move_blocks: list[str] = field(default_factory=list)  # exact block texts
    make_local_zsh: bool = False
    make_local_ghostty: bool = False
    add_ghostty_include: bool = False


@dataclass
class Step:
    desc: str
    fn: Callable[[], Result]


def build_steps(ch: Choices, stamp: str) -> list[Step]:
    steps: list[Step] = []
    for cf in ch.replace:
        steps.append(Step(f"replace {cf.label} with a link; your old file is backed up first", lambda cf=cf: do_replace(cf, stamp)))
    if ch.bootstrap:
        steps.append(Step("add the init.zsh bootstrap line to ~/.zshrc (backup first)", lambda: do_bootstrap(stamp)))
    if ch.move_blocks:
        steps.append(Step(f"move {len(ch.move_blocks)} block(s) from ~/.zshrc into local.zsh (backups first, `zsh -n` checked)", lambda: do_migrate(ch.move_blocks, stamp)))
    if ch.make_local_zsh:
        steps.append(Step("create .config/zsh/local.zsh", lambda: do_make_local(LOCAL_ZSH, LOCAL_ZSH_TEMPLATE)))
    if ch.make_local_ghostty:
        steps.append(Step("create .config/ghostty/config.local", lambda: do_make_local(GHOSTTY_LOCAL, GHOSTTY_LOCAL_TEMPLATE)))
    if ch.add_ghostty_include:
        steps.append(Step("add `config-file = ?config.local` to the tracked ghostty config", do_ghostty_include))
    steps.append(Step("run `stow .` (skipped if conflicts remain)", do_stow))
    return steps


def run_steps(steps: list[Step], log: Callable[[str, str], None]) -> bool:
    for s in steps:
        try:
            level, msg = s.fn()
        except Exception as exc:  # stop at the first failure rather than leave a half-applied mix
            log("fail", f"{s.desc}: {exc}")
            return False
        log(level, msg)
    return True


# ----------------------------------------------------------------------------------------------------------------------
# UI


def cli_check() -> int:
    pre = stow_preflight()
    checks = run_checks(pre)
    sym = {"ok": "✔", "warn": "⚠", "fail": "✖", "info": "•"}
    print(machine_summary())
    for c in checks:
        print(f"{sym[c.status]} {c.title}" + (f"  ({c.detail})" if c.detail else ""))
    return 1 if any(c.status == "fail" for c in checks) else 0


def make_app():
    """Interactive Textual TUI for dotfiles setup. textual is imported here so `--check` needs nothing installed."""
    from rich.markup import escape
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Horizontal, Vertical, VerticalScroll
    from textual.css.query import NoMatches
    from textual.screen import ModalScreen
    from textual.widgets import Button, Footer, Header, RichLog, Select, SelectionList, Static, Switch
    from textual.widgets.selection_list import Selection

    ICON = {"ok": "[green]✔[/]", "warn": "[yellow]⚠[/]", "fail": "[red]✖[/]", "info": "[dim]•[/]"}

    class Confirm(ModalScreen[bool]):
        DEFAULT_CSS = """
        Confirm { align: center middle; }
        #box { width: 90%; max-width: 110; height: auto; max-height: 85%; padding: 1 2; border: thick $accent; background: $surface; }
        #plan { height: auto; max-height: 22; overflow-y: auto; margin-bottom: 1; }
        #confirm-row { height: 3; }
        #confirm-row Button { margin-right: 1; }
        """
        BINDINGS = [Binding("escape", "cancel", "Cancel")]

        def __init__(self, plan: list[str]) -> None:
            super().__init__()
            self.plan = plan

        def compose(self) -> ComposeResult:
            with Vertical(id="box"):
                yield Static("[b]Apply these changes?[/]  [dim]nothing is deleted; replaced files are backed up[/]")
                yield Static(escape("\n".join(f"• {p}" for p in self.plan)), id="plan")
                with Horizontal(id="confirm-row"):
                    yield Button("Apply", variant="primary", id="yes")
                    yield Button("Cancel", id="no")

        def on_button_pressed(self, event: Button.Pressed) -> None:
            self.dismiss(event.button.id == "yes")

        def action_cancel(self) -> None:
            self.dismiss(False)

    class SetupApp(App):
        TITLE = "Dotfiles setup"
        CSS = """
        Screen { layout: vertical; }
        #main { padding: 1 2; }
        .section-title { color: $accent; text-style: bold; margin-top: 1; }
        #checks, #conflicts, #zsh, #locals { height: auto; }
        .row { layout: horizontal; height: auto; min-height: 3; }
        .row-label { width: 44; padding: 1 1 0 0; text-style: bold; }
        .row-info { padding: 0 0 1 2; color: $text-muted; }
        .hint { color: $text-muted; padding: 0 0 1 0; }
        .toggle-row { layout: horizontal; height: auto; min-height: 3; }
        .toggle-label { width: 1fr; padding: 1 1 0 0; }
        Select { width: 1fr; }
        Switch { width: 12; }
        SelectionList { height: auto; max-height: 14; }
        RichLog { height: 12; border: round $surface; }
        #btn-row { height: 5; padding: 1 2; dock: bottom; background: $surface; }
        #btn-apply { margin-right: 1; }
        #btn-refresh { margin-right: 1; }
        """
        BINDINGS = [
            Binding("ctrl+q", "quit", "Quit"),
            Binding("q", "quit", "Quit", show=False),
            Binding("a", "apply", "Apply"),
            Binding("r", "refresh", "Refresh"),
        ]

        pre: Preflight
        segs: list[Seg] | None
        movable: list[Seg]

        def compose(self) -> ComposeResult:
            yield Header(show_clock=False)
            with VerticalScroll(id="main"):
                yield Static("Machine", classes="section-title")
                yield Static(id="machine")
                yield Static("Checks", classes="section-title")
                yield Vertical(id="checks")
                yield Static("Stow conflicts", classes="section-title")
                yield Vertical(id="conflicts")
                yield Static("zsh", classes="section-title")
                yield Vertical(id="zsh")
                yield Static("Local override files", classes="section-title")
                yield Vertical(id="locals")
                yield Static("Log", classes="section-title")
                yield RichLog(id="log", highlight=False, markup=True, wrap=True)
            with Horizontal(id="btn-row"):
                yield Button("Apply", variant="primary", id="btn-apply")
                yield Button("Refresh", variant="default", id="btn-refresh")
                yield Button("Quit", variant="default", id="btn-quit")
            yield Footer()

        async def on_mount(self) -> None:
            await self.reload()

        # ---- building the screen from the current state of the machine
        async def reload(self) -> None:
            self.pre = stow_preflight()
            self.segs = load_segs()
            self.query_one("#machine", Static).update(escape(machine_summary()))

            checks = self.query_one("#checks", Vertical)
            await checks.remove_children()
            await checks.mount(*[
                Static(f"{ICON[c.status]} {escape(c.title)}" + (f"  [dim]{escape(c.detail)}[/]" if c.detail else ""))
                for c in run_checks(self.pre)
            ])

            box = self.query_one("#conflicts", Vertical)
            await box.remove_children()
            widgets = []
            if not self.pre.conflicts:
                widgets.append(Static("[green]No conflicts.[/]"))
            else:
                widgets.append(Static("Files already in your home that `stow .` wants to turn into links:", classes="hint"))
            for i, cf in enumerate(self.pre.conflicts):
                opts = [("Replace with link (old file backed up)", "replace"), ("Leave as is", "skip")]
                sel = Select(opts, allow_blank=False, value="replace" if cf.kind == "identical" else "skip", id=f"cf-{i}", disabled=not cf.replaceable)
                widgets.append(Horizontal(Static(escape(cf.label), classes="row-label"), sel, classes="row"))
                info = cf.detail + (("\n" + cf.diff) if cf.diff else "")
                widgets.append(Static(escape(info), classes="row-info"))
            await box.mount(*widgets)

            zbox = self.query_one("#zsh", Vertical)
            await zbox.remove_children()
            zw = []
            if self.segs is None:
                zw.append(self._toggle("Create ~/.zshrc with the init.zsh bootstrap line", "sw-boot", True))
            elif not zsh_has_bootstrap():
                zw.append(self._toggle("Add the init.zsh bootstrap line to the top of ~/.zshrc", "sw-boot", True))
            else:
                zw.append(Static("[green]~/.zshrc already loads init.zsh.[/]"))
            self.movable = [s for s in (self.segs or []) if s.kind == "movable"]
            if self.movable:
                zw.append(Static("Tick blocks of ~/.zshrc to move into local.zsh (this machine only). Moved blocks run right after init.zsh, i.e. before the rest of ~/.zshrc.", classes="hint"))
                zw.append(SelectionList(*[Selection(self._preview(s), i, False) for i, s in enumerate(self.movable)], id="blocks"))
            kept = [s for s in (self.segs or []) if s.kind in ("managed", "secret")]
            if kept:
                names = [("secret, never moved into the repo dir" if s.kind == "secret" else "managed by an installer") for s in kept]
                zw.append(Static(f"[dim]Staying in ~/.zshrc: {len(kept)} block(s) ({', '.join(sorted(set(names)))}).[/]", classes="hint"))
            await zbox.mount(*zw)

            lbox = self.query_one("#locals", Vertical)
            await lbox.remove_children()
            lw = []
            if not LOCAL_ZSH.is_file():
                lw.append(self._toggle("Create .config/zsh/local.zsh (gitignored)", "sw-local-zsh", True))
            if GHOSTTY_CFG.is_file() and not GHOSTTY_LOCAL.is_file():
                lw.append(self._toggle("Create .config/ghostty/config.local (gitignored)", "sw-local-ghostty", True))
            if ghostty_state() == "missing":
                lw.append(self._toggle("Add `config-file = ?config.local` to the tracked ghostty config", "sw-ghostty-inc", True))
            if not lw:
                lw.append(Static("[green]All local override files exist.[/]"))
            await lbox.mount(*lw)

        @staticmethod
        def _toggle(label: str, wid: str, value: bool) -> Horizontal:
            return Horizontal(Static(escape(label), classes="toggle-label"), Switch(value=value, id=wid), classes="toggle-row")

        @staticmethod
        def _preview(seg: Seg) -> str:
            first = next((mask(ln) for ln in seg.lines if not ln.lstrip().startswith("#")), mask(seg.lines[0]))
            more = f"  (+{len(seg.lines) - 1} more line{'s' if len(seg.lines) > 2 else ''})" if len(seg.lines) > 1 else ""
            return escape(first.strip()[:78]) + more

        # ---- reading the choices back and applying them
        def _switch(self, wid: str) -> bool:
            try:
                return self.query_one(f"#{wid}", Switch).value
            except NoMatches:
                return False

        def collect(self) -> Choices:
            ch = Choices()
            for i, cf in enumerate(self.pre.conflicts):
                try:
                    if self.query_one(f"#cf-{i}", Select).value == "replace":
                        ch.replace.append(cf)
                except NoMatches:
                    pass
            ch.bootstrap = self._switch("sw-boot")
            try:
                ch.move_blocks = [self.movable[i].text for i in self.query_one("#blocks", SelectionList).selected]
            except NoMatches:
                pass
            ch.make_local_zsh = self._switch("sw-local-zsh")
            ch.make_local_ghostty = self._switch("sw-local-ghostty")
            ch.add_ghostty_include = self._switch("sw-ghostty-inc")
            return ch

        def action_apply(self) -> None:
            steps = build_steps(self.collect(), datetime.now().strftime("%Y%m%d-%H%M%S"))

            def after(confirmed: bool | None) -> None:
                if not confirmed:
                    self.notify("Nothing changed")
                    return
                log = self.query_one("#log", RichLog)

                def write(level: str, msg: str) -> None:
                    log.write(f"{ICON.get(level, ICON['info'])} {escape(msg)}")

                ok = run_steps(steps, write)
                self.notify("Done" if ok else "Stopped on an error, see the log", severity="information" if ok else "error")
                self.call_later(self.reload)

            self.push_screen(Confirm([s.desc for s in steps]), after)

        async def action_refresh(self) -> None:
            await self.reload()

        def on_button_pressed(self, event: Button.Pressed) -> None:
            if event.button.id == "btn-quit":
                self.exit()
            elif event.button.id == "btn-refresh":
                self.run_worker(self.reload())
            elif event.button.id == "btn-apply":
                self.action_apply()

    return SetupApp()


def main() -> int:
    ap = argparse.ArgumentParser(description="Set up these dotfiles on this machine.")
    ap.add_argument("--check", action="store_true", help="print the checks and exit 1 if something blocks `stow .` (no UI)")
    args = ap.parse_args()
    if args.check:
        return cli_check()
    make_app().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())

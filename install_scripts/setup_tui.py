#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["textual>=0.80"]
# ///
"""Get this machine's dotfiles working: ``./start.sh``

No options. It looks at the machine, lists what it will do, and does it when you press Apply:
  - files already in your home that block ``stow .`` are moved to ~/.dotfiles-backup/<timestamp>/ and replaced by links
  - ~/.zshrc gets the line that loads ~/.config/zsh/init.zsh, if it is missing
  - ``stow .`` runs
Nothing is ever deleted. ``./start.sh --check`` prints the same status without a UI (stdlib only) and exits 1 if
something blocks.

Per-machine settings never go into tracked files: ~/.config/zsh/local.zsh (zsh) and ~/.config/ghostty/config.local
(ghostty) are gitignored and picked up automatically.
"""

from __future__ import annotations

import argparse
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
HOME_R = HOME.resolve()  # stow reports resolved paths (macOS: /tmp is really /private/tmp), so compare both
ZSHRC = HOME / ".zshrc"
BACKUP_ROOT = HOME / ".dotfiles-backup"

BOOTSTRAP_LINE = 'source "${HOME}/.config/zsh/init.zsh"'
BOOT_RE = re.compile(r"config/zsh/init\.zsh")
CONFLICT_PATTERNS = [
    re.compile(r"cannot stow (?P<src>\S+) over existing target (?P<tgt>\S+) since"),
    re.compile(r"cannot stow non-directory (?P<src>\S+) over existing directory target (?P<tgt>\S+)"),
    re.compile(r"existing target is not owned by stow: (?P<tgt>\S+)"),
    re.compile(r"existing target is neither a link nor a directory: (?P<tgt>\S+)"),
    re.compile(r"existing target is stowed to a different package: (?P<tgt>\S+)"),
]


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
    if not shutil.which("stow"):
        return Preflight(error="stow is not installed (brew install stow / apt install stow)")
    rc, out = sh(["stow", "-n", "-v", "."], cwd=REPO)
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
    if pre.error:
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

    dirty = git_dirty_tracked()
    if dirty:
        shown = ", ".join(dirty[:5]) + (f" (+{len(dirty) - 5} more)" if len(dirty) > 5 else "")
        out.append(Check("warn", f"{len(dirty)} tracked file(s) modified locally", shown, quiet=True))
    if platform.system() != "Darwin" and ((REPO / "Library").exists() or (REPO / ".hammerspoon").exists()):
        out.append(Check("info", "Library/ and .hammerspoon/ are macOS-only", "stow still links them here; harmless", quiet=True))
    return out


def machine_summary() -> str:
    _rc, branch = sh(["git", "-C", str(REPO), "rev-parse", "--abbrev-ref", "HEAD"])
    return f"{platform.system()} {platform.machine()} · {socket.gethostname()} · {stow_version()} · git {branch.strip() or '?'}\nrepo {REPO}  ->  links into {TARGET}"


# ----------------------------------------------------------------------------------------------------------------------
# what Apply does. Each action returns (level, message) or raises; none of them deletes anything.


Result = tuple[str, str]


def do_replace(cf: Conflict, stamp: str) -> Result:
    assert cf.target is not None
    if not cf.target.exists() and not cf.target.is_symlink():
        return "ok", f"{cf.label}: already gone"
    if cf.target.is_symlink() or cf.target.is_dir() or not cf.target.is_file():
        raise RuntimeError(f"{cf.label}: not a plain file, resolve by hand")
    dest = backup_dest(cf.target, stamp)
    shutil.move(str(cf.target), str(dest))
    return "ok", f"{cf.label}: old copy moved to {dest}"


def do_bootstrap(stamp: str) -> Result:
    if not ZSHRC.exists():
        ZSHRC.write_text(BOOTSTRAP_LINE + "\n")
        return "ok", "created ~/.zshrc with the init.zsh line"
    old = ZSHRC.read_text()
    if BOOT_RE.search(old):
        return "ok", "~/.zshrc already loads init.zsh"
    new = BOOTSTRAP_LINE + "\n\n" + old
    ok, err = zsh_syntax_ok(new)
    if not ok:
        raise RuntimeError(f"refusing to write ~/.zshrc, syntax check failed: {err}")
    shutil.copy2(ZSHRC, backup_dest(ZSHRC, stamp))
    ZSHRC.write_text(new)
    return "ok", f"added the init.zsh line to the top of ~/.zshrc (old copy in {BACKUP_ROOT / stamp})"


def do_stow() -> Result:
    pre = stow_preflight()
    if pre.error:
        return "warn", pre.error
    if pre.conflicts:
        return "warn", f"not linked yet: {len(pre.conflicts)} file{'s' if len(pre.conflicts) != 1 else ''} still in the way"
    rc, out = sh(["stow", "-v", "."], cwd=REPO)
    if rc != 0:
        raise RuntimeError(out.strip()[-400:])
    n = sum(1 for ln in out.splitlines() if ln.startswith("LINK:"))
    return "ok", f"linked {n} item{'s' if n != 1 else ''}" if n else "nothing new to link"


@dataclass
class Step:
    desc: str
    fn: Callable[[str], Result]  # takes the backup timestamp


@dataclass
class Plan:
    steps: list[Step] = field(default_factory=list)
    blockers: list[str] = field(default_factory=list)  # things only the user can fix


def make_plan(pre: Preflight) -> Plan:
    plan = Plan()
    if pre.error:
        plan.blockers.append(pre.error)
    for cf in pre.conflicts:
        if cf.kind in ("identical", "differs"):
            extra = "" if cf.kind == "identical" else " (differs from the repo copy)"
            plan.steps.append(Step(f"replace {cf.label} with a link{extra}", lambda stamp, cf=cf: do_replace(cf, stamp)))
        else:
            plan.blockers.append(f"{cf.label} {cf.detail}")
    if not zsh_has_bootstrap():
        plan.steps.append(Step("make ~/.zshrc load the shared zsh config", do_bootstrap))
    if not pre.error and (plan.steps or pre.links):
        suffix = " (skipped while the above still blocks it)" if plan.blockers else ""
        plan.steps.append(Step("link everything with stow" + suffix, lambda stamp: do_stow()))
    return plan


def run_steps(steps: list[Step], log: Callable[[str, str], None]) -> bool:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    for s in steps:
        try:
            level, msg = s.fn(stamp)
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
    plan = make_plan(pre)
    sym = {"ok": "✔", "warn": "⚠", "fail": "✖", "info": "•"}
    print(machine_summary())
    for c in checks:
        print(f"{sym[c.status]} {c.title}" + (f"  ({c.detail})" if c.detail else ""))
    if plan.steps or plan.blockers:
        print("Apply would:")
        for s in plan.steps:
            print(f"  - {s.desc}")
        for b in plan.blockers:
            print(f"  ! needs you: {b}")
    return 1 if any(c.status == "fail" for c in checks) else 0


def make_app():
    """One-screen Textual UI. textual is imported here so `--check` needs nothing installed."""
    from rich.markup import escape
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Horizontal, Vertical, VerticalScroll
    from textual.widgets import Button, Footer, Header, Static

    ICON = {"ok": "[green]✔[/]", "warn": "[yellow]⚠[/]", "fail": "[red]✖[/]", "info": "[dim]•[/]"}
    NOTE = "[dim]Replaced files are moved to ~/.dotfiles-backup/<time>/, never deleted.[/]"

    class SetupApp(App):
        TITLE = "Dotfiles setup"
        CSS = """
        Screen { layout: vertical; }
        #main { padding: 1 2; align-horizontal: center; }
        #body { width: 100%; max-width: 92; height: auto; }
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
                    yield Static(id="checks", classes="panel")
                    yield Static(id="plan", classes="panel")
                    yield Static(id="result", classes="panel")
                    with Horizontal(id="btn-row"):
                        yield Button("Apply", variant="primary", id="btn-apply")
                        yield Button("Quit", variant="default", id="btn-quit")
            yield Footer()

        def on_mount(self) -> None:
            os_name = {"Darwin": "macOS"}.get(platform.system(), platform.system())
            self.sub_title = f"{os_name} · {socket.gethostname()}"
            self.query_one("#checks").border_title = "Status"
            self.query_one("#plan").border_title = "Apply will"
            self.query_one("#result").border_title = "Result"
            self.query_one("#result").display = False
            self.reload()

        def reload(self) -> None:
            pre = stow_preflight()
            self.plan = make_plan(pre)
            rows = [c for c in run_checks(pre) if not c.quiet]
            self.query_one("#checks", Static).update("\n".join(
                f"{ICON[c.status]}  {escape(c.title)}" + (f"  [dim]{escape(c.detail)}[/]" if c.detail else "") for c in rows
            ))

            lines = [f"[dim]{i}[/]  {escape(s.desc)}" for i, s in enumerate(self.plan.steps, 1)]
            lines += [f"[red]✖[/]  [b]needs you:[/] {escape(b)}" for b in self.plan.blockers]
            if self.plan.blockers:
                lines += ["", "[dim]Move those away yourself, then press r to re-check.[/]"]
            if self.plan.steps:
                lines += ["" if not self.plan.blockers else "", NOTE]
            plan_box = self.query_one("#plan", Static)
            plan_box.update("\n".join(lines))
            plan_box.display = bool(lines)

            n = len(self.plan.steps)
            if self.plan.blockers:
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
            ok = run_steps(self.plan.steps, lambda level, msg: results.append(f"{ICON.get(level, ICON['info'])}  {escape(msg)}"))
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
    ap = argparse.ArgumentParser(description="Get this machine's dotfiles working.")
    ap.add_argument("--check", action="store_true", help="print the status and exit 1 if something blocks `stow .` (no UI)")
    args = ap.parse_args()
    if args.check:
        return cli_check()
    make_app().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())

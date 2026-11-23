# Dotfiles

Works on macOS and Linux. Nothing tracked in here gets edited per machine: OS differences are detected in code, and
per-machine settings live in gitignored local files.

## Every machine

    git pull && stow .

## First time on a machine, or when `stow .` complains

    ./start.sh            # TUI: resolves stow conflicts, ~/.zshrc bootstrap, local override files
    ./start.sh --check    # the same checks without a UI (stdlib only); exits 1 if something blocks stow

Needs `stow`. The TUI runs through `uv` in a throwaway environment, so nothing is installed into system Python.
It never deletes anything: a file it replaces is moved to `~/.dotfiles-backup/<timestamp>/`, and every change is
listed and confirmed before it happens.

## Per-machine settings (never tracked)

| What | Where |
| --- | --- |
| zsh (prompt name, ssh hooks, machine paths) | `~/.config/zsh/local.zsh`, sourced last by `init.zsh` |
| ghostty | `~/.config/ghostty/config.local`, pulled in by `config-file = ?config.local` in the tracked config |
| blocks that installers append (conda, gcloud, ...) and anything secret | `~/.zshrc` (untracked) |

Secrets stay in `~/.zshrc`, outside the repo directory; the setup tool never moves them.

## OS-specific parts

* `install_scripts/{mac,linux,cloud_vm}_install_required.sh` install each platform's dependencies.
* zsh and tmux pick fzf, syntax highlighting and the clipboard tool by OS at shell start.
* yazi: `y` yanks, and on macOS also puts the file on the system clipboard (the `clippy` plugin is a no-op elsewhere).
* `Library/` and `.hammerspoon/` are macOS-only; stow links them on Linux too, which is harmless.

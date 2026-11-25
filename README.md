# Dotfiles

Works on macOS and Linux. OS differences are detected in code where possible, and per-machine settings live in
gitignored local files instead of edits to tracked ones. Known gap: the ghostty config needs ghostty 1.2+ for
`cmd+r=prompt_surface_title` (an older ghostty just reports that one line as invalid).

## Every machine

    git pull && stow .

If a pull removed or renamed files, run `stow -R .` once to clear their old links.

## First time on a machine, or when `stow .` complains

    ./start.sh            # one screen: shows what it will do, press Apply (Enter)
    ./start.sh --check    # the same status without a UI (stdlib only); exits 1 if something blocks stow

No options. Apply moves files that block `stow .` to `~/.dotfiles-backup/<timestamp>/` and links the repo's copies,
adds the line that loads `~/.config/zsh/init.zsh` to `~/.zshrc` if it is missing, and runs `stow .`. Nothing is
deleted. Anything it can't safely fix (a symlink or directory in the way) is listed as "needs you".

Needs `stow`. The TUI runs through `uv` in a throwaway environment, so nothing is installed into system Python.

## Per-machine settings (never tracked)

| What | Where |
| --- | --- |
| zsh (prompt name, ssh hooks, machine paths) | `~/.config/zsh/local.zsh`, sourced last by `init.zsh` |
| ghostty | `~/.config/ghostty/config.local`, pulled in by `config-file = ?config.local` in the tracked config |
| blocks that installers append (conda, gcloud, ...) and anything secret | `~/.zshrc` (untracked) |

Keep secrets in `~/.zshrc` (untracked) or the keychain, never in this repo.

## OS-specific parts

* `install_scripts/{mac,linux,cloud_vm}_install_required.sh` install each platform's dependencies.
* zsh and tmux pick fzf, syntax highlighting and the clipboard tool by OS at shell start.
* yazi: `y` yanks, and on macOS also puts the file on the system clipboard (the `clippy` plugin is a no-op elsewhere).
* `Library/` and `.hammerspoon/` are macOS-only; stow links them on Linux too, which is harmless.

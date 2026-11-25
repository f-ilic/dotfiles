# Dotfiles

Works on macOS and Linux (Ubuntu/Debian). OS differences are detected in code where possible, and per-machine
settings live in gitignored local files instead of edits to tracked ones. Known gap: the ghostty config needs
ghostty 1.2+ for `cmd+r=prompt_surface_title` (an older ghostty just reports that one line as invalid).

## Every machine

    git pull && stow .

If a pull removed or renamed files, run `stow -R .` once to clear their old links.

## New machine, or when `stow .` complains

    ./start.sh            # one screen: what is installed, what Apply will do; press Apply (Enter)
    ./start.sh --check    # the same status without a UI; exits 1 if something needed is missing or blocked
    ./start.sh --plain    # the same flow as plain text with a y/N question

No options. The screen lists what the configs need, marks what is missing, and Apply:

1. installs the missing tools: Homebrew on macOS; apt, snap and release downloads on Ubuntu/Debian. Installers run in
   your terminal, so `sudo` can ask for a password and you see the output.
2. makes `~/.zshrc` load `~/.config/zsh/init.zsh` (creating it from the repo's template if there is none)
3. replaces files in your home that are byte-identical to the repo copy with links, then runs `stow .`

A file that differs from the repo copy is never replaced: it is listed as "needs you", and linking waits until you have
compared it (`diff`) and deleted the one you don't want. Nothing is backed up or moved around.

Desktop apps (ghostty, the font, Hammerspoon and so on) are only installed on a Mac or a Linux box with a desktop; a
headless VM is detected and skipped. The list of tools lives in one table at the top of `install_scripts/setup_tui.py`.
Needs `stow` (installed by the screen itself on a bare machine, via `./start.sh --plain`). The screen runs through `uv`
in a throwaway environment, so nothing is installed into system Python.

## Per-machine settings (never tracked)

| What | Where |
| --- | --- |
| zsh (prompt name, ssh hooks, machine paths) | `~/.config/zsh/local.zsh`, sourced last by `init.zsh` |
| ghostty | `~/.config/ghostty/config.local`, pulled in by `config-file = ?config.local` in the tracked config |
| blocks that installers append (conda, gcloud, ...) and anything secret | `~/.zshrc` (untracked) |

Keep secrets in `~/.zshrc` (untracked) or the keychain, never in this repo.

## OS-specific parts

* zsh and tmux pick fzf, syntax highlighting and the clipboard tool by OS at shell start. Ubuntu's apt fzf is older than
  the config would like, so Alt-T falls back to a plain picker (no `--style`, no preview) there.
* `init.zsh` falls back to `TERM=xterm-256color` when the terminal's terminfo is missing (ghostty over SSH).
* yazi: `y` yanks, and on macOS also puts the file on the system clipboard (the `clippy` plugin is a no-op elsewhere).
* `Library/` and `.hammerspoon/` are macOS-only; stow links them on Linux too, which is harmless.

## Keyboard remap

The same nav layer exists on both systems: hold the layer key and `ijkl` are arrows, `u`/`o` line start/end, `n`/`m`
page up/down, `h` backspace, `;` delete, space enter, `q` escape (Alt plus those on macOS via
`.hammerspoon/Spoons/KeyRemap`, Caps Lock on Linux via kmonad). Hammerspoon has a second, modal variant,
`KeyRemapTogglable`, which `init.lua` can load instead.

On a Linux desktop `./start.sh` installs the kmonad binary. Then, once per machine:

    kmonad/install.sh            # a service for each configured keyboard that is plugged in here
    kmonad/install.sh --list     # which configs match a connected keyboard
    kmonad/install.sh --remove

Each `kmonad/config/*.kbd` names its keyboard in a `;; device:` header (a glob, so a serial number doesn't tie it to
one unit). The script checks every config with `kmonad --dry-run` before it changes anything, then runs them all through
one `kmonad@.service`. Re-run it after editing a config.

## bin/

| Tool | What it does |
| --- | --- |
| `collage` | Grid or stack of images, GIFs and videos into one GIF, video or image. Run it bare for a small TUI. |
| `create-tmux-session NAME` | Create a tmux session with a ready layout (main, files, monitor and git windows), or attach if it exists. |
| `preview FILE` | Full-screen preview: images through chafa, anything else through rich and less. yazi binds it to a key. |
| `tunnel` | Persistent SSH port forwards per host (`start`, `stop`, `status`, `edit`, `logs`), configured in `~/.tunnel.conf`. |

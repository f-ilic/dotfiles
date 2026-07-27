#!/usr/bin/env bash
#
# cloud_vm_install_required.sh
# ---------------------------------------------------------------------------
# Dependency installer for HEADLESS cloud VMs — Ubuntu/Debian boxes you only
# ever SSH into (GCP, AWS, etc.). NOT for a machine with a display.
#
# How it differs from linux_install_required.sh (desktop):
#   • No ghostty, no kmonad, no fonts — useless without a GUI.
#   • Never aborts the whole run because one optional install failed
#     (the desktop script's `set -e` bailed on the ghostty snap and skipped
#      the .zshrc setup, which is why TERM=xterm-ghostty stayed broken).
#   • Fixes the TERM=xterm-ghostty-over-SSH problem up front.
#   • Actually runs `stow` so ~/.config/zsh/init.zsh gets linked.
#   • Uses `sudo chsh` — cloud accounts have no Unix password, so plain
#     chsh fails with "PAM: Authentication failure".
#   • Generates the en_US.UTF-8 locale that exports.zsh expects.
#
# Run it:   bash ~/dotfiles/install_scripts/cloud_vm_install_required.sh
# ---------------------------------------------------------------------------

set -uo pipefail   # deliberately NOT -e: one failed extra must not kill setup

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\n\033[1;34m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }
try()  { "$@" || warn "step failed (continuing): $*"; }

log "☁️  Headless VM setup — SSH-only box, skipping all GUI packages"

# ---------------------------------------------------------------------------
# 1) apt update — if THIS fails it's almost always missing internet egress,
#    which we can't (and shouldn't) work around from here. Fail loudly.
# ---------------------------------------------------------------------------
log "🔄 Updating apt package lists..."
if ! sudo apt-get update -y; then
    warn "apt update failed — this VM likely has no internet egress."
    warn "Sort out egress (Cloud NAT / an internal mirror / proxy) and re-run."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) Locale — exports.zsh sets LC_ALL=en_US.UTF-8; generate it or every
#    command spews 'setlocale: LC_ALL: cannot change locale' warnings.
# ---------------------------------------------------------------------------
log "🌐 Ensuring en_US.UTF-8 locale..."
try sudo apt-get install -y locales
try sudo locale-gen en_US.UTF-8
try sudo update-locale LANG=en_US.UTF-8

# ---------------------------------------------------------------------------
# 3) Core CLI tools the .zshrc / init.zsh modules actually reference
# ---------------------------------------------------------------------------
log "📦 Installing core CLI tools..."
sudo apt-get install -y \
    zsh stow git curl wget build-essential \
    fzf micro tree \
    zsh-syntax-highlighting git-delta chafa \
  || warn "one or more core apt packages failed (see output above)"

# ---------------------------------------------------------------------------
# 4) lazygit — not in apt, grab the release binary (arch-aware, non-fatal)
# ---------------------------------------------------------------------------
if ! command -v lazygit &>/dev/null; then
    log "🐊 Installing lazygit..."
    case "$(uname -m)" in
        x86_64)          LG_ARCH="Linux_x86_64" ;;
        aarch64|arm64)   LG_ARCH="Linux_arm64"  ;;
        *)               LG_ARCH="Linux_x86_64" ;;
    esac
    LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
                | grep -Po '"tag_name": *"v\K[^"]*' || true)"
    if [[ -n "${LG_VER:-}" ]] \
        && curl -fsSL -o /tmp/lazygit.tar.gz \
             "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_${LG_ARCH}.tar.gz" \
        && tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit; then
        sudo install /tmp/lazygit /usr/local/bin/lazygit && ok "lazygit ${LG_VER} installed"
    else
        warn "lazygit download failed (GitHub egress?) — skipping, not fatal"
    fi
else
    ok "lazygit already installed"
fi

# ---------------------------------------------------------------------------
# 5) yazi — TUI file manager used by the `y`/Ctrl-o widget. Optional; snap
#    can be slow on VMs, so it's non-fatal and skipped if snap is absent.
# ---------------------------------------------------------------------------
if command -v snap &>/dev/null; then
    if snap list yazi &>/dev/null; then
        ok "yazi already installed"
    else
        log "🗂  Installing yazi via snap (optional)..."
        try sudo snap install yazi --classic
    fi
else
    warn "snap not available — skipping yazi (optional TUI file manager)"
fi

# ---------------------------------------------------------------------------
# 6) rich-cli — nice-to-have, via pipx. Fully optional.
# ---------------------------------------------------------------------------
log "👌 Installing nice-to-haves (rich-cli)..."
try sudo apt-get install -y pipx
if command -v pipx &>/dev/null; then
    try pipx install rich-cli
fi

# ---------------------------------------------------------------------------
# 7) Link the dotfiles with stow (this is what the desktop script forgot).
#    init.zsh + module files + bin/ + .tmux.conf get symlinked into $HOME.
#    .zshrc, install_scripts, kmonad, vscode, README are excluded by
#    .stow-local-ignore. Conflicts are reported, never force-overwritten.
# ---------------------------------------------------------------------------
log "🔗 Linking dotfiles into \$HOME with stow..."
if command -v stow &>/dev/null; then
    if (cd "$DOTFILES_DIR" && stow --restow --target="$HOME" . 2>/tmp/stow.err); then
        ok "dotfiles linked"
    else
        warn "stow hit conflicts — nothing was overwritten. Details:"
        sed 's/^/      /' /tmp/stow.err >&2 2>/dev/null || true
        warn "resolve those paths, then: cd ~/dotfiles && stow --restow --target=\$HOME ."
    fi
    [[ -r "$HOME/.config/zsh/init.zsh" ]] \
        && ok "verified ~/.config/zsh/init.zsh is present" \
        || warn "~/.config/zsh/init.zsh not linked — zsh config won't fully load"
else
    warn "stow missing — cannot link dotfiles"
fi

# ---------------------------------------------------------------------------
# 8) ~/.zshrc — it's stow-ignored, so set it up here.
#    Preserve any existing file (e.g. conda's appended init) and just make
#    sure the two required lines are present: the TERM fallback and the
#    init.zsh source.
# ---------------------------------------------------------------------------
log "📄 Setting up ~/.zshrc..."
TEMPLATE="$DOTFILES_DIR/.zshrc"
TARGET="$HOME/.zshrc"
if [[ ! -f "$TARGET" ]]; then
    cp "$TEMPLATE" "$TARGET" && ok "created ~/.zshrc from dotfiles template"
else
    if ! grep -q 'config/zsh/init.zsh' "$TARGET"; then
        printf '\nsource "${HOME}/.config/zsh/init.zsh"\n' >> "$TARGET"
        ok "added init.zsh source to existing ~/.zshrc"
    fi
    if ! grep -q 'infocmp "\$TERM"' "$TARGET"; then
        { printf '# Fall back if TERM (e.g. xterm-ghostty over SSH) has no terminfo here\nif ! infocmp "$TERM" &>/dev/null; then\n  export TERM=xterm-256color\nfi\n\n'; cat "$TARGET"; } \
            > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
        ok "prepended TERM fallback to ~/.zshrc"
    fi
    ok "~/.zshrc already present, left your customizations intact"
fi

# ---------------------------------------------------------------------------
# 9) Default shell -> zsh, via sudo (cloud accounts have no password).
# ---------------------------------------------------------------------------
log "🐚 Setting zsh as the default shell..."
ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
    ok "default shell already zsh"
elif sudo chsh -s "$ZSH_BIN" "$USER"; then
    ok "default shell set to $ZSH_BIN (takes effect on next login)"
else
    warn "couldn't set default shell. If this VM uses GCP OS Login, /etc/passwd"
    warn "changes don't stick — set the shell in your Google profile instead."
    warn "Otherwise run manually: sudo chsh -s $ZSH_BIN $USER"
fi

# ---------------------------------------------------------------------------
log "✅ Done."
cat <<'EOF'

Next steps:
  1. Reconnect over SSH (or run: exec zsh) to pick up the new shell.
  2. The TERM=xterm-ghostty error is handled by the fallback in ~/.zshrc.

Intentionally NOT installed (headless VM): ghostty, kmonad, fonts-firacode.
EOF

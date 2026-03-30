#!/bin/bash

# Linux (Ubuntu/Debian) Installation Script for .zshrc Dependencies
# This script installs all required programs for the .zshrc dotfile to work correctly

set -e  # Exit on any error

echo "🚀 Starting Linux dependency installation for .zshrc dotfile..."

# Update package lists
echo "🔄 Updating package lists..."
sudo apt update

# Install core dependencies
echo "📝 Installing core dependencies..."
sudo apt install -y zsh fzf micro curl wget git build-essential zsh-syntax-highlighting fonts-firacode chafa

# Install lazygit (not in apt repos)
echo "📝 Installing lazygit..."
if ! command -v lazygit &> /dev/null; then
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo mv /tmp/lazygit /usr/local/bin/lazygit
fi

# Install rich-cli via pipx
echo "👌 Installing Nice-To-Have's"
sudo apt install -y pipx
pipx install rich-cli

# Install snap packages
echo "🛠️ Installing additional tools..."
sudo snap install yazi --classic
sudo snap install ghostty --classic

# Install kmonad
echo "⌨️ Installing kmonad..."
if ! command -v kmonad &> /dev/null; then
    wget -O /tmp/kmonad https://github.com/kmonad/kmonad/releases/latest/download/kmonad
    sudo mv /tmp/kmonad /usr/local/bin/kmonad
    sudo chmod +x /usr/local/bin/kmonad
fi

# Make zsh the default shell if it isn't already
if [[ "$SHELL" != "$(which zsh)" ]]; then
    echo "🐚 Setting zsh as default shell..."
    sudo chsh -s $(which zsh) $(whoami)
    echo "⚠️  Please restart your computer for the change to take effect"
fi

# Create ~/bin directory if it doesn't exist
if [[ ! -d "$HOME/bin" ]]; then
    echo "📁 Creating ~/bin directory..."
    mkdir -p "$HOME/bin"
fi

# Setup ~/.zshrc
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZSHRC_TEMPLATE="$DOTFILES_DIR/.zshrc"

if [[ ! -f "$HOME/.zshrc" ]]; then
    echo "📄 Creating ~/.zshrc from dotfiles template..."
    cp "$ZSHRC_TEMPLATE" "$HOME/.zshrc"
else
    echo "📄 ~/.zshrc already exists, checking for required lines..."
    PREPEND=""
    if ! grep -q 'infocmp "\$TERM"' "$HOME/.zshrc"; then
        PREPEND='# Fall back to xterm-256color if the current TERM has no terminfo entry (e.g. xterm-ghostty over SSH)\nif ! infocmp "$TERM" &>/dev/null; then\n    export TERM=xterm-256color\nfi\n\n'"$PREPEND"
    fi
    if ! grep -q 'source.*config/zsh/init.zsh' "$HOME/.zshrc"; then
        PREPEND="${PREPEND}"'source "${HOME}/.config/zsh/init.zsh"\n\n'
    fi
    if [[ -n "$PREPEND" ]]; then
        echo "  → Prepending missing lines to ~/.zshrc"
        printf "$PREPEND" | cat - "$HOME/.zshrc" > /tmp/.zshrc_tmp && mv /tmp/.zshrc_tmp "$HOME/.zshrc"
    else
        echo "  → ~/.zshrc already has required lines, skipping"
    fi
fi

echo "✅ Installation complete!"
echo ""
echo "📋 Installed packages:"
echo "  - zsh (Z shell)"
echo "  - fzf (fuzzy finder)"
echo "  - yazi (file manager)"
echo "  - micro (text editor)"
echo "  - zsh-syntax-highlighting"
echo "  - Fira Code font"
echo "  - ghostty (terminal)"
echo "  - kmonad (keyboard remapper)"
echo ""
echo "🔄 Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Your .zshrc dotfile should now work correctly!"
echo ""
echo "💡 Notes:"
echo "  - Make sure to link/copy your dotfiles to the correct locations"
echo "  - Ghostty and Yazi were installed via snap"

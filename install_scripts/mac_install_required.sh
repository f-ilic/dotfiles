#!/bin/bash

# macOS Installation Script for .zshrc Dependencies
# This script installs all required programs for the .zshrc dotfile to work correctly

set -e  # Exit on any error

echo "🚀 [macOS] Starting installation of .zshrc dotfile requirements and customizations"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for the current session
    if [[ $(uname -m) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew is already installed"
fi

# Update Homebrew
echo "🔄 Updating Homebrew..."
brew update

# Install essential tools needed for .zshrc
echo "📝 Installing core dependencies..."

# Essential for .zshrc functionality
brew install fzf
brew install yazi
brew install micro
brew install zsh-syntax-highlighting
brew install lazygit
brew install chafa

echo "🛠️ Installing additional tools..."
brew install --cask ghostty
brew install --cask hammerspoon
brew install --cask rectangle
brew install --cask alt-tab

# Install fonts
echo "🔤 Installing Fira Code font..."
brew install --cask font-fira-code

# Install nice-to-have's
echo "👌 Installing Nice-To-Have's"
brew install tldr
brew install neilberkman/clippy/clippy
brew install rich-cli

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
echo "🔄 Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Link all the dotfiles or run: source ~/.zshrc"

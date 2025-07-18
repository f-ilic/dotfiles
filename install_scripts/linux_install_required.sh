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
sudo apt install -y zsh fzf micro curl wget git build-essential zsh-syntax-highlighting fonts-firacode

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
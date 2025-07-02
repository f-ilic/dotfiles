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

echo "🛠️ Installing additional tools..."
brew install --cask ghostty
brew install --cask hammerspoon
brew install --cask rectangle
brew install --cask alt-tab

# Install Fira Code font
echo "🔤 Installing Fira Code font..."
brew install --cask font-fira-code

# Create ~/bin directory if it doesn't exist
if [[ ! -d "$HOME/bin" ]]; then
    echo "📁 Creating ~/bin directory..."
    mkdir -p "$HOME/bin"
fi


echo "✅ Installation complete!"
echo ""
echo "📋 Installed packages:"
echo "  - fzf (fuzzy finder)"
echo "  - yazi (file manager)"
echo "  - micro (text editor)"
echo "  - zsh-syntax-highlighting"
echo "  - lazygit (git text interface)"
echo "  - ghostty (terminal)"
echo "  - hammerspoon (automation)"
echo "  - rectangle (window manager)"
echo "  - alt-tab (app switcher)"
echo "  - Fira Code font"
echo ""
echo "🔄 Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Your .zshrc dotfile should now work correctly!"
echo ""
echo "💡 Note: Make sure to link/copy your dotfiles to the correct locations."

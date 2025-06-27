#!/bin/bash

# macOS Installation Script for .zshrc Dependencies
# This script installs all required programs for the .zshrc dotfile to work correctly

set -e  # Exit on any error

echo "🚀 Starting macOS dependency installation for .zshrc dotfile..."

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

echo "🛠️ Installing additional tools..."
brew install --cask ghostty
brew install --cask hammerspoon

# Install Fira Code font
echo "🔤 Installing Fira Code font..."
brew install --cask font-fira-code

# Setup fzf key bindings and fuzzy completion
echo "🔧 Setting up fzf integration..."
$(brew --prefix)/opt/fzf/install --key-bindings --completion --no-update-rc

# Make zsh the default shell if it isn't already
if [[ "$SHELL" != "$(which zsh)" ]]; then
    echo "🐚 Setting zsh as default shell..."
    sudo chsh -s $(which zsh) $(whoami)
    echo "⚠️  Please restart your terminal for the shell change to take effect"
fi

# Create ~/bin directory if it doesn't exist (referenced in .zshrc PATH)
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
echo "  - ghostty (terminal)"
echo "  - hammerspoon (automation)"
echo "  - Fira Code font"
echo ""
echo "🔄 Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Your .zshrc dotfile should now work correctly!"
echo ""
echo "💡 Note: Make sure to link/copy your dotfiles to the correct locations."

#!/bin/bash

# Linux (Ubuntu/Debian) Installation Script for .zshrc Dependencies
# This script installs all required programs for the .zshrc dotfile to work correctly

set -e  # Exit on any error

echo "🚀 Starting Linux dependency installation for .zshrc dotfile..."

# Update package lists
echo "🔄 Updating package lists..."
sudo apt update

# Install essential tools needed for .zshrc
echo "📝 Installing core dependencies from apt..."

# Essential for .zshrc functionality
sudo apt install -y zsh
sudo apt install -y fzf
sudo apt install -y micro

# Install build essentials and dependencies for additional tools
sudo apt install -y curl wget git build-essential

# Install zsh-syntax-highlighting
echo "📦 Installing zsh-syntax-highlighting..."
sudo apt install -y zsh-syntax-highlighting

# Install yazi (file manager) - needs to be installed via cargo or downloaded
echo "📁 Installing yazi file manager..."
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust and Cargo for yazi..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Install yazi via cargo
cargo install --locked yazi-fm yazi-cli

# Install Fira Code font
echo "🔤 Installing Fira Code font..."
sudo apt install -y fonts-firacode

# Install ghostty using the Ubuntu installation script
echo "🖥️ Installing Ghostty terminal..."
if ! command -v ghostty &> /dev/null; then
    echo "Installing Ghostty using official Ubuntu installer..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
else
    echo "✅ Ghostty is already installed"
fi

# Setup fzf key bindings and fuzzy completion
echo "🔧 Setting up fzf integration..."
if [[ -f "/usr/share/doc/fzf/examples/key-bindings.zsh" ]]; then
    # Ubuntu/Debian fzf location
    echo "FZF key bindings will be sourced from system location"
else
    # Alternative: install fzf from git if system version doesn't have key bindings
    if [[ ! -d "$HOME/.fzf" ]]; then
        echo "Installing fzf from git for full functionality..."
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --key-bindings --completion --no-update-rc
    fi
fi

# Make zsh the default shell if it isn't already
if [[ "$SHELL" != "$(which zsh)" ]]; then
    echo "🐚 Setting zsh as default shell..."
    sudo chsh -s $(which zsh) $(whoami)
    echo "⚠️  Please restart your terminal for the shell change to take effect"
fi

# Create ~/bin directory if it doesn't exist
if [[ ! -d "$HOME/bin" ]]; then
    echo "📁 Creating ~/bin directory..."
    mkdir -p "$HOME/bin"
fi

# Add cargo bin to PATH if not already there
if [[ -d "$HOME/.cargo/bin" ]] && [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
    echo "Adding cargo bin to PATH..."
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
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
echo ""
echo "🔄 Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. If you installed Rust/Cargo, run: source ~/.cargo/env"
echo "  3. Your .zshrc dotfile should now work correctly!"
echo ""
echo "💡 Notes:"
echo "  - Make sure to link/copy your dotfiles to the correct locations"
echo "  - Ghostty was downloaded from the official website"
echo "  - Yazi was installed via Rust/Cargo for the latest version"



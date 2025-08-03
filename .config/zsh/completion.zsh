# Zsh completion and syntax highlighting
# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# Syntax highlighting for zsh
# Platform detection and conditional sourcing
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (using Homebrew)
    if [[ -f "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
        source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if [[ -f "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
        source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    fi
fi

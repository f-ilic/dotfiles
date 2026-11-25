# Fall back to xterm-256color if the current TERM has no terminfo entry (e.g. xterm-ghostty over SSH)
if ! infocmp "$TERM" &>/dev/null; then
    export TERM=xterm-256color
fi

ZSH_CONFIG_DIR="${HOME}/.config/zsh" # Configuration directory
PROMPT="%n@%m:%{$fg[cyan]%}%~%{$reset_color%}> "

source_if_exists() { # Helper function to source files safely
    [[ -r "$1" ]] && source "$1"
}

# Load core configuration modules in order
source_if_exists "$ZSH_CONFIG_DIR/exports.zsh"
source_if_exists "$ZSH_CONFIG_DIR/aliases.zsh"
source_if_exists "$ZSH_CONFIG_DIR/completion.zsh"
source_if_exists "$ZSH_CONFIG_DIR/filemanager.zsh"
source_if_exists "$ZSH_CONFIG_DIR/keybindings.zsh"
source_if_exists "$ZSH_CONFIG_DIR/history.zsh"
source_if_exists "$ZSH_CONFIG_DIR/local.zsh"

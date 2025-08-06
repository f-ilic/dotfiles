# Aliases and basic utility functions
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias lg='lazygit'
alias fzf-kill="ps -axo pid,user,command | fzf -m | awk '{print \$1}' | xargs kill"


# Micro does not like TERM=tmux..., so always start it with xterm-256color.
micro() { 
FZF_DEFAULT_OPTS="--style=full --border --preview='fzf-preview.sh {}' --layout reverse --bind=ctrl-k:kill-line"
TERM=xterm-256color command micro "$@"; 
}

tmux-scrollback-with-fzf() {
  local lines=${1:-1000}
  local capture_file="/tmp/tmux_capture_$(date +%s).log"
  local selection_file="/tmp/tmux_selection_$(date +%s).log"

  # Capture tmux scrollback
  tmux capture-pane -S -$lines -p > "$capture_file"

  # Let user select multiple lines with fzf
  cat "$capture_file" | fzf -m --height=80% > "$selection_file"

  # If there was a selection, open it
  if [ -s "$selection_file" ]; then
    eval "$EDITOR \"$selection_file\""
  fi
}

fcp() { # Copy file to clipboard on macOS
    osascript -e "tell application \"Finder\" to set the clipboard to (POSIX file \"$(pwd)/$1\")"
    echo "Copied to clipboard: $1"
}
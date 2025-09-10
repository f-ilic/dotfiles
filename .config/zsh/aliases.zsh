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

# Sourcing FZF: Platform detection and conditional sourcing
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    source <(fzf --zsh)
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
fi

bindkey -r '^[p' # Disable Alt+p for tmux compatibility

bindkey "^[t" fzf-file-widget # Alt+f = Ctrl+t (file search)
bindkey "^[r" fzf-history-widget # Alt+r = Ctrl+r (history search)
bindkey "^o" filemanager # Ctrl+o = file manager

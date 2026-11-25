# Sourcing FZF: Platform detection and conditional sourcing
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    command -v fzf >/dev/null && source <(fzf --zsh)
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux - try git-installed first, then apt-installed location
    if [ -f ~/.fzf.zsh ]; then
        source ~/.fzf.zsh
    elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    fi
fi

bindkey -r '^[p' # Disable Alt+p for tmux compatibility

# Only bind the fzf widgets if fzf's zsh integration actually loaded (no fzf = no dangling keys)
if (( $+widgets[fzf-file-widget] )); then
    bindkey "^[t" fzf-file-widget # Alt+f = Ctrl+t (file search)
    bindkey "^[r" fzf-history-widget # Alt+r = Ctrl+r (history search)
fi
bindkey "^o" filemanager # Ctrl+o = file manager

# FZF configuration and key bindings
# source <(fzf --zsh) # this was the old solution, but does not work on linux.
# WIP: checking if the solution below produces issues.
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey -r '^[p' # Disable Alt+p for tmux compatibility

bindkey "^[t" fzf-file-widget # Alt+f = Ctrl+t (file search)
bindkey "^[r" fzf-history-widget # Alt+r = Ctrl+r (history search)
bindkey "^o" filemanager # Ctrl+o = file manager

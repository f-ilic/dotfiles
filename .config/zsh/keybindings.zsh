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

# Alt-T / Ctrl-T options. Set here, not in exports.zsh: a git-installed fzf (~/.fzf/bin) only reaches PATH through the
# sourcing above. --style needs fzf 0.58+, and fzf-preview.sh comes with Homebrew's and git-installed fzf but not with
# Ubuntu's apt one, so each is used only where it exists (an unknown option would make the whole widget fail).
if command -v fzf >/dev/null; then
    FZF_CTRL_T_OPTS=""
    fzf --help 2>&1 | grep -q -- '--style' && FZF_CTRL_T_OPTS+="--style=full "
    command -v fzf-preview.sh >/dev/null && FZF_CTRL_T_OPTS+="--preview='fzf-preview.sh {}'"
    export FZF_CTRL_T_OPTS
fi

bindkey -r '^[p' # Disable Alt+p for tmux compatibility

# Only bind the fzf widgets if fzf's zsh integration actually loaded (no fzf = no dangling keys)
if (( $+widgets[fzf-file-widget] )); then
    bindkey "^[t" fzf-file-widget # Alt+f = Ctrl+t (file search)
    bindkey "^[r" fzf-history-widget # Alt+r = Ctrl+r (history search)
fi
bindkey "^o" filemanager # Ctrl+o = file manager

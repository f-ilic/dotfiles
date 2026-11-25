# Zsh completion and syntax highlighting
# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# Syntax highlighting for zsh: Homebrew (Apple Silicon, then Intel) or the distro package
for _zsh_hl in /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
               /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
               /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    if [[ -f $_zsh_hl ]]; then source $_zsh_hl; break; fi
done
unset _zsh_hl

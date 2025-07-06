# REQUIREMENTS: fzf, yazi, zsh, zsh-syntax-highlighting

# ----------------- exports -------------------
export PS1="%n@%m:%~%# "
export CLICOLOR=1
export LC_ALL=en_US.UTF-8

export PATH="$HOME/bin:$PATH"
export TERM="xterm-256color"

export EDITOR=micro
export VISUAL="$EDITOR"


# ----------------- aliases -------------------
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# -------------- file management --------------
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# zsh widget to preserve command line buffer
filemanager() {
  local saved_buffer="$BUFFER"
  local saved_cursor="$CURSOR"

  zle clear-screen   # clear screen before launching ranger
  y # this calls the function above

  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}

zle -N filemanager
bindkey '^o' filemanager
# ---------------------------------------------------------------------

# ---------------------------- OTHER ----------------------------------
# FZF configuration
source <(fzf --zsh)
export FZF_DEFAULT_OPTS='--bind=ctrl-k:kill-line'

# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# -------------------- syntax highlighting for zsh --------------------
# if mac
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# if linux
#source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

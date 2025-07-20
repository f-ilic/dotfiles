# REQUIREMENTS: fzf, yazi, zsh, zsh-syntax-highlighting
# ----------------- exports -------------------
autoload -Uz colors && colors
PROMPT="%n@%m:%{$fg[cyan]%}%~%{$reset_color%}> "
export CLICOLOR=1
export LC_ALL=en_US.UTF-8

export PATH="$HOME/bin:$PATH"

export EDITOR='env TERM=xterm-256color micro'
export VISUAL="$EDITOR"
export XDG_CONFIG_HOME="$HOME/.config"
export FZF_DEFAULT_OPTS="--border --layout reverse --bind=ctrl-k:kill-line"
# ----------------- aliases -------------------
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

alias lg='lazygit'

# Micro does not like TERM=tmux..., so  always start it with xterm-256color.
micro() { TERM=xterm-256color command micro "$@"; }

# -------------- file management --------------
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  exec < /dev/tty  # Ensure TTY input for fzf to work correctly

  local fzf_opts_extra="
	 --style=full --preview='fzf-preview.sh {}'
  "

  FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS $fzf_opts_extra" \
    command yazi "$@" --cwd-file="$tmp"

  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

# zsh widget to preserve command line buffer
filemanager() {
  local saved_buffer="$BUFFER"
  local saved_cursor="$CURSOR"

  zle clear-screen
  y

  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}

zle -N filemanager
bindkey '^o' filemanager

# ---------------------------- OTHER ----------------------------------
# FZF configuration
source <(fzf --zsh)

# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# Disable Alt+p for tmux compatibility
bindkey -r '^[p'

# -------------------- syntax highlighting for zsh --------------------
# if mac
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# if linux
#source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

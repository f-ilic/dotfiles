# REQUIREMENTS: zsh, fzf, ranger, zsh-syntax-highlighting

export PS1="%n@%m:%~%# "
export CLICOLOR=1
export LC_ALL=en_US.UTF-8
alias ll='ls -la'

export EDITOR=micro
export VISUAL="$EDITOR"

# FZF configuration
source <(fzf --zsh)
export FZF_DEFAULT_OPTS='--bind=ctrl-k:kill-line'


# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.


# -------------- YAZI  --------------
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# ------------------ ctr+o for ranger navigation ----------------------------
# Idea adapted from https://gist.github.com/LukeSmithxyz/e62f26e55ea8b0ed41a65912fbebbe52
# ranger_cd function: change directory using ranger
ranger_cd() {
  local tmpfile="$(mktemp)"
  ranger --choosedir="$tmpfile" "${@:-$PWD}" < /dev/tty > /dev/tty
  if [ -f "$tmpfile" ]; then
    local dir
    dir="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    if [ -d "$dir" ] && [ "$dir" != "$PWD" ]; then
      cd "$dir"
    fi
  fi
}

# zsh widget to preserve command line buffer
filemanager() {
  local saved_buffer="$BUFFER"
  local saved_cursor="$CURSOR"

  zle clear-screen   # clear screen before launching ranger
  y # if yazi
  # ranger_cd # if ranger

  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}

zle -N filemanager
bindkey '^o' filemanager
# ---------------------------------------------------------------------


# syntax highlighting for zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

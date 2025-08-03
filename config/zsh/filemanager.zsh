# File management functions and yazi integration
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

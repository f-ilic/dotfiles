# REQUIREMENTS: zsh, fzf, ranger, zsh-syntax-highlighting

export PS1="%n@%m:%~%# "
export CLICOLOR=1
export LC_ALL=en_US.UTF-8
alias ll='ls -la'

# FZF configuration
source <(fzf --zsh)
export FZF_DEFAULT_OPTS='--bind=ctrl-k:kill-line'


# Basic auto/tab complete for zsh:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.


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
ranger_cd_widget() {
  local saved_buffer="$BUFFER"
  local saved_cursor="$CURSOR"

  zle clear-screen   # optional: clear screen before launching ranger
  ranger_cd

  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}

zle -N ranger_cd_widget
bindkey '^o' ranger_cd_widget
# ---------------------------------------------------------------------


# # >>> conda initialize >>>
# # !! Contents within this block are managed by 'conda init' !!
# __conda_setup="$('/opt/homebrew/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
# if [ $? -eq 0 ]; then
#     eval "$__conda_setup"
# else
#     if [ -f "/opt/homebrew/anaconda3/etc/profile.d/conda.sh" ]; then
#         . "/opt/homebrew/anaconda3/etc/profile.d/conda.sh"
#     else
#         export PATH="/opt/homebrew/anaconda3/bin:$PATH"
#     fi
# fi
# unset __conda_setup
# # <<< conda initialize <<<

# #>>> Ruby chruby >>>
# source /opt/homebrew/opt/chruby/share/chruby/chruby.sh
# source /opt/homebrew/opt/chruby/share/chruby/auto.sh
# chruby ruby-3.1.3
# #<<< Ruby chruby <<<

# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
# export NODE_PATH=$NODE_PATH:`npm root -g`


# syntax highlighting for zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
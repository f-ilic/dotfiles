# Core environment variables and exports
autoload -Uz colors && colors
export CLICOLOR=1
export LC_ALL=en_US.UTF-8

export PATH="$HOME/bin:$PATH"

export EDITOR='env TERM=xterm-256color micro'
export VISUAL="$EDITOR"
export XDG_CONFIG_HOME="$HOME/.config"

export FZF_DEFAULT_OPTS="--border --layout reverse --bind=ctrl-k:kill-line"
export FZF_CTRL_T_OPTS="--style=full --preview='fzf-preview.sh {}'"
export FZF_ALT_C_OPTS="--preview 'tree -C {}'"

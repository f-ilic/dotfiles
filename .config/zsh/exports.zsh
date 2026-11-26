# Core environment variables and exports
autoload -Uz colors && colors
export CLICOLOR=1
export LC_ALL=en_US.UTF-8

export PATH="$HOME/bin:$HOME/.local/bin:$PATH" # ~/.local/bin: where uv, pipx and the Linux installs put things

export EDITOR='env TERM=xterm-256color micro'
export VISUAL="$EDITOR"
export XDG_CONFIG_HOME="$HOME/.config"

export FZF_DEFAULT_OPTS="--border --layout reverse --bind=ctrl-k:kill-line"
export FZF_CTRL_R_OPTS="--preview-window=hidden"
# FZF_CTRL_T_OPTS is set in keybindings.zsh, once fzf is on PATH
export FZF_ALT_C_OPTS="--preview 'tree -C {}'"

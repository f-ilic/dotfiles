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
# Alt-T / Ctrl-T. --style needs fzf 0.58+ and fzf-preview.sh comes with Homebrew's fzf; Ubuntu's apt fzf has neither,
# so each is only used where it exists (an unknown option would make the whole widget fail).
FZF_CTRL_T_OPTS=""
fzf --help 2>&1 | grep -q -- '--style' && FZF_CTRL_T_OPTS+="--style=full "
command -v fzf-preview.sh >/dev/null && FZF_CTRL_T_OPTS+="--preview='fzf-preview.sh {}'"
export FZF_CTRL_T_OPTS
export FZF_ALT_C_OPTS="--preview 'tree -C {}'"

# Fall back to xterm-256color if the current TERM has no terminfo entry (e.g. xterm-ghostty over SSH)
if ! infocmp "$TERM" &>/dev/null; then
    export TERM=xterm-256color
fi

source "${HOME}/.config/zsh/init.zsh"

# ----------------------------- MACHINE SPECIFIC SETTINGS ---------------------------


# ----------------------------- AUTO-GENERATED SECTIONS -----------------------------

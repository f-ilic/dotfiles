#!/usr/bin/env bash
# Entry point for these dotfiles on any machine. It installs what the configs need and links them.
#   ./start.sh            one screen: what is installed, what Apply will do
#   ./start.sh --check    the same status without a UI; exit 1 if something needed is missing or blocked
#   ./start.sh --plain    the same flow as plain text with a y/N question
# Day to day it is just `git pull && stow .`; run this on a new machine, or when stow complains.
# The screen needs textual. It runs through uv in a throwaway environment, so system python is never touched;
# without uv it falls back to a private venv under ~/.cache, and without that to the plain-text flow.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/install_scripts/setup_tui.py"

# --check and --plain are stdlib-only: no uv, no textual, they work anywhere python3 exists
if [[ "${1:-}" == "--check" || "${1:-}" == "--plain" ]]; then
    exec python3 "$SCRIPT" "$@"
fi

UV="$(command -v uv || true)"
if [[ -z "$UV" ]]; then
    for candidate in "$HOME/.local/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
        if [[ -x "$candidate" ]]; then UV="$candidate"; break; fi
    done
fi
if [[ -n "$UV" ]]; then
    exec "$UV" run --quiet --script "$SCRIPT" "$@"
fi

VENV="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-setup/venv"
if [[ ! -x "$VENV/bin/python" ]]; then
    if ! { python3 -m venv "$VENV" 2>/dev/null && "$VENV/bin/pip" install --quiet textual 2>/dev/null; }; then
        rm -rf "$VENV"  # the half-built one this very run just created
        echo "No uv, and a venv with textual could not be built here: using the plain-text flow." >&2
        exec python3 "$SCRIPT" --plain
    fi
fi
exec "$VENV/bin/python" "$SCRIPT" "$@"

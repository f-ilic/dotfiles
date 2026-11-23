#!/usr/bin/env bash
# Entry point for these dotfiles on any machine:   ./start.sh   (TUI)    ./start.sh --check   (no UI)
# Day to day it is just `git pull && stow .`. Run this the first time on a machine, or when stow complains.
# The TUI needs textual. It runs through uv in a throwaway environment, so system python is never touched;
# without uv it falls back to a private venv under ~/.cache.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/install_scripts/setup_tui.py"

# --check is stdlib-only: no uv, no textual, works anywhere python3 exists
if [[ "${1:-}" == "--check" ]]; then
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
    python3 -m venv "$VENV" || { echo "need uv (https://docs.astral.sh/uv/) or python3-venv" >&2; exit 1; }
    "$VENV/bin/pip" install --quiet textual
fi
exec "$VENV/bin/python" "$SCRIPT" "$@"

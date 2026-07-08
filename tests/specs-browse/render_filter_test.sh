#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
command -v fzf >/dev/null || { echo "$(basename "$0"): SKIP (no fzf)"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/paths" <<'EOF'
/
/data
/data/app
/data/app/lens.apk
/data/system
/data/system/batterystats.bin
/vendor
/vendor/etc
/vendor/etc/battery.cfg
EOF
: > "$tmp/expanded"
export SPECS_BROWSE_PATHS="$tmp/paths" SPECS_BROWSE_EXPANDED="$tmp/expanded" SPECS_BROWSE_ROOT="/"

out="$("$SB" --__render "battery" | cut -f2)"
assert_contains     "match keeps batterystats leaf"   "$out" "batterystats.bin"
assert_contains     "match keeps battery.cfg leaf"    "$out" "battery.cfg"
assert_contains     "ancestor 'system' shown expanded" "$out" "▾ system"
assert_contains     "ancestor 'etc' shown expanded"    "$out" "▾ etc"
assert_not_contains "non-matching lens.apk hidden"     "$out" "lens.apk"
finish

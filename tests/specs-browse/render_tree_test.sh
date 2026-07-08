#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
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

exp_collapsed=$'▾ /\n  ▸ data\n  ▸ vendor'
got="$("$SB" --__render "" | cut -f2)"
assert_eq "collapsed root shows depth-1 dirs only" "$exp_collapsed" "$got"

printf '/data\n' > "$tmp/expanded"
exp_expanded=$'▾ /\n  ▾ data\n    ▸ app\n    ▸ system\n  ▸ vendor'
got="$("$SB" --__render "" | cut -f2)"
assert_eq "expanding /data reveals exactly one more level" "$exp_expanded" "$got"
finish

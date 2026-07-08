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
export SPECS_BROWSE_PATHS="$tmp/paths" SPECS_BROWSE_EXPANDED="$tmp/expanded"

: > "$tmp/expanded"
"$SB" --__expand-all
exp=$'/\n/data\n/data/app\n/data/system\n/vendor\n/vendor/etc'
assert_eq "expand-all records every directory" "$exp" "$(cat "$tmp/expanded")"

: > "$tmp/expanded"
"$SB" --__act /data
assert_eq "act on dir adds it to expanded"      "/data" "$(cat "$tmp/expanded")"
"$SB" --__act /data
assert_eq "act on same dir removes it"          ""      "$(cat "$tmp/expanded")"

# --__toggle is dir-only (safe to bind to a silent key that never opens files)
: > "$tmp/expanded"
"$SB" --__toggle /data/app/lens.apk
assert_eq "toggle on a FILE is a no-op"         ""        "$(cat "$tmp/expanded")"
"$SB" --__toggle /vendor
assert_eq "toggle on a DIR expands it"          "/vendor" "$(cat "$tmp/expanded")"
finish

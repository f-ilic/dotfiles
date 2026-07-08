#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"

raw=$'/a/z\n/a//b/\n/a\n/\n/a-b\n/a/b/c\n/a'
# expected pre-order: '/' sorts first, children of /a before sibling /a-b
exp=$'/\n/a\n/a/b\n/a/b/c\n/a/z\n/a-b'
got="$(printf '%s\n' "$raw" | "$SB" --__treesort)"
assert_eq "treesort: pre-order + collapse-slash + strip-trailing + dedup" "$exp" "$got"
finish

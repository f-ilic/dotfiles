#!/usr/bin/env bash
. "$(dirname "$0")/_helpers.sh"
assert_eq "prune expr joins paths with -o -path" \
  "-path /proc -o -path /sys -o -path /dev" \
  "$("$SB" --__prune-expr "/proc /sys /dev")"
assert_eq "prune expr single path" \
  "-path /proc" \
  "$("$SB" --__prune-expr "/proc")"
finish

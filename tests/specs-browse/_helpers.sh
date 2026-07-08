# shared test helpers — source me
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$(cd "$_here/../.." && pwd)/bin/specs-browse"
_p=0; _f=0
assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then _p=$((_p+1)); else _f=$((_f+1));
    printf 'FAIL %s\n--- expected ---\n%s\n--- actual ---\n%s\n---\n' "$1" "$2" "$3"; fi
}
assert_contains() { # name haystack needle
  case "$2" in *"$3"*) _p=$((_p+1));; *) _f=$((_f+1));
    printf 'FAIL %s (missing: %s)\n%s\n' "$1" "$3" "$2";; esac
}
assert_not_contains() { # name haystack needle
  case "$2" in *"$3"*) _f=$((_f+1));
    printf 'FAIL %s (should NOT contain: %s)\n%s\n' "$1" "$3" "$2";; *) _p=$((_p+1));; esac
}
finish() { echo "$(basename "$0"): pass=$_p fail=$_f"; [ "$_f" -eq 0 ]; }

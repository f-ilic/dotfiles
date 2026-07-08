#!/usr/bin/env bash
# runs every *_test.sh in this directory; nonzero exit if any fail
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in "$here"/*_test.sh; do bash "$t" || rc=1; done
exit $rc

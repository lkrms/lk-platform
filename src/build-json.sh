#!/bin/bash

set -euo pipefail
out=$(mktemp)
die() { echo "${BASH_SOURCE-$0}: $1" >&2 && rm -f "$out" && false || exit; }

_dir=${BASH_SOURCE%${BASH_SOURCE##*/}}
_dir=${_dir:-$PWD}
_dir=$(cd "$_dir" && pwd -P)
cd "$_dir/.."

set -- src/lib/bash/core.sh.d/[0-9][0-9]-regular-expressions.sh \
    lib/json/regex.json

while [ $# -ge 2 ]; do
    s=$1
    [ -x "$s" ] || die "not executable: $s"
    d=$(cd "${2%/*}" && pwd -P) || die "invalid target path: $2"
    f=$d/${2##*/}
    echo "Building: $s -> $f" >&2
    "$s" --json >"$f"
    shift 2
done

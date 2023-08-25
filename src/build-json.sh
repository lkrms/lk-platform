#!/usr/bin/env bash

set -euo pipefail
out=$(mktemp)
trap 'rm -f "$out"' EXIT
die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }

_dir=${BASH_SOURCE%"${BASH_SOURCE##*/}"}
_dir=${_dir:-$PWD}
_dir=$(cd "$_dir" && pwd -P)
cd "$_dir/.."

write=1
[[ ${1-} != --no-write ]] || write=0

set -- src/lib/bash/core.sh.d/[0-9][0-9]-regular-expressions.sh \
    lib/json/regex.json

unset trash_cmd
for c in trash-put trash; do
    type -P "$c" >/dev/null || continue
    trash_cmd=$c
    break
done

[ -n "${trash_cmd-}" ] || {
    function trash() {
        local dest
        dest=$(mktemp "$1.XXXXXX") &&
            cp -a "$1" "$dest" &&
            rm -f "$1"
    }
    trash_cmd=trash
}

status=0

while [ $# -ge 2 ]; do
    src=$1
    [ -x "$src" ] || die "not executable: $src"
    dir=$(cd "${2%/*}" && pwd -P) || die "invalid target path: $2"
    dest=$dir/${2##*/}
    echo "Building: $src -> $dest" >&2
    "$src" --json >"$out"
    if [ -s "$out" ] &&
        ! diff -q --unidirectional-new-file "$dest" "$out" >/dev/null; then
        if ((write)); then
            [ ! -s "$dest" ] || "$trash_cmd" "$dest"
            cp "$out" "$dest"
            echo "  Target file replaced" >&2
        else
            echo "  REBUILD REQUIRED" >&2
            status=1
        fi
    else
        echo "  Target file not changed" >&2
    fi
    shift 2
done

exit "$status"

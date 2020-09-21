#!/bin/bash

set -euo pipefail
out=$(mktemp)
die() { echo "${BASH_SOURCE:-$0}: $1" >&2 && rm -f "$out" && false || exit; }

_DIR=${BASH_SOURCE%${BASH_SOURCE##*/}}
_DIR=${_DIR:-$PWD}
cd "$_DIR"

[ $# -gt 0 ] || set -- *.d

export LC_ALL=C

unset TRASH
for c in trash-put trash; do
    type -P "$c" >/dev/null || continue
    TRASH=$c
    break
done

[ -n "$TRASH" ] || die "no trash command available"

while [ $# -gt 0 ]; do
    d=${1##*/}
    d=${d%.d}
    d=${d%.sh}.sh.d
    [ -d "$d" ] || die "not a directory: $PWD/$d"
    echo "Building: $d" >&2
    {
        embed=0
        f=../include/${d%.d}
        if [ -e "$f" ] && grep -Fxq "#### BEGIN $d" "$f"; then
            embed=1
            awk -v "until=#### BEGIN $d" \
                'f{next}{print}$0==until{f=1;print""}' "$f"
        else
            printf '%s\n\n' "#!/bin/bash"
        fi
        for part in "$d"/*; do
            echo "  Processing: $part" >&2
            if [ -x "$part" ]; then
                "$part"
            else
                cat "$part"
            fi |
                awk 'NR<3 && $0 ~ /^(#!\/|$)/ {next} {print} END {print ""}' |
                sed -E \
                    's/^((\); )?\}) #### Reviewed: [0-9]{4}(-[0-9]{2}){2}$/\1/'
        done
        ! ((embed)) ||
            awk -v "from=#### END $d" \
                '$0==from{f=1}!f{next}{print}END{if(!f)exit 1}' "$f" ||
            die "not found in $PWD/$f: #### END $d"
    } >"$out"
    shfmt -i 4 -d "$out" >&2 ||
        die "incorrect formatting in part(s): $PWD/$d"
    if [ -s "$out" ] && ! diff -q "$f" "$out" >/dev/null; then
        "$TRASH" "$f"
        cp -v "$out" "$f"
        echo "Updated: $f" >&2
    else
        echo "Already up to date: $f" >&2
    fi
    shift
    ! (($#)) || echo
done

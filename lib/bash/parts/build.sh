#!/bin/bash

set -euo pipefail
out=$(mktemp)
die() { echo "${BASH_SOURCE-$0}: $1" >&2 && rm -f "$out" && false || exit; }

_dir=${BASH_SOURCE%${BASH_SOURCE##*/}}
_dir=${_dir:-$PWD}
cd "$_dir"

[ $# -gt 0 ] || set -- *.d

export LC_ALL=C

format=1
minify=1
shfmt_args=(-mn)
[ "${shfmt_minify-1}" = 1 ] || {
    minify=0
    shfmt_args=(-s -i "${shfmt_indent:-4}")
}
[ "${shfmt_simplify-1}" = 1 ] || {
    format=0
    minify=0
}

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
        elif ((!minify)); then
            printf '%s\n\n' "#!/bin/bash"
        fi
        i=0
        for part in "$d"/*; do
            echo "  Processing: $part" >&2
            ((!i || (!embed && minify))) || echo
            if [ -x "$part" ]; then
                "$part"
            else
                cat "$part"
            fi |
                # Remove shebangs, sections between "#### /*" and "#### */",
                # lines that start with "####", consecutive empty lines, and
                # trailing empty lines
                awk -v s="[[:blank:]]" '
NR == 1 && /^#!\//      {next}
skip < 0                {skip = 0}
/^#### \/\*/            {skip = 1}
/^#### \*\//            {skip = -1}
skip                    {next}
                        {if (gsub("(^|" s "+)####(" s ".*|$)", "") && !$0) next}
!f && /^./              {f = NR}
!f                      {next}
NR > f && last $0 != "" {print last}
                        {last = $0}
END                     {if (last) print last}' |
                if ((!embed && format)) && type -P shfmt >/dev/null; then
                    shfmt "${shfmt_args[@]}" | shfmt "${shfmt_args[@]}"
                else
                    cat
                fi
            ((++i))
        done
        ((!embed)) || awk -v "from=#### END $d" \
            '$0==from{if(!f)print"";f=1}!f{next}{print}END{if(!f)exit 1}' \
            "$f" || die "not found in $PWD/$f: #### END $d"
    } >"$out"
    args=(-i "${shfmt_indent:-4}")
    ((embed || !format)) ||
        args=("${shfmt_args[@]}")
    ! type -P shfmt >/dev/null ||
        shfmt "${args[@]}" -d "$out" >&2 ||
        die "incorrect formatting in part(s): $PWD/$d"
    if [ -s "$out" ] &&
        ! diff -q --unidirectional-new-file "$f" "$out" >/dev/null; then
        [ ! -s "$f" ] || "$trash_cmd" "$f"
        cp -v "$out" "$f"
        echo "Updated: $f" >&2
    else
        echo "Already up to date: $f" >&2
    fi
    shift
    ! (($#)) || echo
done

rm -f "$out"

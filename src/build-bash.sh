#!/usr/bin/env bash

set -euo pipefail
head=$(mktemp)
tail=$(mktemp)
out=$(mktemp)
out2=$(mktemp)
out3=$(mktemp)
trap 'rm -f "$head" "$tail" "$out" "$out2" "$out3"' EXIT
die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }

_dir=${BASH_SOURCE%"${BASH_SOURCE##*/}"}
_dir=${_dir:-$PWD}
_dir=$(cd "$_dir" && pwd -P)
cd "$_dir/.."

write=1
[[ ${1-} != --no-write ]] || write=0

set -- $(printf '%s\n' src/lib/bash/*.{sh,sh.d} | sed -E 's/\.d$//' | sort -u)

# Remove trailing structures like:
#
# ```
# true || {
#     command
#     ...
# }
# ```
function filter() {
    awk '
NR == 1 { f = $0; next }
        { f = f ORS $0 }
END     { sub("\ntrue \\|\\| \\{(\n[[:space:]]+[^[:space:]]+)+\n\\}", "", f); printf "%s", f }'
}

export LC_ALL=C

format=1
minify=1
shfmt_args=(-mn)
[ "${shfmt_minify-1}" = 1 ] || {
    minify=0
    shfmt_args=(-i "${shfmt_indent:-4}")
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

IFS=
status=0

while [ $# -gt 0 ]; do
    name=${1##*/}
    file=$1
    dir=$1.d
    dest=lib/bash/include/$name
    echo "Building: $dest" >&2
    {
        embed=0
        parts=("$file")
        if [ -e "$file" ] && grep -Eq "^#### (BEGIN|INCLUDE) $name.d\$" "$file"; then
            embed=1
            awk -v "until=^#### (BEGIN|INCLUDE) $name.d\$" \
                '$0~until{f=1}f{next}{print}' \
                "$file" >"$head"
            awk -v "from=^#### (END|INCLUDE) $name.d\$" \
                '$0~from{f=1;next}!f{next}{print}END{if(!f)exit 1}' \
                "$file" | filter >"$tail" ||
                die "not found in $PWD/$file: #### END $name.d"
            parts=("$head")
        fi
        echo "#!/bin/bash"
        ((minify)) || echo
        parts+=("$dir"/*)
        ((!embed)) || parts+=("$tail")
        i=0
        for part in "${parts[@]}"; do
            [ -f "$part" ] || continue
            echo "  - $part" >&2
            ((!i || minify)) || echo
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
                filter |
                if ((format)) && type -P shfmt >/dev/null; then
                    shfmt "${shfmt_args[@]}" | shfmt "${shfmt_args[@]}"
                else
                    cat
                fi | awk '
# Absorb empty shfmt output (it prints a newline even if there is no input), and
# return with exit status 2 if only whitespace lines were output
NR == 1 {first = $0; next}
NR == 2 {print first}
        {print}
f       {next}
/^./    {f = 2}
END     {if (NR == 1 && first) {print first; f = 2}; exit 2 - f}' && ((++i)) ||
                [[ ${PIPESTATUS[*]} =~ ^0+2$ ]]
        done
    } >"$out2"
    # Add inline scripts
    r="'\\\\\\\\''"
    awk -v out3="'${out3//"'"/$r}'" '
$1 == "lk_awk_load" && $4 != "-" {
  command = "gawk -f lib/awk/" $3 ".awk --profile=" out3 " </dev/null >/dev/null; sed -E \"s/^ *[0-9]+ */\t/; s/ # [0-9]+$//; /^[ \t]*(#.*)?$/d; s/^\t+//\" " out3
}
$1 == "lk_perl_load" && $4 != "-" {
  command = "perltidy -st -dp -dbc -dsc --mangle lib/perl/" $3 ".pl | awk \"NR==1 && /^#!/ {next} {print}\""
}
command {
  sub(/lk_[^ \t]+_load[ \t]+[^ \t]+[ \t]+[^ \t]+/, "& - <<\"EOF\"", $0)
  print
  while ((command | getline) > 0) { print }
  close(command)
  print "EOF"
  command = ""
  next
}
{ print }' "$out2" >"$out"
    args=(-i "${shfmt_indent:-4}")
    ((!format)) ||
        args=("${shfmt_args[@]}")
    ! type -P shfmt >/dev/null ||
        if ((minify)); then
            shfmt "${args[@]}" -d <(sed 1d "$out")
        else
            shfmt "${args[@]}" -d "$out"
        fi >&2 ||
        die "incorrect formatting in part(s): $PWD/$file"
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
    shift
    ! (($#)) || echo
done

exit "$status"

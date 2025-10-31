#!/usr/bin/env bash

function quote() {
    if [[ $1 =~ [^[:print:]] ]]; then
        printf '%q\n' "$1"
    else
        printf "'%s'\n" "${1//"'"/"'\\''"}"
    fi
}

set -euo pipefail

# "core" builds before "prompt"
. lib/bash/include/core.sh

eval "$(lk_get_regex NON_PRINTING_REGEX)"
script=(
    "s/$NON_PRINTING_REGEX//g"
    $'s/\r/\\\\r/g'
    '$b'
    's/$/\\n/'
)
args=
for expr in "${script[@]}"; do
    args+=$' \\\n'"        -e $(quote "$expr")"
done

printf '# _lk_prompt_filter
#
# Reduce input to a line of printable characters by removing escape
# sequences and non-printing characters, representing newlines as "\\n"
# and "\\r", and removing ASCII control characters.
function _lk_prompt_filter() {
    LC_ALL=C sed -E%s | tr -d %s
}\n' "$args" "$(quote '\n\0-\10\16-\37\177')"

#### Reviewed: 2025-10-31

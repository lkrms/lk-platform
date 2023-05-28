#!/bin/bash

function quote() {
    if [[ $1 =~ [^[:print:]] ]]; then
        printf '%q\n' "$1"
    else
        local r="'\\''"
        echo "'${1//"'"/$r}'"
    fi
}

# 1. Name
# 2. GNU format string
# 3. BSD arguments (optional)
# 4. BSD format string
# 5. Shell pipeline (optional)
STAT_FORMATS=(
    owner '%U' '' '%Su' ''
    group '%G' '' '%Sg' ''
    # On BSD, output octal (O) file mode (p) twice, first for the suid, sgid,
    # and sticky bits (M), then with zero-padding (03) for the user, group, and
    # other bits (L)
    mode '%04a' '' '%OMp%03OLp' ''
    owner_mode '%U:%G %04a' '' '%Su:%Sg %OMp%03OLp' ''
    modified '%Y' "-t $(quote '%s')" '%Sm' ''
    sort_modified '%Y :%n' "-t $(quote '%s')" '%Sm :%N' ' | sort -n | cut -d: -f2-'
)

for ((i = 0; i < ${#STAT_FORMATS[@]}; i += 5)); do
    FN=${STAT_FORMATS[i]}
    GNU=$(quote "${STAT_FORMATS[i + 1]}")
    ARG=${STAT_FORMATS[i + 2]}
    BSD=$(quote "${STAT_FORMATS[i + 3]}")
    SH=${STAT_FORMATS[i + 4]}
    printf 'function lk_file_%s() {
    if ! lk_is_macos; then
        function lk_file_%s() { lk_sudo_on_fail stat -c %s -- "$@"%s; }
    else
        function lk_file_%s() { lk_sudo_on_fail stat %s-f %s -- "$@"%s; }
    fi
    lk_file_%s "$@"
}\n\n' "$FN" "$FN" "$GNU" "$SH" "$FN" "${ARG:+$ARG }" "$BSD" "$SH" "$FN"
done

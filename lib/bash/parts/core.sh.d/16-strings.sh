#!/bin/bash

# lk_implode_args GLUE [ARG...]
function lk_implode_args() {
    local GLUE=${1//\\/\\\\}
    GLUE=${GLUE//%/%%}
    [ $# -eq 1 ] || printf '%s' "$2"
    [ $# -le 2 ] || printf -- "$GLUE%s" "${@:3}"
    printf '\n'
}

# lk_implode_arr GLUE [ARRAY_NAME...]
function lk_implode_arr() {
    local _ARR _EVAL=
    for _ARR in "${@:2}"; do
        _EVAL+=" \${$_ARR+\"\${${_ARR}[@]}\"}"
    done
    eval "lk_implode_args \"\$1\" $_EVAL"
}

# lk_implode_input GLUE
function lk_implode_input() {
    awk -v "OFS=$1" 'NR > 1 { printf "%s", OFS } { printf "%s", $0 }'
}

function lk_ere_escape() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_ere_escape
    else
        sed -E 's/[]$()*+.?\^{|}[]/\\&/g'
    fi
}

# lk_ere_implode_input [-e]
#
# If -e is set, escape each input line.
function lk_ere_implode_input() {
    if [ "${1-}" != -e ]; then
        awk '
NR == 1 { first = $0; next }
NR == 2 { printf "(%s", first }
        { printf "|%s", $0 }
END     { if (NR > 1) { print ")" } else if (NR) { printf "%s\n", first } }'
    else
        lk_ere_escape | lk_ere_implode_input
    fi
}

function lk_sed_escape() {
    local DELIM=${_LK_SED_DELIM-/}
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_sed_escape
    else
        sed -E "s/[]\$()*+.$DELIM?\\^{|}[]/\\\\&/g"
    fi
}

function lk_strip_cr() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_strip_cr
    else
        sed -E 's/.*\r(.)/\1/'
    fi
}

# lk_strip_non_printing [-d DELETE] [STRING...]
#
# Remove escape sequences and non-printing characters from each STRING or input
# line, including carriage returns that aren't part of a CRLF line ending and
# any characters appearing before them on the same line. Use -d to specify
# additional characters to remove (DELETE is passed directly to `tr -d`).
function lk_strip_non_printing() {
    local DELETE
    [ "${1-}" != -d ] || { DELETE=$2 && shift 2; }
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_strip_non_printing ${DELETE:+-d "$DELETE"}
    else
        eval "$(lk_get_regex NON_PRINTING_REGEX)"
        ${LK_EXEC:+exec} sed -Eu "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/' |
            lk_unbuffer ${LK_EXEC:+exec} tr -d '\0-\10\16-\37\177'"${DELETE-}"
    fi
}

# lk_string_sort [[SORT_ARGS] STRING]
function lk_string_sort() {
    local IFS=${IFS:- } ARGS
    [ $# -le 1 ] || { ARGS=$1 && shift; }
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" '\0' |
        sort -z ${ARGS:+"$ARGS"} | tr '\0' "${IFS::1}" |
        sed -E '1s/^.//; $s/.$//'
}

# lk_string_remove [STRING [REMOVE...]]
function lk_string_remove() {
    local IFS=${IFS:- } REGEX
    REGEX=$([ $# -le 1 ] || printf '%s\n' "${@:2}" | lk_ere_implode_input)
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" "${IFS::1}" |
        awk -v "RS=${IFS::1}" -v "regex=$REGEX" \
            'NR == 1 {next} $0 !~ regex {printf "%s%s", (i++ ? RS : ""), $0 }'
}

#### Reviewed: 2021-08-28

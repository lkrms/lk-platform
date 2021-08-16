#!/bin/bash

# lk_plural -v VALUE SINGLE_NOUN PLURAL_NOUN
#
# Print SINGLE_NOUN if VALUE is 1, PLURAL_NOUN otherwise. If -v is set, include
# VALUE in the output.
function lk_plural() {
    local VALUE=
    [ "${1-}" != -v ] || { VALUE="$2 " && shift; }
    [ "$1" -eq 1 ] && echo "$VALUE$2" || echo "$VALUE$3"
}

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
        sed -E "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/' |
            tr -d '\0-\10\16-\37\177'"${DELETE-}"
    fi
}

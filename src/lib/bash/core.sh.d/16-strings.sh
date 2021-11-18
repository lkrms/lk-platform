#!/bin/bash

# _lk_stream_args COMMAND_ARGS COMMAND... [ARG...]
function _lk_stream_args() {
    local IFS
    unset IFS
    if (($# > $1 + 1)); then
        printf '%s\n' "${@:$1+2}" | "${@:2:$1}"
    else
        [ "$(type -t "$2")" = file ] || local LK_EXEC
        ${LK_EXEC:+exec} "${@:2:$1}"
    fi
}

# lk_uniq [STRING...]
function lk_uniq() {
    _lk_stream_args 2 awk '!seen[$0]++ { print }' "$@"
}

# lk_double_quote [-f] [STRING...]
#
# If -f is set, add double quotes even if STRING only contains letters, numbers
# and safe punctuation (i.e. + - . / @ _).
function lk_double_quote() {
    local FORCE
    unset FORCE
    [ "${1-}" != -f ] || { FORCE= && shift; }
    _lk_stream_args 3 sed -E \
        ${FORCE-$'/^[a-zA-Z0-9+./@_-]*$/b\n'}'s/["$\`]/\\&/g; s/.*/"&"/' "$@"
}

# lk_implode_args GLUE [ARG...]
function lk_implode_args() {
    local IFS GLUE=${1//\\/\\\\}
    unset IFS
    GLUE=${GLUE//%/%%}
    [ $# -eq 1 ] || printf '%s' "$2"
    [ $# -le 2 ] || printf -- "$GLUE%s" "${@:3}"
    printf '\n'
}

# lk_implode_input GLUE
function lk_implode_input() {
    awk -v "OFS=$1" 'NR > 1 { printf "%s", OFS } { printf "%s", $0 }'
}

function lk_ere_escape() {
    _lk_stream_args 3 sed -E 's/[]$()*+.?\^{|}[]/\\&/g' "$@"
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

# lk_ere_implode_args [-e] [--] [ARG...]
function lk_ere_implode_args() {
    local ARGS
    [ "${1-}" != -e ] || { ARGS=(-e) && shift; }
    [ "${1-}" != -- ] || shift
    [ $# -eq 0 ] ||
        printf '%s\n' "$@" | lk_ere_implode_input ${ARGS+"${ARGS[@]}"}
}

function lk_sed_escape() {
    _lk_stream_args 3 sed -E 's/[]$()*+./?\^{|}[]/\\&/g' "$@"
}

function lk_sed_escape_replace() {
    _lk_stream_args 3 sed -E 's/[&/\]/\\&/g' "$@"
}

function lk_strip_cr() {
    LC_ALL=C _lk_stream_args 3 sed -E $'s/.*\r(.)/\\1/' "$@"
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
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    LC_ALL=C _lk_stream_args 3 \
        sed -Eu "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/' "$@" |
        lk_unbuffer tr -d '\0-\10\16-\37\177'"${DELETE-}"
}

# lk_string_sort [[SORT_ARGS] STRING]
function lk_string_sort() {
    local IFS=${IFS:- } ARGS
    [ $# -le 1 ] || { ARGS=$1 && shift; }
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" '\0' |
        sort -z ${ARGS:+"$ARGS"} | tr '\0' "${IFS::1}" |
        awk -v "RS=${IFS::1}" '
NR == 1 {next}
        {printf "%s%s", (i++ ? RS : ""), $0}
END     {printf "\n"}'
}

# lk_string_remove [STRING [REMOVE...]]
function lk_string_remove() {
    local IFS=${IFS:- } REGEX
    REGEX=$(unset IFS && [ $# -le 1 ] ||
        printf '%s\n' "${@:2}" | lk_ere_implode_input -e)
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" "${IFS::1}" |
        awk -v "RS=${IFS::1}" -v "regex=^${REGEX//\\/\\\\}\$" '
NR == 1     {next}
$0 !~ regex {printf "%s%s", (i++ ? RS : ""), $0}
END         {printf "\n"}'
}

#### Reviewed: 2021-10-21

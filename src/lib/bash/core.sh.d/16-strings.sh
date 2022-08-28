#!/bin/bash

# _lk_stream_args COMMAND_ARGS COMMAND... [ARG...]
function _lk_stream_args() {
    local IFS=$' \t\n'
    if (($# > $1 + 1)); then
        printf '%s\n' "${@:$1+2}" | "${@:2:$1}"
    else
        local EXEC=1
        [ "$(type -t "$2")" = file ] || EXEC=
        ${EXEC:+${LK_EXEC:+exec}} "${@:2:$1}"
    fi
}

# lk_uniq [STRING...]
function lk_uniq() {
    _lk_stream_args 2 awk '!seen[$0]++ { print }' "$@"
}

# lk_ellipsise LENGTH [STRING...]
function lk_ellipsise() {
    local LENGTH=$1
    shift
    _lk_stream_args 4 awk -v "l=$LENGTH" '
length($0) > l  { print substr($0, 1, l - 3) "..."; next }
                { print }' "$@"
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

# lk_args_wider_than WIDTH [ARG...]
function lk_args_wider_than() {
    local IFS=$' \t\n' ARGS
    ARGS=${*:2}
    ((${#ARGS} > $1))
}

# _lk_fold_check_sh [-WIDTH] [ARG...]
function _lk_fold_check_sh() {
    [[ ${1-} =~ ^-[0-9]+$ ]] || return 0
    local WIDTH=${1#-}
    shift
    echo shift
    ! lk_args_wider_than "$WIDTH" "$@" || return 0
    echo 'lk_quote_args "$@"'
    echo return
}

# lk_quote_args [ARG...]
#
# Use `printf %q` to print the arguments on a space-delimited line.
function lk_quote_args() {
    ((!$#)) || { printf '%q' "$1" && shift; }
    ((!$#)) || printf ' %q' "$@"
    printf '\n'
}

# lk_fold_quote_args [-WIDTH] [ARG...]
#
# Same as lk_quote_args, but print each argument on a new line. If WIDTH is set,
# don't fold unless arguments would occupy more than WIDTH columns on a
# space-delimited line.
function lk_fold_quote_args() {
    eval "$(_lk_fold_check_sh "$@")"
    ((!$#)) || { printf '%q' "$1" && shift; }
    ((!$#)) || printf ' \\\n    %q' "$@"
    printf '\n'
}

# lk_fold_quote_options [-WIDTH] [ARG...]
#
# Same as lk_fold_quote_args, but only start a new line before arguments that
# start with "-".
function lk_fold_quote_options() {
    eval "$(_lk_fold_check_sh "$@")"
    ((!$#)) || { printf '%q' "$1" && shift; }
    while (($#)); do
        [[ $1 == -* ]] && printf ' \\\n    %q' "$1" || printf ' %q' "$1"
        shift
    done
    printf '\n'
}

# lk_implode_args GLUE [ARG...]
function lk_implode_args() {
    local IFS=$' \t\n' GLUE=${1//\\/\\\\}
    GLUE=${GLUE//%/%%}
    [ $# -eq 1 ] || printf '%s' "$2"
    [ $# -le 2 ] || printf -- "$GLUE%s" "${@:3}"
    printf '\n'
}

# lk_implode_input GLUE
function lk_implode_input() {
    [ -z "${_LK_INPUT_DELIM+1}" ] ||
        local _LK_INPUT_DELIM=${_LK_INPUT_DELIM:-\\0}
    awk -v "OFS=$1" \
        -v "RS=${_LK_INPUT_DELIM-\\n}" \
        'NR > 1 { printf "%s", OFS } { printf "%s", $0 }'
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
    ((!$#)) ||
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
    LC_ALL=C _lk_stream_args 4 \
        lk_unbuffer sed -E "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/' "$@" |
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

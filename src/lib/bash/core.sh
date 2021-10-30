#!/bin/bash

#### INCLUDE core.sh.d

function _lk_usage_format() {
    local CMD BOLD RESET
    CMD=$(lk_escape_ere "$(lk_caller_name 1)")
    BOLD=$(lk_escape_ere_replace "$LK_BOLD")
    RESET=$(lk_escape_ere_replace "$LK_RESET")
    sed -E \
        -e "s/^($S*(([uU]sage|[oO]r):$S+)?(sudo )?)($CMD)($S|\$)/\1$BOLD\5$RESET\6/" \
        -e "s/^([a-zA-Z0-9][a-zA-Z0-9 ]*:|[A-Z0-9][A-Z0-9 ]*)\$/$BOLD&$RESET/" \
        -e "s/^\\\\(.)/\\1/" <<<"$1"
}

function lk_usage() {
    local EXIT_STATUS=$? MESSAGE=${1:-${LK_USAGE-}}
    [ -z "$MESSAGE" ] || MESSAGE=$(_lk_usage_format "$MESSAGE")
    _LK_TTY_NO_FOLD=1 \
        lk_console_log "${MESSAGE:-$(LK_VERBOSE= _lk_caller): invalid arguments}"
    if [[ $- != *i* ]]; then
        exit "$EXIT_STATUS"
    else
        return "$EXIT_STATUS"
    fi
}

if lk_bash_at_least 4 2; then
    # lk_date FORMAT [TIMESTAMP]
    function lk_date() {
        # Take advantage of printf support for strftime in Bash 4.2+
        printf "%($1)T\n" "${2:--1}"
    }
else
    if ! lk_is_macos; then
        # lk_date FORMAT [TIMESTAMP]
        function lk_date() {
            if [ $# -lt 2 ]; then
                gnu_date "+$1"
            else
                gnu_date -d "@$2" "+$1"
            fi
        }
    else
        # lk_date FORMAT [TIMESTAMP]
        function lk_date() {
            if [ $# -lt 2 ]; then
                date "+$1"
            else
                date -jf '%s' "$2" "+$1"
            fi
        }
    fi
fi #### Reviewed: 2021-04-30

# lk_date_log [TIMESTAMP]
function lk_date_log() {
    lk_date "%Y-%m-%d %H:%M:%S %z" "$@"
} #### Reviewed: 2021-03-26

# lk_date_ymdhms [TIMESTAMP]
function lk_date_ymdhms() {
    lk_date "%Y%m%d%H%M%S" "$@"
} #### Reviewed: 2021-03-26

# lk_date_ymd [TIMESTAMP]
function lk_date_ymd() {
    lk_date "%Y%m%d" "$@"
} #### Reviewed: 2021-03-26

# lk_timestamp
function lk_timestamp() {
    lk_date "%s"
} #### Reviewed: 2021-03-26

if lk_bash_at_least 4 1; then
    function lk_pause() {
        local REPLY
        # A homage to MS-DOS
        read -rs -N 1 \
            -p "$(lk_readline_format "${1:-Press any key to continue . . . }")"
        lk_console_blank
    }
else
    function lk_pause() {
        local REPLY
        read -rs \
            -p "$(lk_readline_format "${1:-Press return to continue . . . }")"
        lk_console_blank
    }
fi

function lk_double_quote() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_double_quote
    else
        sed -E 's/["$\`]/\\&/g; s/.*/"&"/'
    fi
}

# lk_get_shell_var [VAR...]
#
# Output a shell variable assignment for each declared VAR.
function lk_get_shell_var() {
    while [ $# -gt 0 ]; do
        if [ -n "${!1:+1}" ]; then
            printf '%s=%s\n' "$1" "$(lk_double_quote "${!1}")"
        elif [ -n "${!1+1}" ]; then
            printf '%s=\n' "$1"
        fi
        shift
    done
}

function lk_get_quoted_var() {
    while [ $# -gt 0 ]; do
        lk_maybe_local
        if [ -n "${!1-}" ]; then
            printf '%s=%q\n' "$1" "${!1}"
        else
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_get_env [-n] [VAR...]
function lk_get_env() {
    local _LK_VAR_LIST=
    [ "${1-}" != -n ] || { _LK_VAR_LIST=1 && shift; }
    if [ -n "${_LK_ENV+1}" ]; then
        echo "$_LK_ENV"
    else
        declare -x
    fi | awk \
        -v var="$(lk_regex_implode "$@")" \
        -v var_list="$_LK_VAR_LIST" \
        -v prefix="$(lk_maybe_local)" \
        'BEGIN {
    declare = "^declare -[^ ]+ "
    any_var = "[a-zA-Z_][a-zA-Z0-9_]*"
    var = var ? var : any_var
    val = "([^\"\\\\]+|\\.)*"
}
function print_line() {
    l = c ? l : $0
    sub(declare, "", l)
    if (var_list)
        sub("=\".*", "", l)
    else
        l = prefix l
    print l
}
!c && $0 ~ declare any_var "$" { next }
!c && $0 ~ declare var "=\"" val "\"$" { print_line(); next }
!c && $0 ~ declare var "=\"" val "$" { c = 1; l = $0; next }
var != any_var && !c && $0 ~ declare any_var "=\"" val "\"$" { next }
var != any_var && !c && $0 ~ declare any_var "=\"" val "$" { c = 2; next }
c == 1 { l = l "\"$\47\\n\47\"" $0 }
c && $0 ~ "^" val "\"$" { if (c == 1) print_line(); c = 0 }'
} #### Reviewed: 2021-06-07

# lk_path_edit REMOVE_REGEX [MOVE_REGEX [PATH]]
function lk_path_edit() {
    [ $# -gt 0 ] || lk_usage "\
Usage: $FUNCNAME REMOVE_REGEX [MOVE_REGEX [PATH]]" || return
    awk \
        -v "remove=$1" \
        -v "move=${2-}" \
        'function p(v) { printf "%s%s", s, v; s = ":" }
BEGIN { RS = "[:\n]+" }
remove && $0 ~ remove { next }
move && $0 ~ move { a[i++] = $0; next }
{ p($0) }
END{ for (i = 0; i < length(a); i++) p(a[i]) }' <<<"${3-$PATH}"
} #### Reviewed: 2021-05-10

# lk_check_pid PID
#
# Return true if a signal could be sent to the given process by the current
# user.
function lk_check_pid() {
    [ $# -eq 1 ] || return
    lk_maybe_sudo kill -0 "$1" 2>/dev/null
}

# lk_curl_config [--]ARG[=PARAM]...
#
# Output each ARG=PARAM pair formatted for use with `curl --config`.
function lk_curl_config() {
    awk 'BEGIN {
    for (i = 1; i < ARGC; i++) {
        if (ARGV[i] !~ /^(--)?[^-=[:blank:]][^=[:blank:]]*(=.*)?$/) {
            print "invalid argument: " ARGV[i] | "cat >&2"
            exit 1
        }
        name = value = ARGV[i]
        gsub(/(^--|=.*)/, "", name)
        sub(/^[^=]+/, "", value)
        if (!value) {
            printf "--%s\n", name
        } else {
            sub(/^=/, "", value)
            gsub(/["\\]/, "\\\\&", value)
            gsub(/\t/, "\\t", value)
            gsub(/\n/, "\\n", value)
            gsub(/\r/, "\\r", value)
            gsub(/\v/, "\\v", value)
            printf "--%s \"%s\"\n", name, value
        }
    }
}' "$@"
}

# lk_regex_case_insensitive STRING
#
# Replace each alphabetic character in STRING with a bracket expression that
# matches its lower- and upper-case equivalents.
#
# Example:
#
#     $ lk_regex_case_insensitive True
#     [tT][rR][uU][eE]
function lk_regex_case_insensitive() {
    local i l LOWER UPPER REGEX=
    [ $# -gt 0 ] || lk_warn "no string" || return
    [ -n "$1" ] || return 0
    for i in $(seq 0 $((${#1} - 1))); do
        l=${1:$i:1}
        [[ ! $l =~ [[:alpha:]] ]] || {
            LOWER=$(lk_lower "$l")
            UPPER=$(lk_upper "$l")
            [ "$LOWER" = "$UPPER" ] || {
                REGEX="${REGEX}[$LOWER$UPPER]"
                continue
            }
        }
        REGEX=$REGEX$l
    done
    echo "$REGEX"
}

# lk_regex_expand_whitespace [-o] [STRING...]
#
# Replace unquoted sequences of one or more whitespace characters in each STRING
# or input with "[[:blank:]]+". If -o is set, make whitespace optional by using
# "[[:blank:]]*" as the replacement string.
#
# Example:
#
#     $ lk_regex_expand_whitespace "message = 'Here\'s a message'"
#     message[[:blank:]]+=[[:blank:]]+'Here\'s a message'
function lk_regex_expand_whitespace() {
    local QUANTIFIER="+"
    [ "${1-}" != -o ] || { QUANTIFIER="*" && shift; }
    lk_replace_whitespace "[[:blank:]]$QUANTIFIER" "$@"
}

# lk_replace_whitespace REPLACE [STRING...]
function lk_replace_whitespace() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME REPLACE [STRING...]" || return
    if [ $# -gt 1 ]; then
        printf '%s\n' "${@:2}" | lk_replace_whitespace "$1"
    else
        awk -v "replace=$1" '
NR == 1 { s_in = $0; next }
        { s_in = s_in RS $0 }
END     {
    # \47 = single quote
    not_special    = "([^\47\"[:blank:]\\\\]|\\\\.)+"
    quoted_single  = "(\47\47|\47([^\47\\\\]|\\\\.)*\47)"
    quoted_double  = "(\"\"|\"([^\"\\\\]|\\\\.)*\")"
    not_whitespace = "^(" not_special "|" quoted_single "|" quoted_double ")*"
    while (length(s_in) && match(s_in, not_whitespace)) {
        l = RLENGTH
        s_out = s_out substr(s_in, 1, l) (l < length(s_in) ? replace : "")
        s_in = substr(s_in, l + 1)
        if (! sub(/[[:blank:]]+/, "", s_in) && l < length(s_in)) {
            print FILENAME ": unmatched \47 or \"" > "/dev/stderr"
            exit 1
        }
    }
    print s_out
}'
    fi
}

# lk_replace FIND REPLACE STRING
#
# Replace all occurrences of FIND in STRING with REPLACE.
function lk_replace() {
    local STRING
    STRING=${3//"$1"/$2}
    echo "$STRING"
}

# lk_in_string NEEDLE HAYSTACK
#
# True if NEEDLE is a substring of HAYSTACK.
function lk_in_string() {
    [ "$(lk_replace "$1" "" "$2.")" != "$2." ]
}

function lk_has_newline() {
    [ "${!1/$'\n'/}" != "${!1}" ]
}

function lk_var_list() {
    eval "printf '%s\n'$(printf ' "${!%s@}"' {a..z} {A..Z} _)"
}

# lk_expand_template [-e] [-q] [FILE]
#
# Replace each {{KEY}} in FILE or input with the value of variable KEY, and each
# {{"KEY"}} with the output of `printf %q "$KEY"`. If -e is set, also replace
# each ({:LIST:}) with the output of `eval LIST`. If -q is set, quote all
# replacement values.
function lk_expand_template() {
    local OPTIND OPTARG OPT EVAL QUOTE TEMPLATE KEYS i REPLACE KEY QUOTED
    unset EVAL QUOTE
    while getopts ":eq" OPT; do
        case "$OPT" in
        e)
            EVAL=1
            ;;
        q)
            QUOTE=1
            ;;
        \? | :)
            lk_usage "\
Usage: $FUNCNAME [-e] [-q] [FILE]"
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    TEMPLATE=$(cat ${1+"$1"} && printf .) || return
    ! lk_is_true EVAL || {
        lk_mapfile KEYS <(
            # Add a newline to guarantee $'...\n'
            printf '%q' "$TEMPLATE"$'\n' |
                grep -Eo '\(\{:([^:]*|:[^}]|:\}[^)])*:\}\)' |
                sort -u
        )
        [ ${#KEYS[@]} -eq 0 ] ||
            for i in $(seq 0 $((${#KEYS[@]} - 1))); do
                eval "KEYS[i]=\$'${KEYS[i]:3:$((${#KEYS[i]} - 6))}'"
                REPLACE=$(eval "${KEYS[i]}" && printf .) ||
                    lk_warn "error evaluating: ${KEYS[i]}" || return
                ! lk_is_true QUOTE ||
                    REPLACE=$(printf '%q.' "${REPLACE%.}")
                REPLACE=${REPLACE%.}
                TEMPLATE=${TEMPLATE//"({:${KEYS[i]}:})"/$REPLACE}
            done
    }
    KEYS=($(echo "$TEMPLATE" |
        grep -Eo '\{\{"?[a-zA-Z_][a-zA-Z0-9_]*"?\}\}' | sort -u |
        sed -E 's/^\{\{"?([a-zA-Z0-9_]+)"?\}\}$/\1/')) || true
    for KEY in ${KEYS[@]+"${KEYS[@]}"}; do
        [ -n "${!KEY+1}" ] ||
            lk_warn "variable not set: $KEY" || return
        REPLACE=${!KEY}
        QUOTED=$(printf '%q.' "$REPLACE")
        QUOTED=${QUOTED%.}
        ! lk_is_true QUOTE ||
            REPLACE=$QUOTED
        TEMPLATE=${TEMPLATE//"{{$KEY}}"/$REPLACE}
        TEMPLATE=${TEMPLATE//"{{\"$KEY\"}}"/$QUOTED}
    done
    TEMPLATE=${TEMPLATE%.}
    echo "${TEMPLATE%$'\n'}"
}

function lk_lower() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_lower
    else
        tr '[:upper:]' '[:lower:]'
    fi
}

function lk_upper() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_upper
    else
        tr '[:lower:]' '[:upper:]'
    fi
}

function lk_upper_first() {
    local EXIT_STATUS
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    printf '%s%s\n' "$(lk_upper "${1:0:1}")" "$(lk_lower "${1:1}")"
}

function lk_trim() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_trim
    else
        sed -E "s/^$S*(.*$NS)?$S*\$/\1/"
    fi
}

function lk_pad_zero() {
    [[ $2 =~ ^0*([0-9]+)$ ]] || lk_warn "not a number: $2" || return
    printf "%0$1d" "${BASH_REMATCH[1]}"
}

# lk_ellipsis LENGTH STRING
function lk_ellipsis() {
    [ "$1" -gt 3 ] &&
        [[ $2 =~ ^(.{$(($1 - 3))}).{4,} ]] &&
        echo "${BASH_REMATCH[1]}..." ||
        echo "$2"
}

# lk_repeat STRING MULTIPLIER
function lk_repeat() {
    [ "$2" -le 0 ] || {
        local STRING=$1
        STRING=${STRING//\\/\\\\}
        STRING=${STRING//%/%%}
        printf -- "$STRING%.s" $(seq 1 "$2")
    }
}

function lk_hostname() {
    hostname -s
}

function lk_fqdn() {
    hostname -f
}

function lk_awk_dir() {
    local DIR=${LK_BASE:+$LK_BASE/lib/awk} FILE
    [ -d "$DIR" ] || {
        FILE=${BASH_SOURCE[1]:-$PWD/}
        DIR=${FILE%/*}
        [ "$DIR" != "$FILE" ] && [ -d "$DIR" ] || DIR=.
    }
    echo "$DIR"
}

function _lk_get_colour() {
    local SEQ
    while [ $# -ge 2 ]; do
        SEQ=$(tput $2) || SEQ=
        printf '%s%s=%q\n' "$PREFIX" "$1" "$SEQ"
        [ "$1" != DIM ] ||
            printf '%s%s=%q\n' "$PREFIX" UNDIM \
                "$([ "$SEQ" != $'\E[2m' ] || echo $'\E[22m')"
        shift 2
    done
}

# lk_get_colours [PREFIX]
function lk_get_colours() {
    local PREFIX
    PREFIX=$(lk_maybe_local)${1-LK_}
    _lk_get_colour \
        BLACK "setaf 0" \
        RED "setaf 1" \
        GREEN "setaf 2" \
        YELLOW "setaf 3" \
        BLUE "setaf 4" \
        MAGENTA "setaf 5" \
        CYAN "setaf 6" \
        WHITE "setaf 7" \
        GREY "setaf 8" \
        BLACK_BG "setab 0" \
        RED_BG "setab 1" \
        GREEN_BG "setab 2" \
        YELLOW_BG "setab 3" \
        BLUE_BG "setab 4" \
        MAGENTA_BG "setab 5" \
        CYAN_BG "setab 6" \
        WHITE_BG "setab 7" \
        GREY_BG "setab 8" \
        BOLD "bold" \
        DIM "dim" \
        UL_ON "smul" \
        UL_OFF "rmul" \
        WRAP_OFF "rmam" \
        WRAP_ON "smam" \
        RESET "sgr0"
}

function lk_maybe_bold() {
    [[ ${1/"$LK_BOLD"/} != "$1" ]] ||
        echo "$LK_BOLD"
}

# _lk_array_fill_temp ARRAY...
#
# Create new array _LK_TEMP_ARRAY and copy the elements of each ARRAY to it.
function _lk_array_fill_temp() {
    local _LK_ARRAY
    _LK_TEMP_ARRAY=()
    while [ $# -gt 0 ]; do
        lk_is_identifier "$1" ||
            lk_warn "not a valid identifier: $1" || return
        _LK_ARRAY="$1[@]"
        _LK_TEMP_ARRAY+=(${!_LK_ARRAY+"${!_LK_ARRAY}"})
        shift
    done
}

# _lk_array_action COMMAND ARRAY...
#
# Run COMMAND with the combined elements of each ARRAY as arguments. COMMAND is
# executed once and any fixed arguments must be quoted.
function _lk_array_action() {
    local _LK_COMMAND _LK_TEMP_ARRAY
    eval "_LK_COMMAND=($1)"
    _lk_array_fill_temp "${@:2}" &&
        "${_LK_COMMAND[@]}" ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}
}

# lk_echo_args [-z] [ARG...]
function lk_echo_args() {
    local DELIM=${LK_Z:+'\0'}
    [ "${1-}" != -z ] || { DELIM='\0' && shift; }
    [ $# -eq 0 ] ||
        printf "%s${DELIM:-\\n}" "$@"
}

# lk_array_merge NEW_ARRAY [ARRAY...]
function lk_array_merge() {
    [ $# -ge 2 ] || return
    eval "$1=($(for i in "${@:2}"; do
        printf '${%s[@]+"${%s[@]}"}\n' "$i" "$i"
    done))"
}

# lk_quote_args [ARG...]
#
# Use `printf %q` to output each ARG on a single space-delimited line.
#
# Example:
#
#     $ lk_quote_args printf '%s\n' "Hello, world."
#     printf %s\\n Hello\,\ world.
function lk_quote_args() {
    [ $# -eq 0 ] || printf '%q' "$1"
    [ $# -le 1 ] || printf ' %q' "${@:2}"
    printf '\n'
}

# lk_quote_args_folded [ARG...]
#
# Same as lk_quote_args, but start each ARG on a new line.
#
# Example:
#
#     $ lk_quote_args_folded printf '%s\n' "Hello, world."
#     printf \
#         %s\\n \
#         Hello\,\ world.
function lk_quote_args_folded() {
    [ $# -eq 0 ] || printf '%q' "$1"
    [ $# -le 1 ] || printf ' \\\n    %q' "${@:2}"
    printf '\n'
}

# lk_quote [ARRAY...]
function lk_quote() {
    _lk_array_action lk_quote_args "$@"
}

# lk_in_array VALUE ARRAY [ARRAY...]
#
# Return true if VALUE exists in any ARRAY, otherwise return false.
function lk_in_array() {
    local _LK_ARRAY _LK_VAL
    for _LK_ARRAY in "${@:2}"; do
        _LK_ARRAY="${_LK_ARRAY}[@]"
        for _LK_VAL in ${!_LK_ARRAY+"${!_LK_ARRAY}"}; do
            [ "$_LK_VAL" = "$1" ] || continue
            return 0
        done
    done
    false
}

# lk_array_search PATTERN ARRAY
#
# Search ARRAY for PATTERN and output the key of the first match if found,
# otherwise return false.
function lk_array_search() {
    local _LK_KEYS _LK_VALS _lk_i
    eval "_LK_KEYS=(\"\${!$2[@]}\")"
    eval "_LK_VALS=(\"\${$2[@]}\")"
    for _lk_i in "${!_LK_VALS[@]}"; do
        # shellcheck disable=SC2053
        [[ ${_LK_VALS[$_lk_i]} == $1 ]] || continue
        echo "${_LK_KEYS[$_lk_i]}"
        return 0
    done
    false
}

# lk_xargs [-z] COMMAND [ARG...]
#
# Invoke the given command line for each LINE of input, passing LINE as the
# final argument. If -z is set, use NUL instead of newline as the input
# delimiter.
function lk_xargs() {
    local LK_Z=${LK_Z-} _LK_NUL_READ=(-d '') _LK_LINE _LK_STATUS=0
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
    while IFS= read -r ${LK_Z:+"${_LK_NUL_READ[@]}"} _LK_LINE ||
        [ -n "$_LK_LINE" ]; do
        "$@" "$_LK_LINE" || _LK_STATUS=$?
    done
    return "$_LK_STATUS"
}

# _lk_maybe_xargs FIXED_ARGS [ARG...]
#
# For functions that take FIXED_ARGS followed by one value argument, add support
# for passing multiple values in subsequent arguments or on standard input via
# newline- or NUL-delimited lines.
#
# After accounting for FIXED_ARGS, the number of arguments remaining determines
# next steps.
# 1. one argument: return false immediately, signalling the caller to process
#    the value passed
# 2. zero arguments: use lk_xargs to invoke the caller with each line of input,
#    then set EXIT_STATUS to the return value and return true
# 3. two or more arguments: invoke the caller with each argument, then set
#    EXIT_STATUS to the return value and return true
#
# If there are no value arguments and the caller is invoked with -z as the first
# argument, use NUL instead of newline as the input delimiter.
#
# Example:
#
#     function my_function() {
#         local EXIT_STATUS
#         ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
#         # process $1
#     }
function _lk_maybe_xargs() {
    local LK_Z=${LK_Z-} COMMAND
    # Check for -z and no value arguments, i.e. NUL-delimited input
    [ "${2-}" != -z ] || (($# - $1 - 2)) ||
        { LK_Z=1 && set -- "$1" "${@:3}"; }
    # Return false ASAP if there's exactly one value for the caller to process
    (($# - $1 - 2)) || return
    COMMAND=("${FUNCNAME[1]}" "${@:2:$1}")
    EXIT_STATUS=0
    # If there are no values to process, use lk_xargs to pass input lines
    if ! (($# - $1 - 1)); then
        lk_xargs "${COMMAND[@]}" || EXIT_STATUS=$?
    else
        # Otherwise pass each value
        for i in "${@:$(($1 + 2))}"; do
            "${COMMAND[@]}" "$i" || {
                EXIT_STATUS=$?
                return 0
            }
        done
    fi
}

function lk_has_arg() {
    lk_in_array "$1" _LK_ARGV
}

function _lk_cache_dir() {
    echo "${_LK_OUTPUT_CACHE:=$(
        TMPDIR=${TMPDIR:-/tmp}
        DIR=${TMPDIR%/}/_lk_output_cache_$EUID
        install -d -m 00700 "$DIR" && echo "$DIR"
    )}"
} #### Reviewed: 2021-03-25

# lk_cache [-t TTL] COMMAND [ARG...]
#
# Print output from a previous run if possible, otherwise execute the command
# line and cache its output in a transient per-process cache. If -t is set, use
# cached output for up to TTL seconds (default: 300). If TTL is 0, use cached
# output indefinitely.
function lk_cache() {
    local TTL=300 FILE AGE s=/
    [ "${1-}" != -t ] || { TTL=$2 && shift 2; }
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__} &&
        { [ ! -f "${FILE}_dirty" ] || rm -f -- "$FILE"*; } || return
    FILE+=_${FUNCNAME[1]}_$(lk_hash "$@") || return
    if [ -f "$FILE" ] &&
        { [ "$TTL" -eq 0 ] ||
            { AGE=$(lk_file_age "$FILE") &&
                [ "$AGE" -lt "$TTL" ]; }; }; then
        cat "$FILE"
    else
        "$@" >"$FILE" && cat -- "$FILE" || lk_pass rm -f -- "$FILE"
    fi
} #### Reviewed: 2021-03-25

function lk_cache_mark_dirty() {
    local FILE s=/
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__}_dirty || return
    touch "$FILE"
} #### Reviewed: 2021-03-25

# lk_get_outputs_of COMMAND [ARG...]
#
# Execute COMMAND, output Bash-compatible code that sets _STDOUT and _STDERR to
# COMMAND's respective outputs, and exit with COMMAND's exit status.
function lk_get_outputs_of() {
    local SH EXIT_STATUS
    SH=$(
        _LK_CAN_FAIL=1
        _LK_STDOUT=$(lk_mktemp_file) &&
            _LK_STDERR=$(lk_mktemp_file) &&
            lk_delete_on_exit "$_LK_STDOUT" "$_LK_STDERR" || exit
        unset _LK_FD
        "$@" >"$_LK_STDOUT" 2>"$_LK_STDERR" || EXIT_STATUS=$?
        for i in _LK_STDOUT _LK_STDERR; do
            lk_maybe_local
            printf '%s=%q\n' "${i#_LK}" "$(cat "${!i}" |
                lk_strip_non_printing)"
        done
        exit "${EXIT_STATUS:-0}"
    ) || EXIT_STATUS=$?
    echo "$SH"
    return "${EXIT_STATUS:-0}"
}

function _lk_lock_check_args() {
    lk_is_linux || lk_command_exists flock || {
        [ "${FUNCNAME[1]-}" = lk_lock_drop ] ||
            lk_console_warning "File locking is not supported on this platform"
        return 2
    }
    case $# in
    0 | 1)
        set -- LOCK_FILE LOCK_FD "${1-}"
        ;;
    2 | 3)
        set -- "$1" "$2" "${3-}"
        lk_test_many lk_is_identifier "${@:1:2}"
        ;;
    *)
        false
        ;;
    esac || lk_warn "invalid arguments" || return 1
    printf 'set -- %s\n' "$(lk_quote_args "$@")"
} #### Reviewed: 2021-05-23

# lk_lock [-f LOCK_FILE] [-w] [LOCK_FILE_VAR LOCK_FD_VAR] [LOCK_NAME]
function lk_lock() {
    local _LK_FILE _LK_NONBLOCK=1 _LK_SH
    [ "${1-}" != -f ] || { _LK_FILE=${2-} && shift 2 || return; }
    [ "${1-}" != -w ] || { unset _LK_NONBLOCK && shift || return; }
    _LK_SH=$(_lk_lock_check_args "$@") ||
        { [ $? -eq 2 ] && return 0; } || return
    eval "$_LK_SH" || return
    unset "${@:1:2}"
    eval "$1=\${_LK_FILE:-/tmp/\${3:-.\${LK_PATH_PREFIX:-lk-}\$(lk_caller_name)}.lock}" &&
        eval "$2=\$(lk_fd_next)" &&
        eval "exec ${!2}>\"\$$1\"" || return
    flock ${_LK_NONBLOCK+-n} "${!2}" ||
        lk_warn "unable to acquire lock: ${!1}" || return
    lk_trap_add EXIT lk_lock_drop "$@"
} #### Reviewed: 2021-05-23

# lk_lock_drop [LOCK_FILE_VAR LOCK_FD_VAR] [LOCK_NAME]
function lk_lock_drop() {
    local _LK_SH
    _LK_SH=$(_lk_lock_check_args "$@") ||
        { [ $? -eq 2 ] && return 0; } || return
    eval "$_LK_SH" || return
    if [ "${!1:+1}${!2:+1}" = 11 ]; then
        eval "exec ${!2}>&-" || lk_warn "unable to drop lock: ${!1}" || return
        rm -f -- "${!1}" 2>/dev/null || true
    fi
    unset "${@:1:2}"
} #### Reviewed: 2021-05-23

function lk_pv() {
    lk_ignore_SIGINT && lk_log_bypass_stderr pv "$@"
}

function _lk_tee() {
    local PRESERVE
    [[ ! "$1" =~ ^-[0-9]+$ ]] || { PRESERVE=${1#-} && shift; }
    lk_ignore_SIGINT && eval exec "$(_lk_log_close_fd ${PRESERVE-})" || return
    exec tee "$@"
}

# lk_log [PREFIX]
#
# Add PREFIX and a microsecond-resolution timestamp to the beginning of each
# line of input.
#
# Example:
#
#     $ echo "Hello, world." | lk_log '!!'
#     !!2021-05-13 18:01:53.860513 +1000 Hello, world.
function lk_log() {
    local PREFIX=${1-}
    lk_ignore_SIGINT && eval exec "$(_lk_log_close_fd)" || return
    PREFIX=${PREFIX//"%"/"%%"} exec perl -pe '$| = 1;
BEGIN {
    use POSIX qw{strftime};
    use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "$ENV{PREFIX}%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );
s/.*\r(.)/\1/;'
} #### Reviewed: 2021-05-13

# lk_log_create_file [-e EXT] [DIR...]
function lk_log_create_file() {
    local OWNER=$UID GROUP EXT CMD LOG_DIRS=() LOG_DIR LOG_PATH
    GROUP=$(id -gn) || return
    [ "${1-}" != -e ] || { EXT=$2 && shift 2; }
    CMD=${_LK_LOG_CMDLINE:-$0}
    [ ! -d "${_LK_INST:-${LK_BASE-}}" ] ||
        [ -z "$(ls -A "${_LK_INST:-$LK_BASE}")" ] ||
        LOG_DIRS=("${_LK_INST:-$LK_BASE}/var/log")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS[@]+"${LOG_DIRS[@]}"}; do
        # Find the first LOG_DIR in which the user can write to LOG_FILE,
        # installing LOG_DIR (world-writable) and LOG_FILE (owner-only) if
        # needed, running commands via sudo only if they fail without it
        [ -d "$LOG_DIR" ] || lk_elevate_if_error \
            lk_install -d -m 01777 "$LOG_DIR" 2>/dev/null || continue
        LOG_PATH=$LOG_DIR/${_LK_LOG_BASENAME:-${CMD##*/}}-$UID.${EXT:-log}
        if [ -f "$LOG_PATH" ]; then
            [ -w "$LOG_PATH" ] || {
                lk_elevate_if_error chmod 00600 "$LOG_PATH" || continue
                [ -w "$LOG_PATH" ] ||
                    lk_elevate chown "$OWNER:$GROUP" "$LOG_PATH" || continue
            }
        else
            lk_elevate_if_error \
                lk_install -m 00600 -o "$OWNER" -g "$GROUP" "$LOG_PATH" ||
                continue
        fi 2>/dev/null
        echo "$LOG_PATH"
        return 0
    done
    false
}

function lk_start_trace() {
    # Don't interfere with an existing trace
    [[ $- != *x* ]] && lk_is_true LK_DEBUG || return 0
    local TRACE_PATH
    TRACE_PATH=${_LK_LOG_TRACE_PATH:-$(lk_log_create_file \
        -e "$(lk_date_ymdhms).trace" /tmp ~)} &&
        exec 4> >(lk_log >"$TRACE_PATH") || return
    if lk_bash_at_least 4 1; then
        BASH_XTRACEFD=4
    else
        # If BASH_XTRACEFD isn't supported, trace all output to stderr and send
        # lk_tty_* to the terminal
        exec 2>&4 &&
            { ! lk_log_is_open || _LK_TRACE_FD=4; } &&
            { [ "${_LK_FD-2}" -ne 2 ] ||
                { exec 3>/dev/tty && export _LK_FD=3; }; }
    fi || lk_warn "unable to open trace file" || return
    set -x
}

function _lk_log_close_fd() {
    local IFS i j=0 SH=()
    unset IFS
    for i in _LK_FD _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD _LK_LOG2_FD; do
        [ -z "${!i-}" ] || [ "${!i}" -lt 3 ] || [ "${!i}" -eq "${1:-0}" ] ||
            SH[j++]="${!i}>&-"
    done
    ((j)) || return 0
    echo "${SH[*]}"
}

# lk_log_start [TEMP_LOG_FILE]
function lk_log_start() {
    local ARG0 HEADER EXT _FILE FILE LOG_FILE OUT_FILE FIFO
    if [ "${LK_NO_LOG-}" = 1 ] || lk_log_is_open ||
        { [[ $- == *i* ]] && ! lk_script_running; }; then
        return
    fi
    ARG0=$(type -p "${_LK_LOG_CMDLINE:-$0}") &&
        ARG0=${ARG0:-${_LK_LOG_CMDLINE+"Bash $(type -t \
            "$_LK_LOG_CMDLINE") $_LK_LOG_CMDLINE"}} || ARG0=
    [ -n "${_LK_LOG_CMDLINE+1}" ] ||
        local _LK_LOG_CMDLINE=("$0" ${_LK_ARGV+"${_LK_ARGV[@]}"})
    _LK_LOG_CMDLINE[0]=${ARG0:-$_LK_LOG_CMDLINE}
    HEADER=$(
        printf '====> %s invoked' "$LK_BOLD$ARG0$LK_RESET"
        ! ((ARGC = ${#_LK_LOG_CMDLINE[@]} - 1)) || {
            printf ' with %s %s:' "$ARGC" \
                "$(lk_plural "$ARGC" argument arguments)"
            for ((i = 1; i <= ARGC; i++)); do
                printf '\n%s%3d%s %q' \
                    "$LK_BOLD" "$i" "$LK_RESET" "${_LK_LOG_CMDLINE[i]}"
            done
        }
    )
    if [[ ${1-} =~ (.+)(\.(log|out))?$ ]]; then
        set -- "${BASH_REMATCH[1]}"
    else
        set --
    fi
    for EXT in log out; do
        if [ -n "${_LK_LOG_FILE-}" ]; then
            if [ "$EXT" = log ]; then
                FILE=$_LK_LOG_FILE
                _lk_log_install_file "$FILE" || return
            else
                FILE=/dev/null
            fi
        elif [ $# -gt 0 ]; then
            _FILE=$1.$EXT
            if FILE=$(lk_log_create_file -e "$EXT"); then
                [ ! -e "$_FILE" ] ||
                    { lk_file_backup -m "$_FILE" "$FILE" &&
                        cat -- "$_FILE" >>"$FILE" &&
                        rm -f -- "$_FILE"; } || return
            else
                FILE=$_FILE
            fi
        else
            FILE=$(lk_log_create_file -e "$EXT" ~ /tmp) ||
                lk_warn "unable to create log file" || return
        fi
        eval "$(lk_upper "$EXT")_FILE=\$FILE"
    done
    FIFO=$(lk_mktemp_dir)/fifo &&
        lk_delete_on_exit "${FIFO%/*}" &&
        mkfifo "$FIFO" || return
    (lk_ignore_SIGINT &&
        LK_EXEC=1 lk_strip_non_printing <"$FIFO" >>"$OUT_FILE") &
    unset _LK_LOG2_FD
    [ -z "${_LK_SECONDARY_LOG_FILE-}" ] || { _LK_LOG2_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG2_FD"'>>"$_LK_SECONDARY_LOG_FILE"' &&
        export _LK_LOG2_FD; } || return
    _LK_TTY_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_OUT_FD>&1" &&
        _LK_TTY_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_ERR_FD>&2" &&
        _LK_LOG_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG_OUT_FD"'> >(lk_log ".." >"$FIFO")' &&
        _LK_LOG_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG_ERR_FD"'> >(lk_log "!!" >"$FIFO")' &&
        _LK_LOG_FD=$(lk_fd_next) && { if [ -z "${_LK_LOG2_FD-}" ]; then
            eval "exec $_LK_LOG_FD"'> >(lk_log >>"$LOG_FILE")'
        else
            eval "exec $_LK_LOG_FD"'> >(lk_log > >(_lk_tee -a "$LOG_FILE" >&"$_LK_LOG2_FD"))'
        fi; } || return
    export _LK_FD _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD
    [ "${_LK_FD-2}" -ne 2 ] || {
        _LK_FD=3
        _LK_FD_LOGGED=1
    }
    lk_log_tty_on
    tee "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD" <<<"$HEADER"
    ! lk_verbose 2 || lk_echoc \
        "Output is being logged to $LK_BOLD$LOG_FILE$LK_RESET" "$LK_GREY" |
        lk_log_to_tty_stdout
    _LK_LOG_FILE_LOG=$LOG_FILE
    _LK_LOG_FILE_OUT=$OUT_FILE
}

function lk_log_is_open() {
    local FD
    for FD in _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD; do
        lk_fd_is_open "${!FD-}" || return
    done
}

# lk_log_close [-r]
#
# Close redirections opened by lk_log_start. If -r is set, reopen them for
# further logging (useful when closing a secondary log file).
function lk_log_close() {
    lk_log_is_open || lk_warn "no output log" || return
    if [ "${1-}" = -r ]; then
        [ -z "${_LK_LOG2_FD-}" ] || {
            eval "exec $_LK_LOG_FD"'> >(lk_log >>"$_LK_LOG_FILE_LOG")' &&
                { ! lk_fd_is_open "$_LK_LOG2_FD" ||
                    eval "exec $_LK_LOG2_FD>&-"; }
        } || return
        unset _LK_LOG2_FD
    else
        CLOSE=()
        [ -z "${_LK_FD_LOGGED-}" ] || CLOSE=(_LK_FD)
        CLOSE+=(
            _LK_LOG_FD
            _LK_LOG_ERR_FD
            _LK_LOG_OUT_FD
            _LK_TTY_ERR_FD
            _LK_TTY_OUT_FD
            _LK_LOG2_FD
        )
        exec >&"$_LK_TTY_OUT_FD" 2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}" &&
            eval "$(for i in "${CLOSE[@]}"; do
                [ -z "${!i-}" ] || printf 'exec %s>&-\n' "${!i-}"
            done)" &&
            unset "${CLOSE[@]}" _LK_{LOG,OUT}_FILE
    fi
}

# lk_log_tty_off -a
function lk_log_tty_off() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
        2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") &&
        { [ "${1-}" != -a ] || [ -z "${_LK_FD_LOGGED-}" ] ||
            eval "exec $_LK_FD"'> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")'; } &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_tty_stdout_off() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
        2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_tty_on() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD") \
        2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") &&
        { [ -z "${_LK_FD_LOGGED-}" ] ||
            eval "exec $_LK_FD"'> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD")'; } &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_to_file_stdout() {
    lk_log_is_open || lk_warn "no output log" || return
    cat > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")
}

function lk_log_to_file_stderr() {
    lk_log_is_open || lk_warn "no output log" || return
    cat > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
}

function lk_log_to_tty_stdout() {
    if lk_log_is_open; then
        cat >&"$_LK_TTY_OUT_FD"
    else
        cat
    fi
}

function lk_log_to_tty_stderr() {
    if lk_log_is_open; then
        cat >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
    else
        cat >&2
    fi
}

function _lk_log_bypass() {
    (
        unset "${!_LK_LOG_@}"
        "$@"
    )
}

# lk_log_bypass [-o|-e|-t|-to|-te|-n] COMMAND [ARG...]
#
# Run the given command with stdout and stderr redirected to the console,
# bypassing output log files. If -o or -e is set, only redirect stdout or stderr
# respectively. If -t is set, run the command with stdout and stderr redirected
# to output log files, bypassing the console. If -to or -te are set, only
# redirect stdout or stderr to output logs. If -n is set, run COMMAND with the
# same redirections lk_log_tty_on would apply.
function lk_log_bypass() {
    local ARG=${1-} _LK_CAN_FAIL=1
    [[ ! $ARG =~ ^-(t?[oe]|n)$ ]] || shift
    lk_log_is_open || {
        "$@"
        return
    }
    case "$ARG" in
    -to)
        _lk_log_bypass "$@" \
            > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")
        ;;
    -te)
        _lk_log_bypass "$@" \
            2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
        ;;
    -t)
        _lk_log_bypass "$@" \
            > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
            2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
        ;;
    -o)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD"
        ;;
    -e)
        _lk_log_bypass "$@" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    -n)
        _lk_log_bypass "$@" \
            > >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD") \
            2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}")
        ;;
    *)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    esac
}

function lk_log_bypass_stdout() {
    lk_log_bypass -o "$@"
}

function lk_log_bypass_stderr() {
    lk_log_bypass -e "$@"
}

function lk_log_bypass_tty() {
    lk_log_bypass -t "$@"
}

function lk_log_bypass_tty_stdout() {
    lk_log_bypass -to "$@"
}

function lk_log_bypass_tty_stderr() {
    lk_log_bypass -te "$@"
}

function lk_log_no_bypass() {
    lk_log_bypass -n "$@"
}

# lk_echoc [-n] [MESSAGE [COLOUR]]
function lk_echoc() {
    local NEWLINE MESSAGE
    [ "${1-}" != -n ] || { NEWLINE=0 && shift; }
    MESSAGE=${1-}
    [ $# -le 1 ] || [ -z "$LK_RESET" ] ||
        MESSAGE=$2${MESSAGE//"$LK_RESET"/$LK_RESET$2}$LK_RESET
    echo ${NEWLINE:+-n} "$MESSAGE"
}

function lk_readline_format() {
    local STRING=$1 REGEX
    eval "$(lk_get_regex CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX)"
    for REGEX in CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX; do
        while [[ $STRING =~ ((.*)(^|[^$'\x01']))(${!REGEX})+(.*) ]]; do
            STRING=${BASH_REMATCH[1]}$'\x01'${BASH_REMATCH[4]}$'\x02'${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
        done
    done
    echo "$STRING"
}

function lk_diff() { (
    _LK_CAN_FAIL=1
    [ $# -eq 2 ] || lk_usage "Usage: $FUNCNAME FILE1 FILE2" || exit
    for i in 1 2; do
        if [ -p "${!i}" ] || [ -n "${_LK_DIFF_SED_SCRIPT:+1}" ]; then
            FILE=$(lk_mktemp_file) && lk_delete_on_exit "$FILE" &&
                lk_maybe_sudo sed -E \
                    "${_LK_DIFF_SED_SCRIPT-}" \
                    "${!i}" >"$FILE" || exit
            set -- "${@:1:i-1}" "$FILE" "${@:i+1}"
        fi
    done
    # Use the same escape sequences as icdiff, which ignores TERM
    BLUE=$'\E[34m'
    GREEN=$'\E[1;32m'
    RESET=$'\E[m'
    if lk_command_exists icdiff; then
        # Don't use icdiff if FILE1 is empty
        if lk_maybe_sudo test ! -s "$1" -a -s "$2"; then
            echo "$BLUE$2$RESET"
            printf '%s' "$GREEN"
            # Add $RESET to the last line
            lk_maybe_sudo cat "$2" | awk -v "r=$RESET" \
                's { print l } { s = 1; l = $0 } END { print l r }'
            false
        else
            printf '%s' "$LK_RESET"
            ! lk_require_output lk_maybe_sudo icdiff -U2 --no-headers \
                ${_LK_TTY_INDENT:+--cols=$(($(
                    lk_tty_columns
                ) - 2 * (_LK_TTY_INDENT + 2)))} "$@"
        fi
    elif lk_command_exists git; then
        lk_maybe_sudo \
            git diff --no-index --no-prefix --no-ext-diff --color -U3 "$@"
    else
        DIFF_VER=$(lk_diff_version 2>/dev/null) &&
            lk_version_at_least "$DIFF_VER" 3.4 || unset DIFF_VER
        lk_maybe_sudo gnu_diff ${DIFF_VER+--color=always} -U3 "$@"
    fi && echo "${BLUE}Files are identical${_LK_DIFF_SED_SCRIPT:+ or have hidden differences}$RESET"
); }

function lk_maybe_trace() {
    local OUTPUT COMMAND
    [ "${1-}" != -o ] || { OUTPUT=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no command" || return
    COMMAND=("$@")
    [[ $- != *x* ]] ||
        COMMAND=(env
            ${BASH_XTRACEFD:+BASH_XTRACEFD=$BASH_XTRACEFD}
            SHELLOPTS=xtrace
            "$@")
    ! lk_will_sudo || {
        # See: https://bugzilla.sudo.ws/show_bug.cgi?id=950
        local SUDO_MIN=3 VER
        ! VER=$(sudo -V | awk 'NR == 1 { print $NF }') ||
            printf '%s\n' "$VER" 1.8.9 1.8.32 1.9.0 1.9.4p1 | sort -V |
            awk -v "v=$VER" '$0 == v { l = NR } END { exit 1 - l % 2 }' ||
            SUDO_MIN=4
        COMMAND=(
            sudo -H
            -C "$(($(set +u && printf '%s\n' $((SUDO_MIN - 1)) \
                $((_LK_FD ? _LK_FD : 2)) $((BASH_XTRACEFD)) $((_LK_TRACE_FD)) \
                $((_LK_TTY_OUT_FD)) $((_LK_TTY_ERR_FD)) \
                $((_LK_LOG_OUT_FD)) $((_LK_LOG_ERR_FD)) \
                $((_LK_LOG_FD)) $((_LK_LOG2_FD)) | sort -n | tail -n1) + 1))"
            "${COMMAND[@]}"
        )
    }
    # Remove "env" from sudo command
    [[ $- != *x* ]] || ! lk_will_sudo || unset "COMMAND[4]"
    ! lk_is_true OUTPUT ||
        COMMAND=(lk_quote_args "${COMMAND[@]}")
    "${COMMAND[@]}"
}

# lk_clip
#
# Copy input to the user's clipboard if possible, otherwise print it out.
function lk_clip() {
    local OUTPUT COMMAND LINES MESSAGE DISPLAY_LINES=${LK_CLIP_LINES:-5}
    [ ! -t 0 ] || lk_warn "no input" || return
    OUTPUT=$(cat && printf .) && OUTPUT=${OUTPUT%.}
    if COMMAND=$(lk_command_first_existing \
        "xclip -selection clipboard" \
        pbcopy) &&
        echo -n "$OUTPUT" | $COMMAND &>/dev/null; then
        LINES=$(wc -l <<<"$OUTPUT" | tr -d ' ')
        [ "$LINES" -le "$DISPLAY_LINES" ] || {
            OUTPUT=$(head -n$((DISPLAY_LINES - 1)) <<<"$OUTPUT" &&
                echo "$LK_BOLD$LK_MAGENTA...$LK_RESET")
            MESSAGE="$LINES lines copied"
        }
        lk_console_item "${MESSAGE:-Copied} to clipboard:" \
            $'\n'"$LK_GREEN$OUTPUT$LK_RESET" "$LK_MAGENTA"
    else
        lk_console_error "Unable to copy input to clipboard"
        echo -n "$OUTPUT"
    fi
}

# lk_paste
#
# Paste the user's clipboard to output, if possible.
function lk_paste() {
    local COMMAND
    COMMAND=$(lk_command_first_existing \
        "xclip -selection clipboard -out" \
        pbpaste) &&
        $COMMAND ||
        lk_console_error "Unable to paste clipboard to output"
}

# lk_file_add_suffix FILENAME SUFFIX
#
# Add SUFFIX to FILENAME without changing its extension.
function lk_file_add_suffix() {
    local EXT
    [[ $1 =~ [^/]((\.tar)?\.[-a-zA-Z0-9_]+/*|/*)$ ]] &&
        EXT=${BASH_REMATCH[1]} ||
        EXT=
    echo "${1%$EXT}$2$EXT"
}

# lk_file_maybe_add_extension FILENAME EXT
#
# Add EXT to FILENAME if it's missing.
function lk_file_maybe_add_extension() {
    (
        shopt -s nocasematch
        [[ $1 == *.${2#.} ]] && echo "$1" || echo "$1.${2#.}"
    )
}

function lk_mime_type() {
    [ -e "$1" ] || lk_warn "file not found: $1" || return
    file --brief --mime-type "$1"
}

function lk_is_pdf() {
    local MIME_TYPE
    MIME_TYPE=$(lk_mime_type "$1") &&
        [ "$MIME_TYPE" = application/pdf ]
}

# lk_uri_parts URI [COMPONENT...]
#
# Output Bash-compatible variable assignments for all components in URI or for
# each COMPONENT.
#
# COMPONENT can be one of: _SCHEME, _USERNAME, _PASSWORD, _HOST, _PORT, _PATH,
# _QUERY, _FRAGMENT, _IPV6_ADDRESS
function lk_uri_parts() {
    local PARTS=("${@:2}") PART VALUE
    eval "$(lk_get_regex URI_REGEX)"
    [[ $1 =~ ^$URI_REGEX$ ]] || return
    [ ${#PARTS[@]} -gt 0 ] || PARTS=(
        _SCHEME _USERNAME _PASSWORD _HOST _PORT _PATH _QUERY _FRAGMENT
        _IPV6_ADDRESS
    )
    for PART in "${PARTS[@]}"; do
        case "$PART" in
        _SCHEME)
            VALUE=${BASH_REMATCH[2]}
            ;;
        _USERNAME)
            VALUE=${BASH_REMATCH[5]}
            ;;
        _PASSWORD)
            VALUE=${BASH_REMATCH[7]}
            ;;
        _HOST)
            VALUE=${BASH_REMATCH[8]}
            ;;
        _IPV6_ADDRESS)
            VALUE=${BASH_REMATCH[9]}
            ;;
        _PORT)
            VALUE=${BASH_REMATCH[11]}
            ;;
        _PATH)
            VALUE=${BASH_REMATCH[12]}
            ;;
        _QUERY)
            VALUE=${BASH_REMATCH[14]}
            ;;
        _FRAGMENT)
            VALUE=${BASH_REMATCH[16]}
            ;;
        *)
            lk_warn "unknown URI component: $PART"
            return 1
            ;;
        esac
        lk_maybe_local
        printf '%s=%q\n' "$PART" "$VALUE"
    done
}

# lk_get_uris [FILE...]
#
# Match and output URIs ("scheme://host" at minimum) in each FILE or input.
function lk_get_uris() {
    local REGEX_QUOTED REGEX EXIT_STATUS=0
    eval "$(lk_get_regex URI_REGEX_REQ_SCHEME_HOST)"
    REGEX_QUOTED="'($(sed -E "s/(\\[[^]']*)'([^]']*\\])/(\1\2|(\\\\\\\\'))/g" \
        <<<"$URI_REGEX_REQ_SCHEME_HOST"))'"
    REGEX="([^a-zA-Z']|^)($URI_REGEX_REQ_SCHEME_HOST)([^']|\$)"
    grep -Eo "($REGEX|$REGEX_QUOTED)" "$@" |
        sed -E \
            -e "s/^${REGEX//\//\\\/}/\2/" \
            -e "s/^${REGEX_QUOTED//\//\\\/}/\1/" || EXIT_STATUS=$?
    # `grep` returns 1 if there are no matches
    [ "$EXIT_STATUS" -eq 0 ] || [ "$EXIT_STATUS" -eq 1 ]
}

# lk_wget_uris URL
#
# Match and output URIs ("scheme://host" at minimum) in the file downloaded from
# URL. URIs are converted during download using `wget --convert-links`.
function lk_wget_uris() {
    local TEMP_FILE
    # --convert-links is disabled if wget uses standard output
    TEMP_FILE=$(lk_mktemp_file) &&
        lk_delete_on_exit "$TEMP_FILE" &&
        wget --quiet --convert-links --output-document "$TEMP_FILE" "$1" ||
        return
    lk_get_uris "$TEMP_FILE"
    rm -f -- "$TEMP_FILE"
}

function lk_curl_version() {
    curl --version | awk 'NR == 1 { print $2 }' ||
        lk_warn "unable to determine curl version" || return
}

function lk_diff_version() {
    gnu_diff --version | awk 'NR == 1 { print $NF }' ||
        lk_warn "unable to determine diff version" || return
}

# lk_download [-s] [URI[|FILENAME]...]
#
# Download each URI to the current directory unless an up-to-date version is
# already present. If no URI arguments are given, read them from input.
#
# By default, the file name for each URI is taken from its path, and an error is
# returned if a URI has an empty or unsuitable path. To override this behaviour,
# specify the file name for a URI by adding the "|FILENAME" suffix, or set -s to
# use the file name specified by the server.
#
# IMPORTANT: if -s is set, files in the current directory with the same name as
# a server-specified file name will be overwritten, and even if they are
# up-to-date, files previously downloaded will be re-downloaded.
function lk_download() {
    local SERVER_NAMES CURL_VERSION CURL_COMMAND DOWNLOAD_DIR URI FILENAME \
        SH DOWNLOAD_ONE DOWNLOAD_ARGS \
        FILENAMES=() COMMANDS=() COMMAND_ARGS=() COMMAND
    [ "${1-}" != -s ] || { SERVER_NAMES=1 && shift; }
    CURL_VERSION=$(lk_curl_version) || return
    CURL_COMMAND=(
        curl
        --fail
        --location
        --remote-time
    )
    ! lk_is_true SERVER_NAMES || {
        lk_version_at_least "$CURL_VERSION" 7.26.0 ||
            lk_warn "curl too old to output filename_effective" || return
        DOWNLOAD_DIR=$(lk_mktemp_dir) &&
            lk_delete_on_exit "$DOWNLOAD_DIR" &&
            pushd "$DOWNLOAD_DIR" >/dev/null || return
        CURL_COMMAND+=(
            --remote-name
            --remote-header-name
            --write-out '%{filename_effective}\n'
        )
    }
    while IFS='|' read -r URI FILENAME; do
        [ -n "$URI" ] || continue
        lk_is_uri "$URI" || lk_warn "not a URI: $URI" || return
        unset DOWNLOAD_ONE
        DOWNLOAD_ARGS=()
        lk_is_true SERVER_NAMES || {
            [ -n "$FILENAME" ] || {
                SH=$(lk_uri_parts "$URI" _PATH) &&
                    eval "$SH"
                FILENAME=${_PATH##*/}
            }
            [ -n "$FILENAME" ] ||
                lk_warn "no filename in URI: $URI" || return
            [ ! -f "$FILENAME" ] || {
                # --time-cond can only be set once per invocation of curl, so
                # queue separate commands for any files downloaded previously
                DOWNLOAD_ONE=1
                DOWNLOAD_ARGS+=(--time-cond "$(lk_timestamp_readable \
                    "$(lk_file_modified "$FILENAME")")")
            }
            DOWNLOAD_ARGS+=(--output "$FILENAME")
            FILENAMES+=("$FILENAME")
        }
        DOWNLOAD_ARGS+=("$URI")
        lk_is_true DOWNLOAD_ONE || {
            COMMAND_ARGS+=("${DOWNLOAD_ARGS[@]}")
            continue
        }
        COMMANDS+=("$(lk_quote CURL_COMMAND DOWNLOAD_ARGS)")
    done < <([ $# -gt 0 ] &&
        lk_echo_args "$@" ||
        cat)
    [ ${#COMMAND_ARGS[@]} -eq 0 ] || {
        CURL_COMMAND=("${CURL_COMMAND[@]//--remote-name/--remote-name-all}")
        ! lk_version_at_least "$CURL_VERSION" 7.66.0 ||
            CURL_COMMAND+=(--parallel)
        ! lk_version_at_least "$CURL_VERSION" 7.68.0 ||
            CURL_COMMAND+=(--parallel-immediate)
        COMMANDS+=("$(lk_quote CURL_COMMAND COMMAND_ARGS)")
    }
    for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
        eval "$COMMAND" || return
    done
    lk_is_true SERVER_NAMES || {
        lk_echo_array FILENAMES
        return
    }
    popd >/dev/null && (
        shopt -s dotglob &&
            mv -f "$DOWNLOAD_DIR"/* "$PWD" &&
            rmdir "$DOWNLOAD_DIR"
    ) || return
}

function lk_curl() {
    local CURL_OPTIONS=(${LK_CURL_OPTIONS[@]+"${LK_CURL_OPTIONS[@]}"})
    [ ${#CURL_OPTIONS[@]} -gt 0 ] || CURL_OPTIONS=(
        --fail
        --header "Cache-Control: no-cache"
        --header "Pragma: no-cache"
        --location
        --retry 2
        --show-error
        --silent
    )
    curl ${CURL_OPTIONS[@]+"${CURL_OPTIONS[@]}"} "$@"
}

# lk_run_as USER COMMAND [ARG...]
function lk_run_as() {
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    if lk_is_linux; then
        lk_elevate runuser -u "$1" -- "${@:2}"
    else
        sudo -u "$1" -- "${@:2}"
    fi
}

function lk_maybe_drop() {
    if ! lk_root; then
        "$@"
    elif lk_is_linux; then
        runuser -u nobody -- "$@"
    else
        sudo -u nobody -- "$@"
    fi
}

# lk_can_sudo COMMAND [USERNAME]
#
# Return true if the current user is allowed to execute COMMAND via sudo.
#
# Specify USERNAME to override the default target user (usually root). Set
# LK_NO_INPUT to return false if sudo requires a password.
#
# If the current user has no sudo privileges at all, they will not be prompted
# for a password.
function lk_can_sudo() {
    local COMMAND=${1-} USERNAME=${2-} ERROR
    [ -n "$COMMAND" ] || lk_warn "no command" || return
    [ -z "$USERNAME" ] || lk_user_exists "$USERNAME" ||
        lk_warn "user not found: $USERNAME" || return
    # 1. sudo exists
    lk_command_exists sudo && {
        # 2. The current user (or one of their groups) appears in sudo's
        #    security policy
        ERROR=$(sudo -nv 2>&1) ||
            # "sudo: a password is required" means the user can sudo
            grep -i password <<<"$ERROR" >/dev/null
    } && {
        # 3. The current user is allowed to execute COMMAND as USERNAME (attempt
        #    with prompting disabled first)
        sudo -n ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" &>/dev/null || {
            ! lk_no_input &&
                sudo ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" >/dev/null
        }
    }
}

function lk_me() {
    lk_maybe_sudo id -un
}

# lk_rm [-v] [--] [FILE...]
function lk_rm() {
    local v=
    [ "${1-}" != -v ] || { v=v && shift; }
    [ "${1-}" != -- ] || shift
    [ $# -gt 0 ] || return 0
    if lk_command_exists trash-put; then
        lk_maybe_sudo trash-put -f"$v" -- "$@"
    elif lk_command_exists trash; then
        local DELETE=()
        while [ $# -gt 0 ]; do
            lk_maybe_sudo test -e "$1" &&
                DELETE[${#DELETE[@]}]=$1 || true
            shift
        done
        [ -z "${DELETE+1}" ] ||
            lk_maybe_sudo trash -F"$v" -- "${DELETE[@]}"
    else
        lk_file_backup -m "$@" &&
            lk_maybe_sudo rm -Rf"$v" -- "$@"
    fi
}

# - lk_install [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
# - lk_install -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY...
#
# Create or set permissions and ownership on each FILE or DIRECTORY.
function lk_install() {
    local OPTIND OPTARG OPT LK_USAGE _USER LK_SUDO=${LK_SUDO-} \
        DIR MODE OWNER GROUP VERBOSE DEST STAT REGEX ARGS=()
    LK_USAGE="\
Usage: $FUNCNAME [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
   or: $FUNCNAME -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY..."
    while getopts ":dm:o:g:v" OPT; do
        case "$OPT" in
        d)
            DIR=1
            ARGS+=(-d)
            ;;
        m)
            MODE=$OPTARG
            ARGS+=(-m "$MODE")
            ;;
        o)
            OWNER=$(id -un "$OPTARG") &&
                _USER=$(id -un) || return
            ARGS+=(-o "$OWNER")
            [ "$OWNER" != "$_USER" ] ||
                unset OWNER
            ;;
        g)
            [[ ! $OPTARG =~ ^[0-9]+$ ]] ||
                lk_warn "invalid group: $OPTARG" || return
            GROUP=$OPTARG
            ARGS+=(-g "$GROUP")
            ;;
        v)
            VERBOSE=1
            ARGS+=(-v)
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -gt 0 ] || lk_usage || return
    [ -z "${OWNER-}" ] &&
        { [ -z "${GROUP-}" ] || lk_user_in_group "$GROUP"; } ||
        LK_SUDO=1
    if lk_is_true DIR; then
        lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} "$@"
    else
        for DEST in "$@"; do
            if lk_maybe_sudo test ! -e "$DEST" 2>/dev/null; then
                lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} /dev/null "$DEST"
            else
                STAT=$(lk_file_security "$DEST" 2>/dev/null) || return
                [ -z "${MODE-}" ] ||
                    { [[ $MODE =~ ^0*([0-7]+)$ ]] &&
                        REGEX=" 0*${BASH_REMATCH[1]}\$" &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_maybe_sudo chmod \
                        ${VERBOSE:+-v} "$MODE" "$DEST" ||
                    return
                [ -z "${OWNER-}${GROUP-}" ] ||
                    { REGEX='[-a-z0-9_]+\$?' &&
                        REGEX="^${OWNER:-$REGEX}:${GROUP:-$REGEX} " &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_elevate chown \
                        ${VERBOSE:+-v} "${OWNER-}${GROUP:+:$GROUP}" "$DEST" ||
                    return
            fi
        done
    fi
}

# lk_symlink [-f] TARGET LINK
#
# Safely add a symbolic link to TARGET from LINK. If -f is set, delete a file or
# directory at LINK instead of moving it to LINK.orig.
function lk_symlink() {
    local TARGET LINK LINK_DIR CURRENT_TARGET NO_ORIG v='' vv=''
    [ "${1-}" != -f ] || { NO_ORIG=1 && shift; }
    [ $# -eq 2 ] || lk_usage "\
Usage: $FUNCNAME [-f] TARGET LINK"
    TARGET=$1
    LINK=${2%/}
    LINK_DIR=${LINK%/*}
    [ "$LINK_DIR" != "$LINK" ] || LINK_DIR=.
    lk_maybe_sudo test -e "$TARGET" ||
        { [ "${TARGET:0:1}" != / ] &&
            lk_maybe_sudo test -e "$LINK_DIR/$TARGET"; } ||
        lk_warn "target not found: $TARGET" || return
    ! lk_verbose || v=v
    ! lk_verbose 2 || vv=v
    LK_SYMLINK_NO_CHANGE=${LK_SYMLINK_NO_CHANGE:-1}
    if lk_maybe_sudo test -L "$LINK"; then
        CURRENT_TARGET=$(lk_maybe_sudo readlink -- "$LINK") || return
        [ "$CURRENT_TARGET" != "$TARGET" ] ||
            return 0
        lk_maybe_sudo rm -f"$vv" -- "$LINK" || return
    elif lk_maybe_sudo test -e "$LINK"; then
        if ! lk_is_true NO_ORIG; then
            lk_maybe_sudo \
                mv -f"$v" -- "$LINK" "$LINK.orig" || return
        else
            lk_rm ${v:+"-$v"} -- "$LINK" || return
        fi
    elif lk_maybe_sudo test ! -d "$LINK_DIR"; then
        lk_maybe_sudo \
            install -d"$v" -- "$LINK_DIR" || return
    fi
    lk_maybe_sudo ln -s"$v" -- "$TARGET" "$LINK" &&
        LK_SYMLINK_NO_CHANGE=0
}

function lk_user_exists() {
    id "$1" &>/dev/null || return
}

function lk_user_home() {
    lk_expand_path "~${1-}"
}

# lk_user_groups [USER]
function lk_user_groups() {
    id -Gn | tr -s '[:blank:]' '\n'
}

# lk_user_in_group GROUP [USER]
function lk_user_in_group() {
    lk_user_groups ${2+"$2"} | grep -Fx "$1" >/dev/null
}

# lk_test_many TEST [VALUE...]
#
# Return true if every VALUE passes TEST, otherwise:
# - return 1 if there are no VALUE arguments;
# - return 2 if at least one VALUE passes TEST; or
# - return 3 if no VALUE passes TEST
function lk_test_many() {
    local TEST=${1-} PASSED=0 FAILED=0
    [ -n "$TEST" ] || lk_warn "no test command" || return
    shift
    [ $# -gt 0 ] || return 1
    while [ $# -gt 0 ] && ((PASSED + FAILED < 2)); do
        eval "($TEST \"\$1\")" &&
            PASSED=1 ||
            FAILED=1
        shift
    done
    [ $# -eq 0 ] && [ "$FAILED" -eq 0 ] || {
        [ "$PASSED" -eq 0 ] &&
            return 3 ||
            return 2
    }
}

function lk_paths_exist() {
    lk_test_many "lk_maybe_sudo test -e" "$@"
}

function lk_files_exist() {
    lk_test_many "lk_maybe_sudo test -f" "$@"
}

function lk_dirs_exist() {
    lk_test_many "lk_maybe_sudo test -d" "$@"
}

function lk_fifos_exist() {
    lk_test_many "lk_maybe_sudo test -p" "$@"
}

function lk_files_not_empty() {
    lk_test_many "lk_maybe_sudo test -s" "$@"
}

# lk_dir_parents [-u UNTIL] DIR...
function lk_dir_parents() {
    local UNTIL=/
    [ "${1-}" != -u ] || {
        UNTIL=$(_lk_realpath "$2") || return
        shift 2
    }
    _lk_realpath "$@" | awk -v "u=$UNTIL" 'BEGIN {
    l = length(u) + 1
}
substr($0 "/", 1, l) == u "/" {
    split(substr($0, l), a, "/")
    d = u
    for(i in a) {
        d = d (a[i] ? "/" a[i] : "")
        print d
    }
}' | lk_filter 'test -d'
}

# lk_remove_false TEST ARRAY
#
# Reduce ARRAY to each element where evaluating TEST returns true after
# replacing the string '{}' with the element's value. Array indices are not
# preserved.
function lk_remove_false() {
    local _LK_TEMP_ARRAY _LK_TEST _LK_VAL _lk_i=0
    _lk_array_fill_temp "$2" || return
    _LK_TEST="($(lk_replace '{}' '$_LK_VAL' "$1"))"
    eval "$2=()"
    for _LK_VAL in ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}; do
        ! eval "$_LK_TEST" || eval "$2[$((_lk_i++))]=\$_LK_VAL"
    done
}

# lk_remove_missing ARRAY
#
# Remove paths to missing files from ARRAY.
function lk_remove_missing() {
    lk_remove_false 'lk_maybe_sudo test -e "{}" -o -L "{}"' "$1"
}

# lk_remove_missing_or_empty ARRAY
#
# Remove paths to missing or empty files from ARRAY.
function lk_remove_missing_or_empty() {
    lk_remove_false 'lk_maybe_sudo test -s "{}" -o -L "{}"' "$1"
}

# lk_resolve_files ARRAY
#
# Resolve paths in ARRAY to absolute file names and remove any duplicates.
function lk_resolve_files() {
    local _LK_TEMP_ARRAY
    _lk_array_fill_temp "$1" || return
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            gnu_realpath -zm "${_LK_TEMP_ARRAY[@]}" | sort -zu
    )
}

# lk_expand_path [-z] [PATH]
#
# Perform quote removal, tilde expansion and glob expansion on PATH, then print
# each result. If -z is set, output NUL instead of newline after each result.
# The globstar shell option must be enabled with `shopt -s globstar` for **
# globs to be expanded.
function lk_expand_path() {
    local LK_Z=${LK_Z-} EXIT_STATUS _PATH SHOPT DELIM q g ARR
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    [ -n "${1-}" ] || lk_warn "no path" || return
    _PATH=$1
    SHOPT=$(shopt -p nullglob) || true
    shopt -s nullglob
    DELIM=${LK_Z:+'\0'}
    # If the path is double- or single-quoted, remove enclosing quotes and
    # unescape
    if [[ $_PATH =~ ^\"(.*)\"$ ]]; then
        _PATH=${BASH_REMATCH[1]//"\\\""/"\""}
    elif [[ $_PATH =~ ^\'(.*)\'$ ]]; then
        _PATH=${BASH_REMATCH[1]//"\\'"/"'"}
    fi
    # Perform tilde expansion
    if [[ $_PATH =~ ^(~[-a-z0-9\$_]*)(/.*)?$ ]]; then
        # `printf '%s%q'` outputs "~username''", which doesn't expand, if used
        # with no path
        eval "_PATH=$([ -n "${BASH_REMATCH[2]}" ] &&
            printf '%s%q' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ||
            printf '%s' "${BASH_REMATCH[1]}")"
    fi
    # Expand globs
    if [[ $_PATH =~ [*?] ]]; then
        # Escape characters that have special meanings within double quotes
        _PATH=$(lk_double_quote "$_PATH")
        _PATH=${_PATH:1:${#_PATH}-2}
        # Add quotes around glob sequences so that when the whole path is
        # quoted, they will be unquoted
        q='"'
        for g in '\*+' '\?+'; do
            while [[ $_PATH =~ (.*([^$q${g:1:1}]|^))($g)(.*) ]]; do
                _PATH=${BASH_REMATCH[1]}$q${BASH_REMATCH[3]}$q${BASH_REMATCH[4]}
            done
        done
        eval "ARR=($q$_PATH$q)"
        [ ${#ARR[@]} -eq 0 ] ||
            printf "%s${DELIM:-\\n}" "${ARR[@]}"
    else
        printf "%s${DELIM:-\\n}" "$_PATH"
    fi
    eval "$SHOPT"
}

# lk_expand_paths ARRAY
function lk_expand_paths() {
    local _LK_TEMP_ARRAY
    _lk_array_fill_temp "$1" || return
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            lk_expand_path -z "${_LK_TEMP_ARRAY[@]}"
    )
}

function lk_basename() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        sed -E 's/.*\/([^/]+)\/*$/\1/'
}

function lk_filter() {
    local LK_Z=${LK_Z-} EXIT_STATUS TEST DELIM
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 1 "$@" || return "$EXIT_STATUS"
    TEST=$1
    [ -n "$TEST" ] || lk_warn "no test command" || return
    shift
    DELIM=${LK_Z:+'\0'}
    ! eval "($TEST \"\$1\")" || printf "%s${DELIM:-\\n}" "$1"
}

function lk_is_declared() {
    declare -p "$1" &>/dev/null
}

function lk_is_readonly() {
    (unset "$1" 2>/dev/null) || return 0
    false
}

function lk_is_exported() {
    local REGEX="^declare -$NS*x$NS*"
    [[ $(declare -p "$1" 2>/dev/null) =~ $REGEX ]]
}

function lk_jq() {
    jq -L"${_LK_INST:-$LK_BASE}"/lib/{jq,json} "$@"
}

# lk_jq_get_array ARRAY [FILTER]
#
# Apply FILTER (default: ".[]") to the input and populate ARRAY with the
# JSON-encoded value of each result.
function lk_jq_get_array() {
    local SH
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    SH="$1=($(jq -r "${2:-.[]} | tostring | @sh"))" &&
        eval "$SH"
}

# lk_jq_get_shell_var [--arg NAME VALUE]... VAR FILTER [VAR FILTER]...
function lk_jq_get_shell_var() {
    local JQ ARGS=()
    while [ "${1-}" = --arg ]; do
        [ $# -ge 5 ] || lk_warn "invalid arguments" || return
        ARGS+=("${@:1:3}")
        shift 3
    done
    [ $# -gt 0 ] && ! (($# % 2)) || lk_warn "invalid arguments" || return
    JQ=$(printf '"%s":(%s),' "$@")
    JQ='include "core"; {'${JQ%,}'} | to_sh($_prefix)'
    lk_jq -r \
        ${ARGS[@]+"${ARGS[@]}"} \
        --arg _prefix "$(lk_maybe_local)" \
        "$JQ"
}

function lk_json_from_xml_schema() {
    [ $# -gt 0 ] && [ $# -le 2 ] && lk_files_exist "$@" || lk_usage "\
Usage: $FUNCNAME XSD_FILE [XML_FILE]" || return
    "$LK_BASE/lib/python/json_from_xml_schema.py" "$@"
}

# lk_random_hex BYTES
function lk_random_hex() {
    [ $# -gt 0 ] && [[ $1 =~ ^[0-9]+$ ]] ||
        lk_warn "invalid arguments" || return
    [ "$1" -lt 1 ] ||
        printf '%02x' $(for i in $(seq 1 "$1"); do echo $((RANDOM % 256)); done)
}

# lk_random_password [LENGTH]
function lk_random_password() {
    local LENGTH=${1:-16} PASSWORD=
    LK_RANDOM_ITERATIONS=0
    while [ ${#PASSWORD} -lt "$LENGTH" ]; do
        ((++LK_RANDOM_ITERATIONS))
        # Increase BYTES by 10% to compensate for removal of 'look-alike'
        # characters, reducing chance of 2+ iterations from >50% to <2%
        PASSWORD=$PASSWORD$(openssl rand -base64 \
            $((BITS = LENGTH * 6, BYTES = BITS / 8 + (BITS % 8 ? 1 : 0), BYTES * 11 / 10)) |
            sed -E 's/[lIO01\n]+//g') || return
        PASSWORD=${PASSWORD//$'\n'/}
    done
    printf '%s' "${PASSWORD:0:$LENGTH}"
}

# lk_base64 [-d]
function lk_base64() {
    local DECODE
    [ "${1-}" != -d ] || DECODE=1
    if lk_command_exists openssl &&
        openssl base64 &>/dev/null </dev/null; then
        # OpenSSL's implementation is ubiquitous and well-behaved
        openssl base64 ${DECODE:+-d}
    elif lk_command_exists base64 &&
        base64 --version 2>/dev/null </dev/null | grep -i gnu >/dev/null; then
        # base64 on BSD and some legacy systems (e.g. RAIDiator 4.x) doesn't
        # wrap lines by default
        base64 ${DECODE:+--decode}
    else
        false
    fi
}

function _lk_file_sort() {
    sort "${@:--n}" | sed -E 's/^[0-9]+ ://'
}

if ! lk_is_macos; then
    function lk_file_sort_by_date() {
        lk_maybe_sudo stat -c '%Y :%n' -- "$@" | _lk_file_sort
    }
    function lk_file_modified() {
        lk_maybe_sudo stat -c '%Y' -- "$@"
    }
    function lk_file_owner() {
        lk_maybe_sudo stat -c '%U' -- "$@"
    }
    function lk_file_group() {
        lk_maybe_sudo stat -c '%G' -- "$@"
    }
    function lk_file_mode() {
        lk_maybe_sudo stat -c '%04a' -- "$@"
    }
    function lk_file_security() {
        lk_maybe_sudo stat -c '%U:%G %04a' -- "$@"
    }
    function lk_full_name() {
        getent passwd "${1:-$UID}" | cut -d: -f5 | cut -d, -f1
    }
else
    # lk_dscl_read [PATH] KEY
    function lk_dscl_read() {
        [ $# -ne 1 ] || set -- "/Users/$USER" "$1"
        [ $# -eq 2 ] || lk_warn "invalid arguments" || return
        dscl . -read "$@" |
            sed -E "1s/^$(lk_escape_ere "$2")://;s/^ //;/^\$/d"
    }
    function lk_full_name() {
        lk_dscl_read RealName
    }
    function lk_file_sort_by_date() {
        lk_maybe_sudo stat -t '%s' -f '%Sm :%N' -- "$@" | _lk_file_sort
    }
    function lk_file_modified() {
        lk_maybe_sudo stat -t '%s' -f '%Sm' -- "$@"
    }
    function lk_file_owner() {
        lk_maybe_sudo stat -f '%Su' -- "$@"
    }
    function lk_file_group() {
        lk_maybe_sudo stat -f '%Sg' -- "$@"
    }
    function lk_file_mode() {
        # Output octal (O) file mode (p) twice, first for the suid, sgid, and
        # sticky bits (M), then with zero-padding (03) for the user, group, and
        # other bits (L)
        lk_maybe_sudo stat -f '%OMp%03OLp' -- "$@"
    }
    function lk_file_security() {
        lk_maybe_sudo stat -f '%Su:%Sg %OMp%03OLp' -- "$@"
    }
fi

# lk_file_age FILE
#
# Output the number of seconds since FILE was last modified.
function lk_file_age() {
    local MODIFIED
    MODIFIED=$(lk_file_modified "$1") &&
        echo $(($(lk_timestamp) - MODIFIED))
}

if ! lk_is_macos; then
    function lk_timestamp_readable() {
        gnu_date -Rd "@$1"
    }
else
    function lk_timestamp_readable() {
        date -Rjf '%s' "$1"
    }
fi

function lk_realpath() {
    local FILE=$1 i=0 COMPONENT LN RESOLVED=
    lk_maybe_sudo test -e "$FILE" || return
    [ "${FILE:0:1}" = / ] || FILE=${PWD%/}/$FILE
    while [ -n "$FILE" ]; do
        ((i++)) || {
            # 1. Replace "/./" with "/"
            # 2. Replace subsequent "/"s with one "/"
            # 3. Remove trailing "/"
            FILE=$(sed -E \
                -e 's/\/\.\//\//g' \
                -e 's/\/+/\//g' \
                -e 's/\/$//' <<<"$FILE") || return
            FILE=${FILE:1}
        }
        COMPONENT=${FILE%%/*}
        [ "$COMPONENT" != "$FILE" ] ||
            FILE=
        FILE=${FILE#*/}
        case "$COMPONENT" in
        '' | .)
            continue
            ;;
        ..)
            RESOLVED=${RESOLVED%/*}
            continue
            ;;
        esac
        RESOLVED=$RESOLVED/$COMPONENT
        ! lk_maybe_sudo test -L "$RESOLVED" || {
            LN=$(lk_maybe_sudo readlink "$RESOLVED") || return
            [ "${LN:0:1}" = / ] || LN=${RESOLVED%/*}/$LN
            FILE=$LN${FILE:+/$FILE}
            RESOLVED=
            i=0
        }
    done
    echo "$RESOLVED"
}

function _lk_realpath() {
    local STATUS=0
    if lk_command_exists realpath; then
        lk_maybe_sudo realpath "$@"
    else
        while [ $# -gt 0 ]; do
            lk_realpath "$1" || STATUS=$?
            shift
        done
        return "$STATUS"
    fi
}

# lk_file_get_text FILE VAR
#
# Read the entire FILE into variable VAR, adding a newline at the end unless
# FILE has zero bytes or its last byte is a newline.
function lk_file_get_text() {
    lk_maybe_sudo test -e "$1" || lk_warn "file not found: $1" || return
    lk_is_identifier "$2" || lk_warn "not a valid identifier: $2" || return
    eval "$2=\$(lk_maybe_sudo cat \"\$1\" && printf .)" &&
        eval "$2=\${$2%.}" &&
        { [ -z "${!2:+1}" ] ||
            eval "$2=\${$2%\$'\\n'}\$'\\n'"; }
}

# lk_file_keep_original FILE
function lk_file_keep_original() {
    [ "${LK_FILE_KEEP_ORIGINAL:-1}" -eq 1 ] || return 0
    local v=
    ! lk_verbose || v=v
    while [ $# -gt 0 ]; do
        ! lk_maybe_sudo test -s "$1" ||
            lk_maybe_sudo test -e "$1.orig" ||
            lk_maybe_sudo cp -naL"$v" "$1" "$1.orig" || return
        shift
    done
}

# lk_file_get_backup_suffix [TIMESTAMP]
function lk_file_get_backup_suffix() {
    echo ".lk-bak-$(lk_date "%Y%m%dT%H%M%SZ" ${1+"$1"})"
}

# lk_file_backup [-m] [FILE...]
#
# Copy each FILE to FILE.lk-bak-TIMESTAMP, where TIMESTAMP is the file's last
# modified time in UTC (e.g. 20201202T095515Z). If -m is set, copy FILE to
# LK_BASE/var/backup if elevated, or ~/.lk-platform/backup if not elevated.
function lk_file_backup() {
    local MOVE=${LK_FILE_BACKUP_MOVE-} FILE OWNER OWNER_HOME DEST GROUP \
        MODIFIED SUFFIX TZ=UTC s vv=
    [ "${1-}" != -m ] || { MOVE=1 && shift; }
    ! lk_verbose 2 || vv=v
    export TZ
    while [ $# -gt 0 ]; do
        if lk_maybe_sudo test -e "$1"; then
            lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
            lk_maybe_sudo test -s "$1" || return 0
            ! lk_is_true MOVE || {
                FILE=$(_lk_realpath "$1") || return
                {
                    OWNER=$(lk_file_owner "$FILE") &&
                        OWNER_HOME=$(lk_expand_path "~$OWNER") &&
                        OWNER_HOME=$(_lk_realpath "$OWNER_HOME")
                } 2>/dev/null || OWNER_HOME=
                if [ -d "${_LK_INST:-${LK_BASE-}}" ] &&
                    lk_will_elevate && [ "${FILE#$OWNER_HOME}" = "$FILE" ]; then
                    lk_install -d \
                        -m "$([ -g "${_LK_INST:-$LK_BASE}" ] &&
                            echo 02775 ||
                            echo 00755)" \
                        "${_LK_INST:-$LK_BASE}/var" || return
                    DEST=${_LK_INST:-$LK_BASE}/var/backup
                    unset OWNER
                elif lk_will_elevate; then
                    DEST=$OWNER_HOME/.lk-platform/backup
                    GROUP=$(id -gn "$OWNER") &&
                        lk_install -d -m 00755 -o "$OWNER" -g "$GROUP" \
                            "$OWNER_HOME/.lk-platform" || return
                else
                    DEST=~/.lk-platform/backup
                    unset OWNER
                fi
                lk_install -d -m 00700 ${OWNER:+-o "$OWNER" -g "$GROUP"} \
                    "$DEST" || return
                s=/
                DEST=$DEST/${FILE//"$s"/__}
            }
            MODIFIED=$(lk_file_modified "$1") &&
                SUFFIX=$(lk_file_get_backup_suffix "$MODIFIED") &&
                lk_maybe_sudo cp -naL"$vv" "$1" "${DEST:-$1}$SUFFIX"
        fi
        shift
    done
}

# lk_file_prepare_temp [-n] FILE
function lk_file_prepare_temp() {
    local DIR TEMP NO_COPY MODE vv=
    [ "${1-}" != -n ] || { NO_COPY=1 && shift; }
    DIR=${1%/*}
    [ "$DIR" != "$1" ] || DIR=$PWD
    ! lk_verbose 2 || vv=v
    TEMP=$(lk_maybe_sudo mktemp -- "${DIR%/}/.${1##*/}.XXXXXXXXXX") || return
    ! lk_maybe_sudo test -f "$1" ||
        if lk_is_true NO_COPY; then
            local OPT
            lk_is_macos || OPT=--
            MODE=$(lk_file_mode "$1") &&
                lk_maybe_sudo chmod "$(lk_pad_zero 5 "$MODE")" \
                    ${OPT:+"$OPT"} "$TEMP"
        else
            lk_maybe_sudo cp -aL"$vv" -- "$1" "$TEMP"
        fi >&2 || return
    echo "$TEMP"
}

# lk_file_replace [OPTIONS] TARGET [CONTENT]
function lk_file_replace() {
    local OPTIND OPTARG OPT LK_USAGE IFS SOURCE= IGNORE= FILTER= ASK= \
        LINK=1 BACKUP=${LK_FILE_BACKUP_TAKE-} MOVE=${LK_FILE_BACKUP_MOVE-} \
        NEW=1 VERB=Created CONTENT PREVIOUS TEMP vv=
    unset IFS PREVIOUS
    LK_USAGE="\
Usage: $FUNCNAME [OPTIONS] TARGET [CONTENT]

If TARGET differs from input or CONTENT, replace TARGET.

Options:
  -f SOURCE     read CONTENT from SOURCE
  -i PATTERN    ignore lines matching the regular expression when comparing
  -s SCRIPT     filter lines through \`sed -E SCRIPT\` when comparing
  -b            back up TARGET before replacing it
  -m            use a separate location when backing up (-b is implied)
  -p            prompt before replacing TARGET"
    while getopts ":f:i:s:lbmp" OPT; do
        case "$OPT" in
        b)
            BACKUP=1
            MOVE=
            ;;
        m)
            BACKUP=1
            MOVE=1
            ;;
        l)
            LINK=1
            ;;
        i)
            IGNORE=$OPTARG
            ;;
        s)
            FILTER=$OPTARG
            ;;
        f)
            SOURCE=$OPTARG
            lk_file_get_text "$SOURCE" CONTENT ||
                return
            ;;
        p)
            ASK=1
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -gt 0 ] || lk_usage || return
    if [ $# -ge 2 ]; then
        CONTENT=$2
    elif [ -z "$SOURCE" ]; then
        CONTENT=$(cat && printf .) || return
        CONTENT=${CONTENT%.}
    fi
    ! lk_verbose 2 || vv=v
    LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE:-1}
    LK_FILE_REPLACE_DECLINED=0
    if lk_maybe_sudo test -e "$1"; then
        ! lk_is_true LINK || {
            TEMP=$(_lk_realpath "$1") || return
            set -- "$TEMP"
        }
        lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
        ! lk_maybe_sudo test -s "$1" || unset NEW VERB
        lk_maybe_sudo test -L "$1" || ! diff \
            <(TARGET=$1 _lk_maybe_filter "$IGNORE" "$FILTER" \
                lk_maybe_sudo cat "\"\$TARGET\"") \
            <([ -z "${CONTENT:+1}" ] || _lk_maybe_filter "$IGNORE" "$FILTER" \
                echo "\"\${CONTENT%\$'\\n'}\"") >/dev/null || {
            ! lk_verbose 2 || lk_console_detail "Not changed:" "$1"
            return 0
        }
        ! lk_is_true ASK || lk_is_true NEW || {
            lk_console_diff "$1" "" <<<"${CONTENT%$'\n'}" || return
            lk_confirm "Replace $1 as above?" Y || {
                LK_FILE_REPLACE_DECLINED=1
                return 1
            }
        }
        ! lk_verbose || lk_is_true LK_FILE_NO_DIFF ||
            lk_file_get_text "$1" PREVIOUS || return
        ! lk_is_true BACKUP ||
            lk_file_backup ${MOVE:+-m} "$1" || return
    fi
    TEMP=$(lk_file_prepare_temp "$1") &&
        lk_delete_on_exit "$TEMP" &&
        { [ -z "${CONTENT:+1}" ] || echo "${CONTENT%$'\n'}"; } |
        lk_maybe_sudo tee "$TEMP" >/dev/null &&
        lk_maybe_sudo mv -f"$vv" "$TEMP" "$1" &&
        LK_FILE_REPLACE_NO_CHANGE=0 || return
    ! lk_verbose || {
        if lk_is_true LK_FILE_NO_DIFF || lk_is_true ASK; then
            lk_console_detail "${VERB:-Updated}:" "$1"
        elif [ -n "${PREVIOUS+1}" ]; then
            echo -n "$PREVIOUS" | lk_console_detail_diff "" "$1"
        else
            lk_console_detail_file "$1"
        fi
    }
} #### Reviewed: 2021-03-26

# _lk_maybe_filter DELETE_PATTERN SED_SCRIPT QUOTED_COMMAND...
function _lk_maybe_filter() {
    case "${1:+g}${2:+s}" in
    g)
        eval "${*:3}" | grep -Ev "$1" || [ ${PIPESTATUS[1]} -eq 1 ]
        ;;
    s)
        eval "${*:3}" | sed -E "$2"
        ;;
    gs)
        { eval "${*:3}" | grep -Ev "$1" || [ ${PIPESTATUS[1]} -eq 1 ]; } |
            sed -E "$2"
        ;;
    *)
        eval "${*:3}"
        ;;
    esac
} #### Reviewed: 2021-03-26

# lk_nohup COMMAND [ARG...]
function lk_nohup() { (
    _LK_CAN_FAIL=1
    trap "" SIGHUP SIGINT SIGTERM
    set -m
    OUT_FILE=$(TMPDIR=$(lk_first_existing "$LK_BASE/var/log" ~ /tmp) &&
        _LK_MKTEMP_EXT=.nohup.out lk_mktemp_file) &&
        OUT_FD=$(lk_fd_next) &&
        eval "exec $OUT_FD"'>"$OUT_FILE"' || return
    ! lk_verbose || lk_console_item "Redirecting output to" "$OUT_FILE"
    if lk_log_is_open; then
        TTY_OUT_FD=$_LK_TTY_OUT_FD &&
            TTY_ERR_FD=$_LK_TTY_ERR_FD &&
            _LK_TTY_OUT_FD=$OUT_FD &&
            _LK_TTY_ERR_FD=$OUT_FD &&
            ${_LK_LOG_TTY_LAST:-lk_log_tty_on} &&
            exec </dev/null
    else
        TTY_OUT_FD=$(lk_fd_next) &&
            eval "exec $TTY_OUT_FD>&1" &&
            TTY_ERR_FD=$(lk_fd_next) &&
            eval "exec $TTY_ERR_FD>&2" &&
            exec >&"$OUT_FD" 2>&1 </dev/null
    fi || return
    (trap - SIGHUP SIGINT SIGTERM &&
        exec tail -fn+1 "$OUT_FILE") >&"$TTY_OUT_FD" 2>&"$TTY_ERR_FD" &
    lk_kill_on_exit $!
    "$@" &
    wait $! 2>/dev/null
); }

function lk_ignore_SIGINT() {
    trap "" SIGINT
}

function lk_propagate_SIGINT() {
    local PGID
    PGID=$(($(ps -o pgid= $$))) &&
        trap - SIGINT &&
        kill -SIGINT -- -"$PGID"
}

function _lk_exit_trap() {
    local STATUS=$?
    [ $STATUS -eq 0 ] || [ "${_LK_CAN_FAIL-}" = 1 ] ||
        [[ ${FUNCNAME[1]-} =~ ^_?lk_(die|usage)$ ]] ||
        { [[ $- == *i* ]] && [ $BASH_SUBSHELL -eq 0 ]; } ||
        lk_console_error \
            "$(LK_VERBOSE=1 \
                _lk_caller "${_LK_ERR_TRAP_CALLER:-$1}"): unhandled error" \
            "$(lk_stack_trace \
                $((1 - ${_LK_STACK_DEPTH:-0})) \
                "$([ "${LK_NO_STACK_TRACE-}" != 1 ] || echo 1)" \
                "${_LK_ERR_TRAP_CALLER-}")"
} #### Reviewed: 2021-05-28

function _lk_err_trap() {
    _LK_ERR_TRAP_CALLER=$1
} #### Reviewed: 2021-05-28

set -o pipefail

lk_trap_add EXIT '_lk_exit_trap "$LINENO ${FUNCNAME-} ${BASH_SOURCE-}"'
lk_trap_add ERR '_lk_err_trap "$LINENO ${FUNCNAME-} ${BASH_SOURCE-}"'

if lk_is_true LK_TTY_NO_COLOUR; then
    declare \
        LK_BLACK= \
        LK_RED= \
        LK_GREEN= \
        LK_YELLOW= \
        LK_BLUE= \
        LK_MAGENTA= \
        LK_CYAN= \
        LK_WHITE= \
        LK_GREY= \
        LK_BLACK_BG= \
        LK_RED_BG= \
        LK_GREEN_BG= \
        LK_YELLOW_BG= \
        LK_BLUE_BG= \
        LK_MAGENTA_BG= \
        LK_CYAN_BG= \
        LK_WHITE_BG= \
        LK_GREY_BG= \
        LK_BOLD= \
        LK_DIM= \
        LK_UNDIM= \
        LK_RESET=
else
    # See: `man 4 console_codes`
    declare \
        LK_BLACK=$'\E[30m' \
        LK_RED=$'\E[31m' \
        LK_GREEN=$'\E[32m' \
        LK_YELLOW=$'\E[33m' \
        LK_BLUE=$'\E[34m' \
        LK_MAGENTA=$'\E[35m' \
        LK_CYAN=$'\E[36m' \
        LK_WHITE=$'\E[37m' \
        LK_GREY=$'\E[90m' \
        LK_BLACK_BG=$'\E[40m' \
        LK_RED_BG=$'\E[41m' \
        LK_GREEN_BG=$'\E[42m' \
        LK_YELLOW_BG=$'\E[43m' \
        LK_BLUE_BG=$'\E[44m' \
        LK_MAGENTA_BG=$'\E[45m' \
        LK_CYAN_BG=$'\E[46m' \
        LK_WHITE_BG=$'\E[47m' \
        LK_GREY_BG=$'\E[100m' \
        LK_BOLD=$'\E[1m' \
        LK_DIM=$'\E[2m' \
        LK_UNDIM=$'\E[22m' \
        LK_RESET=$'\E[m\017'

    case "${TERM-}" in
    '' | dumb | unknown)
        [ -z "${TERM+1}" ] || unset TERM
        ;;
    linux | vt220 | xterm-*color) ;;
    *)
        eval "$(lk_get_colours)"
        ;;
    esac
fi

_LK_COLOUR=$LK_CYAN
_LK_ALT_COLOUR=$LK_YELLOW
_LK_SUCCESS_COLOUR=$LK_GREEN
_LK_WARNING_COLOUR=$LK_YELLOW
_LK_ERROR_COLOUR=$LK_RED

true || {
    env
    md5
    md5sum
    pbcopy
    pbpaste
    sha256sum
    shasum
    xclip
    xxh32sum
    xxh64sum
    xxh128sum
    xxhsum
}

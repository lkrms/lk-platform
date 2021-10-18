#!/bin/bash

# lk_pass [-STATUS] COMMAND [ARG...]
#
# Run COMMAND without changing the previous command's exit status, or run
# COMMAND and return STATUS.
function lk_pass() {
    local STATUS=$?
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { STATUS=${1:1} && shift; }
    "$@" || true
    return "$STATUS"
}

# lk_err MESSAGE
function lk_err() {
    lk_pass echo "${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-${0##*/}}: $1" >&2
}

# lk_script_name [STACK_DEPTH]
function lk_script_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    lk_script_running ||
        NAME=${FUNCNAME[1 + DEPTH]+"${FUNCNAME[*]: -1}"}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_caller_name [STACK_DEPTH]
function lk_caller_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    NAME=${FUNCNAME[2 + DEPTH]-}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_first_command [COMMAND...]
#
# Print the first executable COMMAND in PATH or return false if no COMMAND was
# found. To allow the inclusion of arguments, word splitting is performed on
# each COMMAND after resetting IFS.
function lk_first_command() {
    local IFS CMD
    unset IFS
    while [ $# -gt 0 ]; do
        CMD=($1)
        ! type -P "${CMD[0]}" >/dev/null || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_first_file [FILE...]
#
# Print the first FILE that exists or return false if no FILE was found.
function lk_first_file() {
    while [ $# -gt 0 ]; do
        [ ! -e "$1" ] || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_plural [-v] VALUE SINGLE [PLURAL]
#
# Print SINGLE if VALUE is 1 or the name of an array with 1 element, PLURAL
# otherwise. If PLURAL is omitted, print "${SINGLE}s" instead. If -v is set,
# include VALUE in the output.
function lk_plural() {
    local VALUE
    [ "${1-}" != -v ] || { VALUE=1 && shift; }
    local COUNT=$1
    [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || eval "COUNT=\${#$1[@]}" || return
    VALUE="${VALUE:+$COUNT }"
    [ "$COUNT" = 1 ] && echo "$VALUE$2" || echo "$VALUE${3-$2s}"
}

# lk_assign VAR
#
# Read standard input until EOF or NUL and assign it to VAR.
#
# Example:
#
#     lk_assign SQL <<"SQL"
#     SELECT id, name FROM table;
#     SQL
function lk_assign() {
    IFS= read -rd '' "$1"
}

# lk_maybe_local
#
# Print 'local ' with no line break if the caller was called by a function.
# Useful when emitting variable declarations.
function lk_maybe_local() {
    local DEPTH=${1:-${_LK_STACK_DEPTH:-0}}
    ((DEPTH < 0)) ||
        case "${FUNCNAME[DEPTH + 2]-}" in
        '' | source | main) ;;
        *) printf 'local ' ;;
        esac
}

# lk_x_off
#
# Output Bash commands that disable xtrace temporarily and prevent themselves
# from appearing in trace output.
#
# Recommended usage, assuming Bash could be writing trace output to either FD 2
# or FD 4:
#
#     function quiet() {
#         { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
#         # Can also be used in a && or || list
#         eval "$_lk_x_return"
#     }
#
# Or, outside of a function:
#
#     { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
#     eval "$_lk_x_restore"
function lk_x_off() {
    echo 'eval "{ declare _lk_x_restore= _lk_x_return=\"return \\\$?\"; [ \"\${-/x/}\" = \"\$-\" ] || { _lk_x_restore=\"set -x\"; _lk_x_return=\"eval \\\"{ local _lk_x_status=\\\\\\\$?; set -x; return \\\\\\\$_lk_x_status; } \\\${BASH_XTRACEFD:-2}>/dev/null\\\"\"; set +x; }; } ${BASH_XTRACEFD:-2}>/dev/null"'
}

#### Reviewed: 2021-10-18

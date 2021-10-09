#!/bin/bash

# lk_pass [-STATUS] COMMAND [ARG...]
function lk_pass() {
    local STATUS=$?
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { STATUS=${1:1} && shift; }
    "$@" || true
    return "$STATUS"
}

function lk_err() {
    lk_pass echo "${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-${0##*/}}: $1" >&2
}

# lk_trace [MESSAGE]
function lk_trace() {
    [ "${LK_DEBUG-}" = Y ] || return 0
    local NOW
    NOW=$(gnu_date +%s.%N) || return 0
    _LK_TRACE_FIRST=${_LK_TRACE_FIRST:-$NOW}
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$NOW" \
        "$_LK_TRACE_FIRST" \
        "${_LK_TRACE_LAST:-$NOW}" \
        "${1+${1::30}}" \
        "${BASH_SOURCE[1]+${BASH_SOURCE[1]#$LK_BASE/}:${BASH_LINENO[0]}}" |
        awk -F'\t' -v "d=$LK_DIM" -v "u=$LK_UNDIM" \
            '{printf "%s%09.4f  +%.4f\t%-30s\t%s\n",d,$1-$2,$1-$3,$4,$5 u}' >&2
    _LK_TRACE_LAST=$NOW
}

# lk_script_name [STACK_DEPTH]
function lk_script_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    lk_script_running ||
        NAME=${FUNCNAME[1 + DEPTH]+"${FUNCNAME[*]: -1}"}
    echo "${NAME:-${0##*/}}"
}

# lk_caller_name [STACK_DEPTH]
function lk_caller_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0}))
    echo "${FUNCNAME[2 + DEPTH]-${0##*/}}"
}

function lk_first_command() {
    local IFS CMDLINE
    unset IFS
    while [ $# -gt 0 ]; do
        CMDLINE=($1)
        if type -P "${CMDLINE[0]}" >/dev/null; then
            echo "$1"
            return 0
        fi
        shift
    done
    false
}

function lk_first_file() {
    while [ $# -gt 0 ]; do
        [ ! -e "$1" ] || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_plural [-v] VALUE SINGLE_NOUN [PLURAL_NOUN]
#
# Print SINGLE_NOUN if VALUE is 1 or the name of an array with 1 element,
# PLURAL_NOUN otherwise. If PLURAL_NOUN is omitted, print "${SINGLE_NOUN}s"
# instead. If -v is set, include VALUE in the output.
function lk_plural() {
    local VALUE
    [ "${1-}" != -v ] || { VALUE=1 && shift; }
    local COUNT=$1
    [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || eval "COUNT=\${#$1[@]}" || return
    VALUE="${VALUE:+$COUNT }"
    [ "$COUNT" = 1 ] && echo "$VALUE$2" || echo "$VALUE${3-$2s}"
}

function lk_maybe_local() {
    local DEPTH=${1:-${_LK_STACK_DEPTH:-0}}
    ((DEPTH < 0)) ||
        case "${FUNCNAME[DEPTH + 2]-}" in
        '' | source | main) ;;
        *) printf 'local ' ;;
        esac
}

#### Reviewed: 2021-10-07

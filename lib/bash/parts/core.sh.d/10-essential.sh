#!/bin/bash

# lk_pass [-STATUS] COMMAND [ARG...]
function lk_pass() {
    local s=$?
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { s=${1:1} && shift; }
    "$@" || true
    return "$s"
}

function lk_err() {
    local d=${_LK_STACK_DEPTH:-0}
    lk_pass echo "${FUNCNAME[1 + d]-${0##*/}}: $1" >&2
}

function lk_first_command() {
    local IFS c
    unset IFS
    while [ $# -gt 0 ]; do
        c=($1)
        if type -P "${c[0]}" >/dev/null; then
            echo "$1"
            return 0
        fi
        shift
    done
    false
}

# lk_plural [-v] VALUE SINGLE_NOUN [PLURAL_NOUN]
#
# Print SINGLE_NOUN if VALUE is 1 or the name of an array with 1 element,
# PLURAL_NOUN otherwise. If PLURAL_NOUN is omitted, print "${SINGLE_NOUN}s"
# instead. If -v is set, include VALUE in the output.
function lk_plural() {
    local v
    [ "${1-}" != -v ] || { v=1 && shift; }
    local c=$1
    [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || eval "c=\${#$1[@]}" || return
    v="${v:+$c }"
    [ "$c" = 1 ] && echo "$v$2" || echo "$v${3-$2s}"
}

#### Reviewed: 2021-09-27

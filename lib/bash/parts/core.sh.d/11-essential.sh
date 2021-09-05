#!/bin/bash

# lk_pass [-STATUS] COMMAND [ARG...]
function lk_pass() {
    local s=$?
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { s=${1:1} && shift; }
    "$@" || true
    return "$s"
}

function lk_err() {
    lk_pass echo "${FUNCNAME[1]-${0##*/}}: $1" >&2
}

function lk_command_first() {
    local IFS COMMAND
    unset IFS
    while [ $# -gt 0 ]; do
        COMMAND=($1)
        if type -P "${COMMAND[0]}" >/dev/null; then
            echo "$1"
            break
        fi
        unset COMMAND
        shift
    done
    [ -n "${COMMAND+1}" ]
}

#### Reviewed: 2021-09-06

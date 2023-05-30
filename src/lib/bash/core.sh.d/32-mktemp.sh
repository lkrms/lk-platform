#!/bin/bash

function lk_mktemp() {
    local TMPDIR=${TMPDIR:-/tmp} FUNC=${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-}
    mktemp "$@" ${_LK_MKTEMP_ARGS-} \
        "${TMPDIR%/}/${0##*/}${FUNC:+-$FUNC}${_LK_MKTEMP_EXT-}.XXXXXXXXXX"
}

# lk_mktemp_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary file that will be deleted when the (sub)shell exits, assign
# its path to VAR, and return after invoking COMMAND (if given) and redirecting
# its output to the file. If VAR is already set to the path of an existing
# file and -r ("reuse") is set, proceed without creating a new file.
function lk_mktemp_with() {
    local _REUSE= _DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [ "${1-}" != -r ] || { _REUSE=1 && shift; }
    [ $# -ge 1 ] || lk_err "invalid arguments" || return
    local _VAR=$1
    shift
    [ -n "${_REUSE-}" ] && [ -e "${!_VAR-}" ] ||
        { eval "$_VAR=\$(_LK_STACK_DEPTH=\$_DEPTH lk_mktemp)" &&
            lk_delete_on_exit "${!_VAR}"; } || return
    LK_MKTEMP_WITH_LAST=${!_VAR}
    [ $# -eq 0 ] || "$@" >"${!_VAR}"
}

# lk_mktemp_dir_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary directory that will be deleted when the (sub)shell exits,
# assign its path to VAR, and return after invoking COMMAND (if given) in the
# directory. If VAR is already set to the path of an existing directory and -r
# ("reuse") is set, proceed without creating a new directory.
function lk_mktemp_dir_with() {
    local _ARGS=() _DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [ -z "${1+1}" ] || _ARGS[0]=$1
    [ "${1-}" != -r ] || [ -z "${2+1}" ] || _ARGS[1]=$2
    _LK_STACK_DEPTH=$_DEPTH _LK_MKTEMP_ARGS=-d \
        lk_mktemp_with ${_ARGS+"${_ARGS[@]}"} || return
    local _VAR=${_ARGS[1]-${_ARGS[0]}}
    shift "${#_ARGS[@]}"
    [ $# -eq 0 ] || (cd "${!_VAR}" && "$@")
}

#### Reviewed: 2021-10-31

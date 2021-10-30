#!/bin/bash

function lk_mktemp() {
    local TMPDIR=${TMPDIR:-/tmp} FUNC=${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-}
    mktemp "$@" ${_LK_MKTEMP_ARGS+"${_LK_MKTEMP_ARGS[@]}"} \
        "${TMPDIR%/}/${0##*/}${FUNC:+-$FUNC}${_LK_MKTEMP_EXT-}.XXXXXXXXXX"
}

# lk_mktemp_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary file that will be deleted when the (sub)shell exits, assign
# its path to VAR, and return after invoking COMMAND (if given) and redirecting
# its output to the file. If VAR is already set to the path of an existing
# file and -r ("reuse") is set, proceed without creating a new file.
function lk_mktemp_with() {
    local _REUSE= _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [ "${1-}" != -r ] || { _REUSE=1 && shift; }
    [ $# -ge 1 ] || lk_err "invalid arguments" || return
    local _VAR=$1
    shift
    [ -n "${_REUSE-}" ] && [ -e "${!_VAR-}" ] ||
        { eval "$_VAR=\$(lk_mktemp)" &&
            lk_delete_on_exit "${!_VAR}"; } || return
    { [ $# -eq 0 ] || "$@" >"${!_VAR}"; }
}

# lk_mktemp_dir_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary directory that will be deleted when the (sub)shell exits,
# assign its path to VAR, and return after invoking COMMAND (if given) in the
# directory. If VAR is already set to the path of an existing directory and -r
# ("reuse") is set, proceed without creating a new directory.
function lk_mktemp_dir_with() {
    local IFS _ARG=1 _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0})) \
        _LK_MKTEMP_ARGS=(-d)
    unset IFS
    [ "${1-}" != -r ] || { _ARG=2; }
    lk_mktemp_with "${@:1:_ARG}" || return
    local _VAR=${!_ARG}
    { [ $# -eq "$_ARG" ] || (cd "${!_VAR}" && "${@:_ARG+1}"); }
}

#### Reviewed: 2021-10-30

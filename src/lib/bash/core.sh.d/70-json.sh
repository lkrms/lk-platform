#!/bin/bash

function lk_jq() {
    jq -L"$LK_BASE/lib"/{jq,json} "$@"
}

# lk_json_mapfile <ARRAY> [JQ_FILTER]
#
# Apply JQ_FILTER (default: '.[]') to the input and populate ARRAY with the
# output, using JSON encoding if necessary.
function lk_json_mapfile() {
    local IFS _SH
    unset IFS
    _SH="$1=($(lk_jq -r "${2:-.[]} | tostring | @sh"))" &&
        eval "$_SH"
}

# lk_json_sh (<VAR> <JQ_FILTER>)...
function lk_json_sh() {
    (($# && !($# % 2))) || lk_err "invalid arguments" || return
    local IFS
    unset IFS
    lk_jq -r --arg prefix "$(_lk_var)" 'include "core"; {'"$(
        printf '"%s":(%s)' "${@:1:2}"
        (($# < 3)) || printf ',"%s":(%s)' "${@:3}"
    )"'} | to_sh($prefix)'
}

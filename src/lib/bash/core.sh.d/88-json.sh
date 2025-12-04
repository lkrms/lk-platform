#!/usr/bin/env bash

function lk_jq() {
    jq -L"$LK_BASE/lib"/{jq,json} "$@"
}

# lk_jq_var <JQ_ARG...> -- <VAR...>
#
# Run jq with the value of each VAR passed to the jq filter as a variable with
# the equivalent camelCase name.
#
# Example:
#
#     $ lk_jq_var -n '{$bashVersion,path:$path|split(":")}' -- BASH_VERSION PATH
#     {
#       "bashVersion": "5.1.16(1)-release",
#       "path": [
#         "/usr/local/bin",
#         "/usr/local/sbin",
#         "/usr/bin",
#         "/bin",
#         "/usr/sbin",
#         "/sbin"
#       ]
#     }
function lk_jq_var() {
    local _ARGS=() _VAR _ARG _CMD=()
    while [[ $# -gt 0 ]]; do
        [[ $1 == -- ]] || { _ARGS[${#_ARGS[@]}]=$1 && shift && continue; }
        shift && break
    done
    while IFS=$'\t' read -r _VAR _ARG; do
        _CMD+=(--arg "$_ARG" "${!_VAR-}")
    done < <(((!$#)) || printf '%s\n' "$@" | awk -F_ '
{ l = $0; sub("^_+", ""); v = tolower($1)
  for(i = 2; i <= NF; i++)
    { v = v toupper(substr($i,1,1)) tolower(substr($i,2)) }
  print l "\t" v }')
    lk_jq ${_CMD+"${_CMD[@]}"} ${_ARGS+"${_ARGS[@]}"}
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

# lk_json_bool VAR
#
# Print "true" if VAR or ${!VAR} is truthy, otherwise print "false".
function lk_json_bool() {
    lk_is_true "$1" && echo "true" || echo "false"
}

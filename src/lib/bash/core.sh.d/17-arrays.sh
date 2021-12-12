#!/bin/bash

# lk_arr [-COMMAND] [ARRAY...]
function lk_arr() {
    local _CMD="printf '%s\n'" _sh _SH=
    [[ ${1-} != -* ]] || { _CMD=${1#-} && shift; }
    while [ $# -gt 0 ]; do
        _sh=" \"\${$1[@]}\""
        _SH+=${!1+$_sh}
        shift
    done
    # Print nothing if no array members were found
    [ -z "${_SH:+1}" ] || eval "$_CMD$_SH"
}

# lk_quote_arr [ARRAY...]
function lk_quote_arr() {
    lk_arr -lk_quote_args "$@"
}

# lk_implode_arr GLUE [ARRAY...]
function lk_implode_arr() {
    local IFS
    unset IFS
    lk_arr "${@:2}" | lk_implode_input "$1"
}

# lk_ere_implode_arr [-e] [ARRAY...]
function lk_ere_implode_arr() {
    local ARGS
    [ "${1-}" != -e ] || { ARGS=(-e) && shift; }
    lk_arr "$@" | lk_ere_implode_input ${ARGS+"${ARGS[@]}"}
}

# lk_arr_remove ARRAY VALUE
function lk_arr_remove() {
    local _SH
    _SH=$(eval "for _i in \${$1+\"\${!$1[@]}\"}; do
    [ \"\${$1[_i]}\" != \"\$2\" ] || echo \"unset \\\"$1[\$_i]\\\"\"
done") && eval "$_SH"
}

#### Reviewed: 2021-11-16

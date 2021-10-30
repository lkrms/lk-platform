#!/bin/bash

# lk_arr [ARRAY...]
function lk_arr() {
    local _sh _SH=
    while [ $# -gt 0 ]; do
        _sh=" \"\${$1[@]}\""
        _SH+=${!1+$_sh}
        shift
    done
    # Print nothing if no array members were found
    [ -z "${_SH:+1}" ] || eval "printf '%s\n'$_SH"
}

# lk_implode_arr GLUE [ARRAY_NAME...]
function lk_implode_arr() {
    local IFS
    unset IFS
    lk_arr "${@:2}" | lk_implode_input "$1"
}

# lk_array_remove_value ARRAY VALUE
function lk_array_remove_value() {
    local _SH
    _SH=$(eval "for _i in \${$1+\"\${!$1[@]}\"}; do
    [ \"\${$1[_i]}\" != \"\$2\" ] || echo \"unset \\\"$1[\$_i]\\\"\"
done") && eval "$_SH"
}

#### Reviewed: 2021-10-21

#!/bin/bash

# lk_arr [ARRAY...]
function lk_arr() {
    local _SH _i=0
    _SH="printf '%s\n'"
    while [ $# -gt 0 ]; do
        # Count array members until one is found
        ((_i)) || eval "\${$1+let _i+=\${#$1[@]}}"
        ((!_i)) || _SH+=" \${$1+\"\${$1[@]}\"}"
        shift
    done
    # Print nothing if no array members were found
    ((!_i)) || eval "$_SH"
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

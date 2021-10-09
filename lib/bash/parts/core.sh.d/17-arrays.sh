#!/bin/bash

# lk_arr [ARRAY...]
function lk_arr() {
    local SH i=0
    SH="printf '%s\n'"
    while [ $# -gt 0 ]; do
        # Count array members until one is found
        ((i)) || eval "\${$1+let i+=\${#$1[@]}}"
        ((!i)) || SH+=" \${$1+\"\${$1[@]}\"}"
        shift
    done
    # Print nothing if no array members were found
    ((!i)) || eval "$SH"
}

# lk_array_remove_value ARRAY VALUE
function lk_array_remove_value() {
    local _SH
    _SH=$(eval "for _i in \${$1+\"\${!$1[@]}\"}; do
    [ \"\${$1[_i]}\" != \"\$2\" ] || echo \"unset \\\"$1[\$_i]\\\"\"
done") && eval "$_SH"
}

#### Reviewed: 2021-10-09

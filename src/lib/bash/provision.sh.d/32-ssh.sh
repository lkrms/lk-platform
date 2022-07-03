#!/bin/bash

# lk_ssh_host_parameter_sh [USER@]<HOST>[:PORT] <VAR_PREFIX> [PARAMETER...]
#
# Always included: user, hostname, port, identityfile
function lk_ssh_host_parameter_sh() {
    [[ ${1-} =~ ^(^([^@]+)@)?([^@:]+)(:([0-9]+))?$ ]] || return
    local user=${BASH_REMATCH[2]} host=${BASH_REMATCH[3]} \
        port=${BASH_REMATCH[5]} PREFIX=${2-} AWK
    shift 2 &&
        lk_awk_load AWK sh-get-ssh-host-parameters || return
    ssh -G ${port:+-p "$port"} "${user:+$user@}$host" |
        awk -v prefix="$PREFIX" -f "$AWK" "$@"
}

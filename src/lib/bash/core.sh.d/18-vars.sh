#!/bin/bash

# lk_var_sh [-f] [VAR...]
#
# Print a variable assignment statement for each declared VAR. If -f is set, it
# is passed to `lk_double_quote`.
function lk_var_sh() {
    local FORCE
    unset FORCE
    [ "${1-}" != -f ] || { FORCE= && shift; }
    while [ $# -gt 0 ]; do
        [ -z "${!1+1}" ] ||
            printf '%s=%s\n' "$1" "$(lk_double_quote ${FORCE+-f} "${!1-}")"
        shift
    done
}

# lk_var_sh_q [VAR...]
#
# Print Bash-compatible assignment statements for each VAR, including any
# that are undeclared.
function lk_var_sh_q() {
    while [ $# -gt 0 ]; do
        if [ -n "${!1:+1}" ]; then
            printf 'declare %s=%q\n' "$1" "${!1}"
        else
            printf 'declare %s=\n' "$1"
        fi
        shift
    done
}

# lk_var_env VAR
#
# Print the original value of VAR if it was in the environment when Bash was
# invoked. Requires `_LK_ENV=$(declare -x)` at or near the top of the script.
function lk_var_env() { (
    [ -n "${_LK_ENV+1}" ] || lk_warn "_LK_ENV not set" || return
    unset "$1" || return
    eval "$_LK_ENV" 2>/dev/null || true
    declare -p "$1" 2>/dev/null |
        awk 'NR == 1 && $2 ~ "x"' | grep . >/dev/null && echo "${!1-}"
); }

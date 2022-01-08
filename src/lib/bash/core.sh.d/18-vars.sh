#!/bin/bash

# _lk_var [STACK_DEPTH]
#
# Print 'declare ' if the command that called the caller belongs to a function.
# In this context, declarations printed for `eval` should create local variables
# rather than globals.
function _lk_var() {
    local DEPTH=${1:-0} _LK_STACK_DEPTH=${_LK_STACK_DEPTH:-0}
    ((DEPTH += _LK_STACK_DEPTH, _LK_STACK_DEPTH < 0 || DEPTH < 0)) ||
        [[ ${FUNCNAME[DEPTH + 2]-} =~ ^(^|source|main)$ ]] ||
        printf 'declare '
}

# lk_var_sh [-a] [VAR...]
#
# Print a variable assignment statement for each declared VAR. If -a is set,
# include undeclared variables.
function lk_var_sh() {
    local ALL=0
    [ "${1-}" != -a ] || { ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        if [ -n "${!1+1}" ]; then
            printf '%s=%s\n' "$1" "$(lk_double_quote "${!1-}")"
        elif ((ALL)); then
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_var_sh_q [-a] [VAR...]
#
# Print Bash-compatible assignment statements for each declared VAR. If -a is
# set, include undeclared variables.
function lk_var_sh_q() {
    local ALL=0
    [ "${1-}" != -a ] || { ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        _lk_var
        if [ -n "${!1:+1}" ]; then
            printf '%s=%q\n' "$1" "${!1}"
        elif ((ALL)) || [ -n "${!1+1}" ]; then
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_var_env VAR
#
# Print the original value of VAR if it was in the environment when Bash was
# invoked. Requires `_LK_ENV=$(declare -x)` at or near the top of the script.
function lk_var_env() { (
    [ -n "${_LK_ENV+1}" ] || lk_err "_LK_ENV not set" || return
    unset "$1" || return
    eval "$_LK_ENV" 2>/dev/null || true
    declare -p "$1" 2>/dev/null |
        awk 'NR == 1 && $2 ~ "x"' | grep . >/dev/null && echo "${!1-}"
); }

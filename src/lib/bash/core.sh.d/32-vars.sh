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
    local __ALL=0
    [ "${1-}" != -a ] || { __ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        if [ -n "${!1+1}" ]; then
            printf '%s=%s\n' "$1" "$(lk_double_quote "${!1-}")"
        elif ((__ALL)); then
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
    local __ALL=0
    [ "${1-}" != -a ] || { __ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        _lk_var
        if lk_var_array "$1"; then
            printf '%s=(%s)\n' "$1" "$(lk_quote_arr "$1")"
        elif [ -n "${!1:+1}" ]; then
            printf '%s=%q\n' "$1" "${!1}"
        elif ((__ALL)) || [ -n "${!1+1}" ]; then
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

function lk_var_has_attr() {
    local REGEX="^declare -$NS*$2"
    [[ $(declare -p "$1" 2>/dev/null) =~ $REGEX ]]
}

function lk_var_declared() {
    declare -p "$1" &>/dev/null
}

function lk_var_array() {
    lk_var_has_attr "$1" a
}

function lk_var_exported() {
    lk_var_has_attr "$1" x
}

function lk_var_readonly() {
    lk_var_has_attr "$1" r
}

# lk_var_not_null VAR...
#
# Return false if any VAR is unset or set to the empty string.
function lk_var_not_null() {
    while [ $# -gt 0 ]; do
        [ -n "${!1:+1}" ] || return
        shift
    done
}

# lk_var_to_bool VAR [TRUE FALSE]
#
# If the value of VAR is 'Y', 'yes', '1', 'true' or 'on' (not case-sensitive),
# assign TRUE (default: Y) to VAR, otherwise assign FALSE (default: N).
function lk_var_to_bool() {
    [ $# -eq 3 ] || set -- "$1" Y N
    if lk_true "$1"; then
        eval "$1=\$2"
    else
        eval "$1=\$3"
    fi
}

# lk_var_to_int VAR [NULL]
#
# Convert the value of VAR to an integer. If VAR is unset, empty or invalid,
# assign NULL (default: 0).
function lk_var_to_int() {
    [ $# -eq 2 ] || set -- "$1" 0
    [[ ! ${!1-} =~ ^(-)?0*([0-9]+)(\.[0-9]*)?$ ]] ||
        set -- "$1" "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    eval "$1=\$2"
}

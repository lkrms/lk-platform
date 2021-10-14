#!/bin/bash

# lk_no_input
#
# Return true if user input should not be requested.
function lk_no_input() {
    if [ "${LK_FORCE_INPUT-}" = 1 ]; then
        { [ -t 0 ] || lk_err "/dev/stdin is not a terminal"; } && false
    else
        [ ! -t 0 ] || [ "${LK_NO_INPUT-}" = 1 ]
    fi
}

#### /*
# lk_vars_not_empty [-q] VAR...
#
# Print a warning and return false if any VAR is empty or unset. If -q is set,
# suppress output.
function lk_vars_not_empty() {
    local QUIET EMPTY=()
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    while [ $# -gt 0 ]; do
        [ -n "${!1:+1}" ] || EMPTY[${#EMPTY[@]}]=$1
        shift
    done
    [ -z "${EMPTY+1}" ] || {
        [ -n "${QUIET-}" ] || {
            local IFS=' ' _LK_STACK_DEPTH=1
            lk_err "$(lk_plural EMPTY value values) required: ${EMPTY[*]}"
        }
        false
    }
}
#### */

#### Reviewed: 2021-10-14

#!/bin/bash

# lk_vars_not_empty [-q] VAR...
#
# Print a warning and return false if any VAR is empty or unset. If -q is set,
# suppress output.
function lk_vars_not_empty() {
    local q e=()
    [ "${1-}" != -q ] || { q=1 && shift; }
    while [ $# -gt 0 ]; do
        [ -n "${!1:+1}" ] || e[${#e[@]}]=$1
        shift
    done
    [ -z "${e+1}" ] || {
        [ -n "${q-}" ] || {
            local IFS=' ' _LK_STACK_DEPTH=1
            lk_err "$(lk_plural e value values) required: ${e[*]}"
        }
        false
    }
}

#### Reviewed: 2021-09-27

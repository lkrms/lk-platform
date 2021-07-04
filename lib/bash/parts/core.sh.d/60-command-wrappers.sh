#!/bin/bash

# lk_require_output [-q] COMMAND [ARG...]
#
# Return true if COMMAND writes output other than newlines and exits without
# error. If -q is set, suppress output.
function lk_require_output() {
    local QUIET FILE
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    FILE=$(lk_mktemp_file) && lk_delete_on_exit "$FILE" &&
        if [ -z "${QUIET-}" ]; then
            "$@" | tee "$FILE"
        else
            "$@" >"$FILE"
        fi &&
        grep -Eq '^.+$' "$FILE" || return
}

# lk_env_clean COMMAND [ARG...]
#
# Remove _LK_* variables from the environment of COMMAND.
function lk_env_clean() {
    local _UNSET=("${!_LK_@}")
    if [ -n "${_UNSET+1}" ]; then
        env "${_UNSET[@]/#/--unset=}" "$@"
    else
        "$@"
    fi
}

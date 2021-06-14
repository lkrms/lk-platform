#!/bin/bash

# lk_require_output [-q] COMMAND [ARG...]
#
# Return true if COMMAND writes output other than newlines and exits without
# error. If -q is set, suppress output.
function lk_require_output() {
    local QUIET FD STATUS=0
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    [ -n "${QUIET-}" ] ||
        { FD=$(lk_fd_next) && eval "exec $FD>&1"; } || return
    if [ -n "${FD-}" ]; then
        "$@" | tee "/dev/fd/$FD"
    else
        "$@"
    fi | grep -E '^.+$' >/dev/null || STATUS=$?
    [ -z "${FD-}" ] ||
        eval "exec $FD>&-" || return
    return "$STATUS"
}

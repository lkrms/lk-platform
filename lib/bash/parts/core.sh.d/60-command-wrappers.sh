#!/bin/bash

# lk_keep_trying COMMAND [ARG...]
#
# Execute COMMAND until its exit status is zero or 10 attempts have been made.
# The delay between each attempt starts at 1 second and follows the Fibonnaci
# sequence (2 sec, 3 sec, 5 sec, 8 sec, 13 sec, etc.).
function lk_keep_trying() {
    local MAX_ATTEMPTS=${LK_KEEP_TRYING_MAX:-10} \
        ATTEMPT=0 WAIT=1 LAST_WAIT=1 NEW_WAIT EXIT_STATUS
    if ! "$@"; then
        while ((++ATTEMPT < MAX_ATTEMPTS)); do
            lk_console_log \
                "Command failed (attempt $ATTEMPT of $MAX_ATTEMPTS):" "$*"
            lk_console_detail \
                "Trying again in $WAIT $(lk_plural $WAIT second seconds)"
            sleep "$WAIT"
            ((NEW_WAIT = WAIT + LAST_WAIT, LAST_WAIT = WAIT, WAIT = NEW_WAIT))
            lk_console_blank
            if "$@"; then
                return 0
            else
                EXIT_STATUS=$?
            fi
        done
        return "$EXIT_STATUS"
    fi
}

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

# lk_mktemp_with VAR COMMAND [ARG...]
#
# Set VAR to the name of a temporary file that contains the output of COMMAND.
function lk_mktemp_with() {
    [ $# -ge 2 ] || lk_usage "Usage: $FUNCNAME VAR COMMAND [ARG...]" || return
    local VAR=$1 _LK_STACK_DEPTH=$((${_LK_STACK_DEPTH:-0} + 1))
    eval "$VAR=\$(lk_mktemp_file)" &&
        lk_delete_on_exit "${!VAR}" &&
        "${@:2}" >"${!VAR}"
}

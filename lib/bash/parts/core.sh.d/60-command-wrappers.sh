#!/bin/bash

# lk_unbuffer [exec] COMMAND [ARG...]
#
# Run COMMAND with unbuffered input and line-buffered output (if supported by
# the command and platform).
function lk_unbuffer() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    case "$1" in
    sed | gsed | gnu_sed)
        set -- "$1" -u "${@:2}"
        ;;
    grep | ggrep | gnu_grep)
        set -- "$1" --line-buffered "${@:2}"
        ;;
    *)
        if [ "$1" = tr ] && lk_is_macos; then
            set -- "$1" -u "${@:2}"
        else
            # TODO: reinstate `unbuffer` when LF -> CRLF issue is resolved
            case "$(lk_command_first_existing stdbuf)" in
            unbuffer)
                set -- unbuffer -p "$@"
                ;;
            stdbuf)
                set -- stdbuf -i0 -oL -eL "$@"
                ;;
            esac
        fi
        ;;
    esac
    lk_maybe_sudo "$@"
}

# lk_tty [exec] COMMAND [ARG...]
#
# Run COMMAND in a pseudo-terminal to satisfy tty checks even if output is being
# redirected.
function lk_tty() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    if ! lk_is_macos; then
        SHELL=$BASH lk_maybe_sudo \
            script -q -f -e -c "$(lk_quote_args "$@")" /dev/null
    else
        lk_maybe_sudo \
            script -q -t 0 /dev/null "$@"
    fi
}

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
function lk_require_output() { (
    unset QUIET
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    FILE=$(lk_mktemp_file) && lk_delete_on_exit "$FILE" &&
        if [ -z "${QUIET-}" ]; then
            "$@" | tee "$FILE"
        else
            "$@" >"$FILE"
        fi &&
        grep -Eq '^.+$' "$FILE"
); }

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

# lk_mktemp_with VAR [COMMAND [ARG...]]
#
# Set VAR to the name of a temporary file that contains the output of COMMAND.
function lk_mktemp_with() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME VAR COMMAND [ARG...]" || return
    local _LK_STACK_DEPTH=1
    eval "$1=\$(lk_mktemp_file)" &&
        lk_delete_on_exit "${!1}" &&
        { [ $# -lt 2 ] || "${@:2}" >"${!1}"; }
}

#### Reviewed: 2021-08-28

#!/bin/bash

# lk_tty [exec] COMMAND [ARG...]
#
# Run COMMAND in a pseudo-terminal to satisfy tty checks even if output is being
# redirected.
function lk_tty() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    if ! lk_is_macos; then
        SHELL=$BASH lk_sudo \
            script -q -f -e -c "$(lk_quote_args "$@")" /dev/null
    else
        lk_sudo \
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

# lk_mktemp_with [-c] VAR [COMMAND [ARG...]]
#
# Set VAR to the name of a new temporary file that optionally contains the
# output of COMMAND. If -c is specified, do nothing if VAR is already set to the
# path of an existing file.
function lk_mktemp_with() {
    local IFS _CACHE
    [ "${1-}" != -c ] || { _CACHE=1 && shift; }
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME [-c] VAR [COMMAND [ARG...]]" || return
    [ -z "${_CACHE-}" ] || [ ! -f "${!1-}" ] || return 0
    local _VAR=$1 _LK_STACK_DEPTH=1
    shift
    eval "$_VAR=\$(lk_mktemp_file)" &&
        lk_delete_on_exit "${!_VAR}" &&
        { [ $# -eq 0 ] || "$@" >"${!_VAR}"; }
}

# lk_mktemp_dir_with [-c] VAR [COMMAND [ARG...]]
#
# Set VAR to the name of a new temporary directory and optionally use it as the
# working directory to run COMMAND. If -c is specified, do nothing if VAR is
# already set to the path of an existing directory.
function lk_mktemp_dir_with() {
    local IFS _CACHE
    [ "${1-}" != -c ] || { _CACHE=1 && shift; }
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME [-c] VAR [COMMAND [ARG...]]" || return
    [ -z "${_CACHE-}" ] || [ ! -d "${!1-}" ] || return 0
    local _VAR=$1 _LK_STACK_DEPTH=1
    shift
    eval "$_VAR=\$(lk_mktemp_dir)" &&
        lk_delete_on_exit "${!_VAR}" &&
        { [ $# -eq 0 ] || (cd "${!_VAR}" && "$@"); }
}

#### Other command wrappers:
#### - lk_pass
#### - lk_elevate
#### - lk_sudo
#### - lk_unbuffer
#### - lk_maybe
#### - lk_git_with_repos
#### - _lk_apt_flock

#### Reviewed: 2021-08-28

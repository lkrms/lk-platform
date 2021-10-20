#!/bin/bash

# lk_report_error [-q] COMMAND [ARG...]
#
# Run COMMAND and print an error message if it exits non-zero. If -q is set,
# discard output to stderr unless COMMAND fails.
function lk_report_error() {
    local QUIET STDERR
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    if [ -n "${QUIET-}" ]; then
        lk_mktemp_with STDERR || return
        "$@" 2>"$STDERR"
    else
        "$@"
    fi || {
        local STATUS=$? IFS=' '
        [ ! -s "${STDERR-}" ] || cat "$STDERR" >&2
        lk_console_error "Exit status $STATUS:" "$*"
        return $STATUS
    }
}

# lk_faketty [exec] COMMAND [ARG...]
#
# Run COMMAND in a pseudo-terminal to satisfy tty checks even if output is being
# redirected.
function lk_faketty() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    if ! lk_is_macos; then
        SHELL=$BASH lk_sudo script -qfec "$(lk_quote_args "$@")" /dev/null
    else
        lk_sudo script -qt 0 /dev/null "$@"
    fi
}

# lk_keep_trying [-MAX_ATTEMPTS] COMMAND [ARG...]
#
# Execute COMMAND until its exit status is zero or MAX_ATTEMPTS have been made
# (default: 10). The delay between each attempt starts at 1 second and follows
# the Fibonnaci sequence (2 sec, 3 sec, 5 sec, 8 sec, 13 sec, etc.).
function lk_keep_trying() {
    local i=0 MAX_ATTEMPTS=10 WAIT=1 PREV=1 NEXT _IFS=${IFS-$' \t\n'}
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { MAX_ATTEMPTS=${1:1} && shift; }
    while :; do
        "$@" && return 0 || {
            local STATUS=$? IFS=' '
            ((++i < MAX_ATTEMPTS)) || break
            lk_console_log "Failed (attempt $i of $MAX_ATTEMPTS):" "$*"
            lk_tty_detail "Trying again in $(lk_plural -v $WAIT second)"
            sleep "$WAIT"
            ((NEXT = WAIT + PREV, PREV = WAIT, WAIT = NEXT))
            lk_tty_print
            IFS=$_IFS
        }
    done
    return $STATUS
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

# lk_mktemp_with [-c|-r] VAR [COMMAND [ARG...]]
#
# Set VAR to the name of a new temporary file that optionally contains the
# output of COMMAND. If VAR is already set to the path of an existing file:
# - do nothing if -c ("cache") is set, or
# - proceed without creating a new file if -r ("reuse") is set.
function lk_mktemp_with() {
    local IFS _CACHE _REUSE
    { [ "${1-}" = -c ] && _CACHE=1 && shift; } ||
        { [ "${1-}" = -r ] && _REUSE=1 && shift; } || true
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME [-c|-r] VAR [COMMAND [ARG...]]" || return
    [ -z "${_CACHE-}" ] || [ ! -f "${!1-}" ] || return 0
    local _VAR=$1 _LK_STACK_DEPTH=1
    shift
    [ -n "${_REUSE-}" ] && [ -f "${!1-}" ] ||
        { eval "$_VAR=\$(lk_mktemp_file)" &&
            lk_delete_on_exit "${!_VAR}"; } || return
    { [ $# -eq 0 ] || "$@" >"${!_VAR}"; }
}

# lk_mktemp_dir_with [-c] VAR [COMMAND [ARG...]]
#
# Set VAR to the name of a new temporary directory and optionally use it as the
# working directory to run COMMAND. If -c ("cache") is set, do nothing if VAR
# already contains the path of an existing directory.
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

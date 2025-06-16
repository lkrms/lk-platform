#!/usr/bin/env bash

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

. "$LK_BASE/lib/bash/common.sh"

LK_USAGE="\
Usage: ${0##*/} WAIT COMMAND [ARG...]

Run the given command for up to WAIT seconds before killing it."

[ $# -ge 2 ] || lk_usage

function _lk_timeout_trap() {
    local RUNNING=
    if [ "${_LK_TIMEOUT_TIMER_PID:+1}${_LK_TIMEOUT_CMD_PID:+1}" = 11 ]; then
        ! lk_check_pid "$_LK_TIMEOUT_TIMER_PID" || RUNNING=t
        ! lk_check_pid "$_LK_TIMEOUT_CMD_PID" || RUNNING+=c
        case "$RUNNING" in
        t)
            # The command returned before timing out, so kill the timer process
            kill "$_LK_TIMEOUT_TIMER_PID" 2>/dev/null || true
            ! lk_verbose 2 ||
                echo "Timer process killed: $_LK_TIMEOUT_TIMER_PID" \
                    >&"${_LK_FD-2}"
            ;;
        c)
            # The command timed out, so kill it
            kill "$_LK_TIMEOUT_CMD_PID" 2>/dev/null || true
            ! lk_verbose 2 ||
                echo "Process killed after timing out: $_LK_TIMEOUT_CMD_PID" \
                    >&"${_LK_FD-2}"
            ;;
        tc)
            ! lk_verbose 2 ||
                echo "SIGCHLD trapped for an unknown process" >&"${_LK_FD-2}"
            return 0
            ;;
        esac
    fi
}

STATUS=0
trap _lk_timeout_trap SIGCHLD

{
    sleep "$1" &
    _LK_TIMEOUT_TIMER_PID=$!

    "${@:2}" &
    _LK_TIMEOUT_CMD_PID=$!

    wait "$_LK_TIMEOUT_CMD_PID" || STATUS=$?

    wait "$_LK_TIMEOUT_TIMER_PID" || true

    trap - SIGCHLD

    (exit "$STATUS") || lk_die ""
}

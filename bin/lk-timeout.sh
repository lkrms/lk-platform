#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit

LK_USAGE="\
Usage: ${0##*/} SECONDS COMMAND [ARG...]

Run the given command for up to SECONDS before killing it."

[ $# -ge 2 ] || lk_usage

function _lk_timeout_trap() {
    local TIMER_STATE CMD_STATE
    if [ "${_LK_TIMEOUT_TIMER_PID:+1}${_LK_TIMEOUT_CMD_PID:+1}" = 11 ]; then
        lk_check_pid "$_LK_TIMEOUT_TIMER_PID" && TIMER_STATE=1 || TIMER_STATE=
        lk_check_pid "$_LK_TIMEOUT_CMD_PID" && CMD_STATE=2 || CMD_STATE=
        case "$TIMER_STATE$CMD_STATE" in
        1)
            # The command returned before timing out, so kill the timer process
            kill "$_LK_TIMEOUT_TIMER_PID" 2>/dev/null || true
            ! lk_verbose 2 ||
                echo "Timer process killed: $_LK_TIMEOUT_TIMER_PID" \
                    >&"${_LK_FD:-2}"
            ;;
        2)
            # The command timed out, so kill it
            kill "$_LK_TIMEOUT_CMD_PID" 2>/dev/null || true
            ! lk_verbose 2 ||
                echo "Process killed after timing out: $_LK_TIMEOUT_CMD_PID" \
                    >&"${_LK_FD:-2}"
            ;;
        12)
            ! lk_verbose 2 ||
                echo "SIGCHLD trapped for an unknown process" >&"${_LK_FD:-2}"
            return 0
            ;;
        esac
    fi
}

EXIT_STATUS=0
trap _lk_timeout_trap SIGCHLD
sleep "$1" &
_LK_TIMEOUT_TIMER_PID=$!
"${@:2}" &
_LK_TIMEOUT_CMD_PID=$!
wait "$_LK_TIMEOUT_CMD_PID" || EXIT_STATUS=$?
wait "$_LK_TIMEOUT_TIMER_PID" || true
trap - SIGCHLD
exit "$EXIT_STATUS"

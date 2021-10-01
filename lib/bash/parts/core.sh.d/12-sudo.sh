#!/bin/bash

# lk_elevate [exec] [COMMAND [ARG...]]
#
# If Bash is running as root, run COMMAND, otherwise use `sudo` to run it as the
# root user. If COMMAND is not found in PATH and is a function, run it with
# LK_SUDO set. If no COMMAND is specified and Bash is not running as root, run
# the current script, with its original arguments, as the root user.
function lk_elevate() {
    local COMMAND
    [ "${1-}" != exec ] || { local LK_EXEC=1 && shift; }
    if [ "$EUID" -eq 0 ]; then
        [ $# -eq 0 ] ||
            ${LK_EXEC:+exec} "$@"
    elif [ $# -eq 0 ]; then
        ${LK_EXEC:+exec} sudo -H "$0" ${_LK_ARGV+"${_LK_ARGV[@]}"}
    elif ! COMMAND=$(type -P "$1") && [ "$(type -t "$1")" = "function" ]; then
        local LK_SUDO=1
        "$@"
    elif [ -n "$COMMAND" ]; then
        # Use `shift` and "$@" because Bash 3.2 expands "${@:2}" to the
        # equivalent of `IFS=" "; echo "${*:2}"` unless there is a space in IFS
        shift
        ${LK_EXEC:+exec} sudo -H "$COMMAND" "$@"
    else
        lk_err "invalid command: $1"
        false
    fi
}

# lk_sudo [exec] COMMAND [ARG...]
#
# If Bash is running as root or LK_SUDO is empty or unset, run COMMAND,
# otherwise use `sudo` to run it as the root user.
function lk_sudo() {
    if [ -n "${LK_SUDO-}" ]; then
        lk_elevate "$@"
    else
        [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
        ${LK_EXEC:+exec} "$@"
    fi
}

# lk_will_elevate
#
# Return true if commands invoked with lk_sudo will run as the root user, even
# if sudo will not be used.
function lk_will_elevate() {
    [ "$EUID" -eq 0 ] || [ -n "${LK_SUDO-}" ]
}

# lk_will_sudo
#
# Return true if sudo will be used to run commands invoked with lk_sudo. Return
# false if Bash is already running with root privileges or LK_SUDO is not set.
function lk_will_sudo() {
    [ "$EUID" -ne 0 ] && [ -n "${LK_SUDO-}" ]
}

#### Reviewed: 2021-10-07

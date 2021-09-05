#!/bin/bash

# lk_elevate [exec] [COMMAND [ARG...]]
#
# Use sudo to run COMMAND as the root user if Bash is not already running with
# root privileges, otherwise run COMMAND without sudo. If COMMAND is not found
# in PATH and is a function, run it with LK_SUDO=1.
function lk_elevate() {
    local c
    [ "${1-}" != exec ] || { local LK_EXEC=1 && shift; }
    if [ "$EUID" -eq 0 ]; then
        [ $# -eq 0 ] ||
            ${LK_EXEC:+exec} "$@"
    elif [ $# -eq 0 ]; then
        ${LK_EXEC:+exec} sudo -H "$0" ${_LK_ARGV+"${_LK_ARGV[@]}"}
    elif ! c=$(type -P "$1") && [ "$(type -t "$1")" = "function" ]; then
        local LK_SUDO=1
        "$@"
    elif [ -n "$c" ]; then
        ${LK_EXEC:+exec} sudo -H "$c" "${@:2}"
    else
        lk_err "invalid command: $1"
    fi
}

# lk_sudo [exec] COMMAND [ARG...]
#
# Use sudo to run COMMAND as the root user if:
# - the LK_SUDO variable is set and is not the empty string
# - Bash is not already running with root privileges
# Otherwise run COMMAND without sudo.
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

#### Reviewed: 2021-09-06

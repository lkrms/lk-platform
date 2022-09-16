#!/bin/bash

function _lk_sudo_check() {
    local LK_SUDO_ON_FAIL=${LK_SUDO_ON_FAIL-} LK_EXEC=${LK_EXEC-} SHIFT=0 \
        _LK_STACK_DEPTH=1
    [ "${1-}" != -f ] || { LK_SUDO_ON_FAIL=1 && ((++SHIFT)) && shift; }
    [ "${1-}" != exec ] || { LK_EXEC=1 && ((++SHIFT)) && shift; }
    [ "${LK_EXEC:+e}${LK_SUDO_ON_FAIL:+f}" != ef ] ||
        lk_err "LK_EXEC and LK_SUDO_ON_FAIL are mutually exclusive" || return
    [ -z "$LK_SUDO_ON_FAIL" ] || [ $# -gt 0 ] ||
        lk_err "command required if LK_SUDO_ON_FAIL is set" || return
    declare -p LK_EXEC LK_SUDO_ON_FAIL
    ((!SHIFT)) || printf 'shift %s\n' "$SHIFT"
}

# lk_elevate [-f] [exec] [COMMAND [ARG...]]
#
# If Bash is running as root, run COMMAND, otherwise use `sudo` to run it as the
# root user. If COMMAND is not found in PATH and is a function, run it with
# LK_SUDO set. If no COMMAND is specified and Bash is not running as root, run
# the current script, with its original arguments, as the root user. If -f is
# set, attempt without `sudo` first and only run as root if the first attempt
# fails.
function lk_elevate() {
    local _SH _COMMAND _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    _SH=$(_lk_sudo_check "$@") && eval "$_SH" || return
    if [ "$EUID" -eq 0 ]; then
        [ $# -eq 0 ] ||
            ${LK_EXEC:+exec} "$@"
    elif [ $# -eq 0 ]; then
        ${LK_EXEC:+exec} sudo -H "$0" ${_LK_ARGV+"${_LK_ARGV[@]}"}
    elif ! _COMMAND=$(type -P "$1") && [ "$(type -t "$1")" = "function" ]; then
        LK_SUDO=
        if [ -n "$LK_SUDO_ON_FAIL" ] && "$@" 2>/dev/null; then
            return 0
        fi
        LK_SUDO=1
        "$@"
    elif [ -n "$_COMMAND" ]; then
        shift
        if [ -n "$LK_SUDO_ON_FAIL" ] && "$_COMMAND" "$@" 2>/dev/null; then
            return 0
        fi
        ${LK_EXEC:+exec} sudo -H "$_COMMAND" "$@"
    else
        lk_err "invalid command: $1"
        false
    fi
}

# lk_sudo [-f] [exec] COMMAND [ARG...]
#
# If Bash is running as root or LK_SUDO is empty or unset, run COMMAND,
# otherwise use `sudo` to run it as the root user. If -f is set and `sudo` will
# be used, attempt without `sudo` first and only run as root if the first
# attempt fails.
function lk_sudo() {
    local _SH _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    _SH=$(_lk_sudo_check "$@") && eval "$_SH" || return
    if [ -n "${LK_SUDO-}" ]; then
        lk_elevate "$@"
    else
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

# lk_sudo_on_fail COMMAND [ARG...]
#
# If `lk_sudo COMMAND` would invoke `sudo COMMAND`:
# 1. Run `COMMAND` without sudo, redirecting any error output to /dev/null
# 2. If COMMAND fails, run `sudo COMMAND`
#
# If `lk_sudo COMMAND` would invoke `COMMAND` without sudo:
# 1. Run `COMMAND` without sudo
function lk_sudo_on_fail() {
    if lk_will_sudo; then
        "$@" 2>/dev/null || sudo -H "$@"
    else
        "$@"
    fi
}

# lk_can_sudo COMMAND
#
# Return true if the current user has permission to run COMMAND via sudo,
# prompting for a password unless the current user:
# - matches a NOPASSWD entry in sudoers;
# - doesn't match any entries in sudoers; or
# - authenticated with sudo in the current terminal less than 5 minutes ago.
#
# Returns false if LK_NO_INPUT is set and sudo can't check the security policy
# without asking the user to authenticate.
function lk_can_sudo() {
    [[ -n ${1-} ]] || lk_err "invalid arguments" || return
    if lk_no_input; then
        sudo -nl "$1" &>/dev/null
    else
        # Return without allowing sudo to prompt for a password if the user has
        # no matching sudoers entries ("sudo: a password is required" indicates
        # the user can sudo)
        LC_ALL=C sudo -nv 2>&1 | grep -i password >/dev/null ||
            [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == *0* ]] || return
        sudo -l "$1" >/dev/null
    fi
}

# lk_run_as USER COMMAND [ARG...]
#
# Use `runuser` or `sudo` to run COMMAND as USER. If USER is empty or "-", use
# `lk_sudo` to run the command instead.
function lk_run_as() {
    [[ $# -ge 2 ]] || lk_err "invalid arguments" || return
    [[ ${1:--} != - ]] || {
        shift
        lk_sudo "$@"
        return
    }
    local _USER
    _USER=$(id -u "$1" 2>/dev/null) || lk_err "user not found: $1" || return
    shift
    if [[ $EUID -eq $_USER ]]; then
        "$@"
    elif lk_is_linux; then
        _USER=$(id -un "$_USER")
        lk_elevate runuser -u "$_USER" -- "$@"
    else
        sudo -u "#$_USER" -- "$@"
    fi
}

#### Reviewed: 2021-10-24

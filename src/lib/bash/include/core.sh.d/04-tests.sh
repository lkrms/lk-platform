#!/usr/bin/env bash

# lk_is_true <value>
#
# Check if a value, or the variable it references, is 'Y', 'yes', '1', 'true',
# or 'on'. Not case-sensitive.
function lk_is_true() {
    (($#)) || lk_bad_args || return
    # Work around Bash IDE not parsing extglob syntax properly
    eval '[[ $1 == @([yY]?([eE][sS])|1|[tT][rR][uU][eE]|[oO][nN]) ]]' ||
        eval '[[ ${!1-} == @([yY]?([eE][sS])|1|[tT][rR][uU][eE]|[oO][nN]) ]]' 2>/dev/null
}

# lk_is_false <value>
#
# Check if a value, or the variable it references, is 'N', 'no', '0', 'false',
# or 'off'. Not case-sensitive.
function lk_is_false() {
    (($#)) || lk_bad_args || return
    # Work around Bash IDE not parsing extglob syntax properly
    eval '[[ $1 == @([nN]?([oO])|0|[fF][aA][lL][sS][eE]|[oO][fF][fF]) ]]' ||
        eval '[[ ${!1-} == @([nN]?([oO])|0|[fF][aA][lL][sS][eE]|[oO][fF][fF]) ]]' 2>/dev/null
}

# lk_test_all "<command> [<arg>...]" <value>...
#
# Check if all of the given values pass an IFS-delimited test command.
function lk_test_all() {
    (($# > 1)) || return
    local cmd
    read -ra cmd <<<"$1"
    shift
    while (($#)); do
        "${cmd[@]}" "$1" || break
        shift
    done
    ((!$#))
}

# lk_test_any "<command> [<arg>...]" <value>...
#
# Check if any of the given values pass an IFS-delimited test command.
function lk_test_any() {
    (($# > 1)) || return
    local cmd
    read -ra cmd <<<"$1"
    shift
    while (($#)); do
        ! "${cmd[@]}" "$1" || break
        shift
    done
    (($#))
}

# lk_debug_is_on
#
# Check if debugging is enabled via LK_DEBUG=Y.
function lk_debug_is_on() {
    [[ ${LK_DEBUG-} == Y ]]
}

# lk_input_is_off
#
# Check if user input prompts should be skipped.
#
# Fails if:
# - the standard input is connected to a terminal and LK_NO_INPUT is not Y, or
# - LK_FORCE_INPUT=Y
function lk_input_is_off() {
    if [[ ${LK_FORCE_INPUT-} == Y ]]; then
        [[ -t 0 ]] || lk_err "LK_FORCE_INPUT=Y but /dev/stdin is not a terminal" || return
        return 1
    fi
    [[ ${LK_NO_INPUT-} == Y ]] || [[ ! -t 0 ]]
}

# lk_is_dryrun
#
# Check if running in dry-run mode via LK_DRYRUN=Y (preferred) or LK_DRY_RUN=Y
# (deprecated).
function lk_is_dryrun() {
    [[ ${LK_DRYRUN-} == Y ]] || [[ ${LK_DRY_RUN-} == Y ]]
}

# lk_is_v [<minimum_verbosity>]
#
# Check if the level of output verbosity applied via LK_VERBOSE (0 if empty or
# unset) is greater than or equal to the given value (1 if not given).
function lk_is_v() {
    ((${LK_VERBOSE:-0} >= ${1-1}))
}

# lk_is_script
#
# Check if a script file is running.
#
# Fails if Bash is reading commands from:
# - the standard input (e.g. `bash -i` or `write_list | bash`)
# - a string (`bash -c "list"`), or
# - a named pipe (`bash <(write_list)`)
function lk_is_script() {
    [[ ${BASH_SOURCE+${BASH_SOURCE[*]: -1}} == "$0" ]] && [[ -f $0 ]]
}

# lk_bash_is <major_version> [<minor_version>]
#
# Check if running on a version of Bash greater than or equal to the given
# version.
function lk_bash_is() {
    case $# in
    0) lk_bad_args ;;
    1) ((BASH_VERSINFO[0] >= $1)) ;;
    *) ((BASH_VERSINFO[0] > $1 || (BASH_VERSINFO[0] == $1 && BASH_VERSINFO[1] >= $2))) ;;
    esac
}

# lk_version_is <installed_version> <minimum_version>
#
# Check if the installed version of an application is greater than or equal to
# the given minimum version.
function lk_version_is() {
    (($# == 2)) || lk_bad_args || return
    local latest
    latest=$(printf '%s\n' "$@" | sort -V | awk 'END { print }') &&
        [[ $latest == "$1" ]]
}

# lk_has [<command>...]
#
# Check if the given commands are executable disk files on the filesystem or in
# PATH.
function lk_has() {
    (($#)) || return
    while (($#)); do
        type -P "$1" >/dev/null || return
        shift
    done
}

# lk_system_is_linux
#
# Check if running on Linux.
function lk_system_is_linux() {
    [[ $OSTYPE == linux-gnu ]]
}

# lk_system_is_arch
#
# Check if running on Arch Linux.
function lk_system_is_arch() {
    lk_system_is_linux && [[ -f /etc/arch-release ]]
}

# lk_system_is_ubuntu
#
# Check if running on Ubuntu.
function lk_system_is_ubuntu() {
    lk_system_is_linux && [[ -f /etc/os-release ]] &&
        (. /etc/os-release && [[ $NAME == Ubuntu ]]) &>/dev/null
}

# lk_system_is_wsl
#
# Check if running on the Windows Subsystem for Linux.
function lk_system_is_wsl() {
    lk_system_is_linux &&
        { [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -d /run/WSL ]]; }
}

# lk_system_is_vm
#
# Check if running on a virtual machine.
function lk_system_is_vm() {
    lk_system_is_linux && awk -F '[ \t]*:[ \t]*' \
        '$1 == "flags" && $2 ~ /(^| )hypervisor( |$)/ { h = 1; exit } END { exit (1 - h) }' \
        /proc/cpuinfo
}

# lk_system_is_qemu
#
# Check if running on a QEMU virtual machine.
function lk_system_is_qemu() {
    lk_system_is_vm &&
        grep -Fxiq QEMU /sys/devices/virtual/dmi/id/*_vendor 2>/dev/null
}

# lk_system_is_macos
#
# Check if running on macOS.
function lk_system_is_macos() {
    [[ $OSTYPE == darwin* ]]
}

# lk_system_is_arm
#
# Check if running on an ARM processor.
function lk_system_is_arm() {
    [[ $MACHTYPE == @(arm|aarch)* ]]
}

# lk_system_is_apple_silicon [-t]
#
# Check if running on Apple Silicon:
# - natively, or
# - as a translated binary (if -t is given)
function lk_system_is_apple_silicon() {
    lk_system_is_macos && { lk_system_is_arm || {
        [[ ${1-} == -t ]] && [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) == 1 ]]
    }; }
}

# lk_user_is_root
#
# Check if running as root.
function lk_user_is_root() {
    ((!EUID))
}

# lk_test_all_e <file>...
#
# Check if every given file exists.
function lk_test_all_e() {
    lk_test_all "lk_sudo_on_fail test -e" "$@"
}

# lk_test_all_f <file>...
#
# Check if every given file exists and is a regular file.
function lk_test_all_f() {
    lk_test_all "lk_sudo_on_fail test -f" "$@"
}

# lk_test_all_d <file>...
#
# Check if every given file exists and is a directory.
function lk_test_all_d() {
    lk_test_all "lk_sudo_on_fail test -d" "$@"
}

# lk_test_all_s <file>...
#
# Check if every given file exists and has a size greater than zero.
function lk_test_all_s() {
    lk_test_all "lk_sudo_on_fail test -s" "$@"
}

#### Reviewed: 2025-12-03

#!/usr/bin/env bash

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

#### Reviewed: 2025-12-02

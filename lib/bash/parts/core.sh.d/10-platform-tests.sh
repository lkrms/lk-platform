#!/bin/bash

# lk_version_at_least INSTALLED MINIMUM
function lk_version_at_least() {
    local MIN
    MIN=$(printf '%s\n' "$@" | sort -V | head -n1) &&
        [ "$MIN" = "$2" ]
}

# lk_bash_at_least MAJOR [MINOR]
function lk_bash_at_least() {
    [ "${BASH_VERSINFO[0]}" -eq "$1" ] &&
        [ "${BASH_VERSINFO[1]}" -ge "${2:-0}" ] ||
        [ "${BASH_VERSINFO[0]}" -gt "$1" ]
}

function lk_command_exists() {
    type -P "$1" >/dev/null
}

function lk_is_arm() {
    [[ $MACHTYPE =~ ^(arm|aarch)64- ]]
}

function lk_is_macos() {
    [[ $OSTYPE == darwin* ]]
}

function lk_is_apple_silicon() {
    lk_is_macos && lk_is_arm
}

function lk_is_system_apple_silicon() {
    lk_is_macos && { lk_is_arm ||
        [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ]; }
}

function lk_is_linux() {
    [[ $OSTYPE == linux-gnu ]]
}

function lk_is_arch() {
    lk_is_linux && [ -f /etc/arch-release ]
}

function lk_is_ubuntu() {
    lk_is_linux && [ -r /etc/os-release ] &&
        (. /etc/os-release && [ "$NAME" = Ubuntu ])
}

function lk_ubuntu_at_least() {
    lk_is_linux && [ -r /etc/os-release ] &&
        (. /etc/os-release && [ "$NAME" = Ubuntu ] &&
            lk_version_at_least "$VERSION_ID" "$1")
}

function lk_is_wsl() {
    lk_is_linux && grep -iq Microsoft /proc/version &>/dev/null
}

function lk_is_virtual() {
    lk_is_linux &&
        grep -Eq "^flags[[:blank:]]*:.*\\<hypervisor\\>" /proc/cpuinfo
}

function lk_is_qemu() {
    lk_is_virtual && (shopt -s nullglob &&
        FILES=(/sys/devices/virtual/dmi/id/*_vendor) &&
        [ ${#FILES[@]} -gt 0 ] &&
        grep -iq qemu "${FILES[@]}")
}

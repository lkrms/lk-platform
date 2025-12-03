#!/usr/bin/env bash

function lk_assert_root() {
    lk_user_is_root || lk_die "not running as root"
}

function lk_assert_not_root() {
    ! lk_user_is_root || lk_die "cannot run as root"
}

function lk_assert_command_exists() {
    local IFS=' '
    lk_has "$@" ||
        lk_die "$(lk_plural $# "command" commands) not found: $*"
}

function lk_assert_is_linux() {
    lk_system_is_linux || lk_die "not running on Linux"
}

function lk_assert_is_arch() {
    lk_system_is_arch || lk_die "not running on Arch Linux"
}

function lk_assert_is_ubuntu() {
    lk_system_is_ubuntu || lk_die "not running on Ubuntu"
}

function lk_assert_is_macos() {
    lk_system_is_macos || lk_die "not running on macOS"
}

function lk_assert_not_wsl() {
    ! lk_system_is_wsl || lk_die "cannot run on Windows"
}

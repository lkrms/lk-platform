#!/bin/bash

function lk_assert_is_root() {
    lk_is_root || lk_die "not running as root"
}

function lk_assert_not_root() {
    ! lk_is_root || lk_die "cannot run as root"
}

function lk_assert_command_exists() {
    lk_command_exists "$1" || lk_die "command not found: $1"
}

function lk_assert_commands_exist() {
    lk_commands_exist "$@" || lk_die "$(lk_maybe_plural "$#" "command" "one or more commands") not found: $*"
}

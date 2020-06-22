#!/bin/bash

function lk_assert_is_root() {
    lk_is_root || lk_die "not running as root"
}

function lk_assert_not_root() {
    ! lk_is_root || lk_die "cannot run as root"
}

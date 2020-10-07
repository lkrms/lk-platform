#!/bin/bash

lk_include provision

function lk_apply_php_setting() {
    [ -n "${PHP_INI_FILE:-}" ] || lk_warn "PHP_INI_FILE not set" || return
    lk_apply_setting "$PHP_INI_FILE" "$1" "$2" "=" "; " " "
}

function lk_enable_php_entry() {
    [ -n "${PHP_INI_FILE:-}" ] || lk_warn "PHP_INI_FILE not set" || return
    lk_enable_entry "$PHP_INI_FILE" "$1" "; "
}

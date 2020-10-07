#!/bin/bash

lk_include provision

function lk_apply_httpd_setting() {
    [ -n "${HTTPD_CONF_FILE:-}" ] || lk_warn "HTTPD_CONF_FILE not set" || return
    lk_apply_setting "$HTTPD_CONF_FILE" "$1" "$2" " " "" $' \t'
}

function lk_enable_httpd_entry() {
    [ -n "${HTTPD_CONF_FILE:-}" ] || lk_warn "HTTPD_CONF_FILE not set" || return
    lk_enable_entry "$HTTPD_CONF_FILE" "$1" "# " ""
}

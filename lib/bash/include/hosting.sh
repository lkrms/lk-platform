#!/bin/bash

# shellcheck disable=SC2015

# lk_hosting_add_account LOGIN
function lk_hosting_add_account() {
    local _GROUP _HOME SKEL
    [ -n "${1:-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
    [ -d /srv/www ] || lk_warn "directory not found: /srv/www" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    for SKEL in /etc/skel{${LK_PATH_PREFIX_ALPHA:+.$LK_PATH_PREFIX_ALPHA},}; do
        [ -d "$SKEL" ] && break || unset SKEL
    done
    lk_console_item "Creating user account:" "$1"
    lk_console_detail "Skeleton directory:" "${SKEL-<none>}"
    lk_elevate useradd \
        --base-dir /srv/www \
        ${SKEL+--skel "$SKEL"} \
        --create-home \
        --shell /bin/bash \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_console_message "Account created successfully"
    lk_console_detail "Login group:" "$_GROUP"
    lk_console_detail "Home directory:" "$_HOME"
}

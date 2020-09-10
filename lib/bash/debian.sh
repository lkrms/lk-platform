#!/bin/bash

function lk_dpkg_installed() {
    local STATUS
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}' "$1" 2>/dev/null) &&
        [ "$STATUS" = installed ]
}

function lk_apt_update() {
    lk_console_message "Updating APT package indexes"
    lk_elevate apt-get -q update
}

function lk_apt_install() {
    lk_console_item "Installing APT $(lk_maybe_plural "$#" package packages):" \
        "$(printf '%s\n' "$@")"
    lk_elevate apt-get -yq install "$@"
}

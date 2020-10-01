#!/bin/bash

function lk_dpkg_installed() {
    local STATUS
    [ $# -gt 0 ] || lk_warn "no package name" || return
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}\n' "$@" 2>/dev/null |
        grep -Fx --count "installed") &&
        [ "$STATUS" -eq $# ]
}

function lk_dpkg_installed_list() {
    [ $# -eq 0 ] || {
        comm -12 \
            <(lk_dpkg_installed_list | sort | uniq) \
            <(lk_echo_args "$@" | sort | uniq)
        return
    }
    dpkg-query --show --showformat \
        '${db:Status-Status}\t${binary:Package}\n' |
        awk '$1 == "installed" { print $2 }'
}

function lk_dpkg_installed_versions() {
    dpkg-query --show --showformat \
        '${db:Status-Status}\t${binary:Package}=${Version}\n' "$@" |
        awk '$1 == "installed" { print $2 }'
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

function lk_apt_remove() {
    local REMOVE
    # shellcheck disable=SC2207
    REMOVE=($(lk_dpkg_installed_list "$@")) || return
    [ ${#REMOVE[@]} -eq 0 ] || {
        lk_console_item "Removing APT packages:" "$(lk_echo_array REMOVE)"
        lk_elevate apt-get -yq purge "${REMOVE[@]}"
    }
}

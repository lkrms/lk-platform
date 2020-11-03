#!/bin/bash

# shellcheck disable=SC2207

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

function lk_apt_available_list() {
    apt-cache pkgnames
}

function lk_apt_marked_manual_list() {
    apt-mark showmanual "$@"
}

function lk_apt_not_marked_manual_list() {
    [ $# -gt 0 ] || return
    comm -13 \
        <(lk_apt_marked_manual_list "$@" | sort | uniq) \
        <(lk_echo_args "$@" | sort | uniq)
}

function lk_apt_update() {
    lk_console_message "Updating APT package indexes"
    lk_elevate apt-get -q update
}

function lk_apt_install() {
    local INSTALL UNAVAILABLE
    INSTALL=($(lk_apt_not_marked_manual_list "$@")) &&
        UNAVAILABLE=$(comm -13 \
            <(lk_apt_available_list | sort | uniq) \
            <(lk_echo_array INSTALL | sort | uniq)) || return
    [ ${#UNAVAILABLE[@]} -eq 0 ] ||
        lk_warn "unavailable for installation: ${UNAVAILABLE[*]}" || return
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_echo_array INSTALL |
            lk_console_list "Installing:" "APT package" "APT packages"
        lk_elevate apt-get -yq install "${INSTALL[@]}"
    }
}

function lk_apt_remove() {
    local REMOVE
    REMOVE=($(lk_dpkg_installed_list "$@")) || return
    [ ${#REMOVE[@]} -eq 0 ] || {
        lk_echo_array REMOVE |
            lk_console_list "Removing:" "APT package" "APT packages"
        lk_elevate apt-get -yq purge "${REMOVE[@]}"
    }
}

#!/bin/bash

# shellcheck disable=SC2207

# lk_dpkg_installed PACKAGE...
#
# Return true if each PACKAGE is installed.
function lk_dpkg_installed() {
    local STATUS
    [ $# -gt 0 ] || lk_warn "no package name" || return
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}\n' "$@" 2>/dev/null |
        grep -Fx --count "installed") &&
        [ "$STATUS" -eq $# ]
}

# lk_dpkg_installed_list [PACKAGE...]
#
# Output each currently installed PACKAGE, or list all installed packages.
function lk_dpkg_installed_list() {
    [ $# -eq 0 ] || {
        comm -12 \
            <(lk_dpkg_installed_list | sort -u) \
            <(lk_echo_args "$@" | sort -u)
        return
    }
    dpkg-query --show --showformat \
        '${db:Status-Status}\t${binary:Package}\n' |
        awk '$1 == "installed" { print $2 }'
}

# lk_dpkg_installed_versions [PACKAGE...]
#
# Output ${Package}=${Version} for each currently installed PACKAGE, or for all
# installed packages.
function lk_dpkg_installed_versions() {
    dpkg-query --show --showformat \
        '${db:Status-Status}\t${binary:Package}=${Version}\n' "$@" |
        awk '$1 == "installed" { print $2 }'
}

# lk_apt_available_list
#
# Output the names of all packages available for installation.
function lk_apt_available_list() {
    apt-cache pkgnames
}

# lk_apt_marked_manual_list [PACKAGE...]
#
# Output each PACKAGE currently marked as "manually installed", or list all
# manually installed packages.
function lk_apt_marked_manual_list() {
    apt-mark showmanual "$@"
}

# lk_apt_not_marked_manual_list PACKAGE...
#
# Output each PACKAGE that isn't currently marked as "manually installed".
function lk_apt_not_marked_manual_list() {
    [ $# -gt 0 ] || return
    comm -13 \
        <(lk_apt_marked_manual_list "$@" | sort -u) \
        <(lk_echo_args "$@" | sort -u)
}

# lk_apt_update
#
# Retrieve the latest APT package indexes.
function lk_apt_update() {
    lk_console_message "Updating APT package indexes"
    lk_elevate apt-get -q update
}

# lk_apt_unavailable_list PACKAGE...
#
# Output each PACKAGE that doesn't appear in APT's package index.
function lk_apt_unavailable_list() {
    [ $# -gt 0 ] || return
    comm -13 \
        <(lk_apt_available_list | sort -u) \
        <(lk_echo_args "$@" | sort -u)
}

# lk_apt_install PACKAGE...
#
# Install each PACKAGE.
function lk_apt_install() {
    local INSTALL
    [ $# -gt 0 ] || return
    INSTALL=($(lk_apt_not_marked_manual_list "$@")) || return
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_echo_array INSTALL |
            lk_console_list "Installing:" "APT package" "APT packages"
        lk_elevate apt-get -yq install "${INSTALL[@]}"
    }
}

# lk_apt_remove PACKAGE...
#
# Remove each installed PACKAGE and any unused dependencies.
function lk_apt_remove() {
    local REMOVE
    [ $# -gt 0 ] || return
    REMOVE=($(lk_dpkg_installed_list "$@")) || return
    [ ${#REMOVE[@]} -eq 0 ] || {
        lk_echo_array REMOVE |
            lk_console_list "${LK_APT_REMOVE_MESSAGE:-Removing}:" \
                "APT package" "APT packages"
        lk_elevate apt-get -yq \
            "${LK_APT_REMOVE_COMMAND:-remove}" --auto-remove "${REMOVE[@]}"
    }
}

# lk_apt_purge PACKAGE...
#
# Purge each installed PACKAGE and any unused dependencies.
function lk_apt_purge() {
    LK_APT_REMOVE_COMMAND=purge \
        LK_APT_REMOVE_MESSAGE=Purging \
        lk_apt_remove "$@"
}

function lk_apt_purge_removed() {
    local PURGE
    lk_console_message "Removing unused dependencies"
    lk_elevate apt-get -yq autoremove &&
        PURGE=($(dpkg-query --show --showformat \
            '${db:Status-Status}\t${binary:Package}\n' |
            awk '$1 == "config-files" { print $2 }')) || return
    [ ${#PURGE[@]} -eq 0 ] || {
        lk_echo_array PURGE |
            lk_console_list "Purging:" "APT package" "APT packages"
        lk_elevate apt-get -yq purge "${PURGE[@]}"
    }
}

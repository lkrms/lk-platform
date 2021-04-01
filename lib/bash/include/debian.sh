#!/bin/bash

# lk_dpkg_installed PACKAGE...
#
# Return true if each PACKAGE is installed.
function lk_dpkg_installed() {
    local STATUS
    [ $# -gt 0 ] || lk_warn "no package" || return
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
    [ $# -gt 0 ] || lk_warn "no package" || return
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
    [ $# -gt 0 ] || lk_warn "no package" || return
    comm -13 \
        <(lk_apt_available_list | sort -u) \
        <(lk_echo_args "$@" | sort -u)
}

# lk_apt_installed PACKAGE...
#
# Return true if each PACKAGE is marked as "manually installed".
function lk_apt_installed() {
    local NOT_INSTALLED
    [ $# -gt 0 ] || lk_warn "no package" || return
    NOT_INSTALLED=$(lk_apt_not_marked_manual_list "$@" | wc -l) &&
        [ "$NOT_INSTALLED" -eq 0 ]
}

# lk_apt_install PACKAGE...
#
# Install each PACKAGE.
function lk_apt_install() {
    local INSTALL
    [ $# -gt 0 ] || lk_warn "no package" || return
    INSTALL=($(lk_apt_not_marked_manual_list "$@")) || return
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_echo_array INSTALL |
            lk_console_list "Installing:" "APT package" "APT packages"
        lk_elevate apt-get -yq \
            --no-install-recommends --no-install-suggests \
            install "${INSTALL[@]}"
    }
}

# lk_apt_remove PACKAGE...
#
# Remove each installed PACKAGE and any unused dependencies.
function lk_apt_remove() {
    local REMOVE
    [ $# -gt 0 ] || lk_warn "no package" || return
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

function lk_apt_autoremove() {
    lk_console_message "Removing unused dependencies"
    lk_elevate apt-get -yq autoremove
}

function lk_apt_purge_removed() {
    local PURGE
    PURGE=($(dpkg-query --show --showformat \
        '${db:Status-Status}\t${binary:Package}\n' |
        awk '$1 == "config-files" { print $2 }')) || return
    [ ${#PURGE[@]} -eq 0 ] || {
        lk_echo_array PURGE |
            lk_console_list "Purging previously removed packages:" \
                "APT package" "APT packages"
        lk_confirm "Proceed?" Y || return
        lk_elevate apt-get -yq purge "${PURGE[@]}"
    }
}

function lk_apt_upgrade_all() {
    local SH
    lk_apt_update &&
        SH=$(apt-get -qq --fix-broken --just-print \
            -o APT::Get::Show-User-Simulation-Note=false \
            dist-upgrade | awk \
            'function sh(op, arr, _i, _j) {
    printf "local %s=(", op
    for (_i in arr)
        printf (_j++ ? " %s" : "%s"), arr[_i]
    printf ")\n"
}
$1 == "Inst" {
    inst[++i] = $2
}
$1 == "Conf" {
    conf[++c] = $2
}
$1 == "Remv" {
    remv[++r] = $2
}
END {
    sh("INST", inst)
    sh("CONF", conf)
    sh("REMV", remv)
    printf "local CHANGES=%s", i + c + r
}') && eval "$SH" || return
    [ "$CHANGES" -gt 0 ] || return 0
    lk_console_message "Upgrading APT packages"
    [ ${#INST[@]} -eq 0 ] || lk_console_detail "Upgrade:" $'\n'"${INST[*]}"
    CONF=($(comm -23 \
        <(lk_echo_array CONF | sort -u) \
        <(lk_echo_array INST | sort -u)))
    [ ${#CONF[@]} -eq 0 ] || lk_console_detail "Configure:" $'\n'"${CONF[*]}"
    [ ${#REMV[@]} -eq 0 ] || lk_console_detail "Remove:" $'\n'"${REMV[*]}"
    lk_elevate apt-get -yq --fix-broken dist-upgrade || return
    lk_apt_autoremove
}

function lk_apt_reinstall_damaged() {
    local _DPKG _REAL _MISSING FILE_COUNT DIRS MISSING_COUNT REINSTALL AUTO
    lk_console_message "Checking APT package files"
    _DPKG=$(lk_mktemp_file) &&
        _REAL=$(lk_mktemp_file) &&
        _MISSING=$(lk_mktemp_file) &&
        lk_delete_on_exit "$_DPKG" "$_REAL" "$_MISSING" || return
    find /var/lib/dpkg/info -name "*.md5sums" -print0 |
        xargs -0 sed -E "s/^$NS+$S+(.*)/\/\1/" | sort -u >"$_DPKG" &&
        FILE_COUNT=$(wc -l <"$_DPKG") &&
        DIRS=$(sed -E 's/(.*)\/[^/]+$/\1/' "$_DPKG" | sort -u |
            awk -f "$LK_BASE/lib/awk/paths-get-unique-roots.awk" | sort -u) ||
        return
    ! lk_verbose ||
        lk_console_detail "Files managed by dpkg:" "$FILE_COUNT"
    local IFS=$'\n'
    lk_elevate find -L $DIRS -type f -print | sort -u >"$_REAL"
    comm -23 "$_DPKG" "$_REAL" >"$_MISSING" &&
        MISSING_COUNT=$(wc -l <"$_MISSING") || return
    ! lk_verbose ||
        lk_console_detail "Missing files:" "$MISSING_COUNT"
    [ "$MISSING_COUNT" -eq 0 ] || {
        REINSTALL=($(xargs dpkg -S <"$_MISSING" | cut -d: -f1 | sort -u)) &&
            [ ${#REINSTALL[@]} -gt 0 ] ||
            lk_warn "unable to find packages for missing files" || return
        lk_echo_array REINSTALL |
            lk_console_detail_list \
                "Reinstalling to restore $MISSING_COUNT $(lk_maybe_plural \
                    "$MISSING_COUNT" file files):" \
                "APT package" "APT packages"
        lk_confirm "Proceed?" Y || return
        AUTO=($(apt-mark showauto | grep -Fxf <(lk_echo_array REINSTALL) ||
            [ ${PIPESTATUS[1]} -eq 1 ])) || return
        unset IFS
        [ ${#AUTO[@]} -eq 0 ] ||
            lk_console_log "Packages marked as 'automatically installed':" \
                "${AUTO[*]}"
        lk_elevate apt-get -yq \
            --no-install-recommends --no-install-suggests --reinstall \
            install "${REINSTALL[@]}" &&
            { [ ${#AUTO[@]} -eq 0 ] ||
                lk_elevate apt-mark auto "${AUTO[@]}"; }
    }
}

# lk_apt_sources_get_clean [-l LIST]
function lk_apt_sources_get_clean() {
    local LIST=/etc/apt/sources.list CODENAME SH \
        SUITES=("$NS+") COMPONENTS=("$NS+")
    [ "${1:-}" != -l ] || LIST=$2
    [ "$LIST" != - ] || unset LIST
    if lk_is_ubuntu; then
        CODENAME=$(. /etc/lsb-release && echo "$DISTRIB_CODENAME") || return
        SUITES=("$CODENAME"{,-{updates,security,backports}})
        COMPONENTS=(main restricted universe multiverse)
    fi
    SH=$(lk_get_regex URI_REGEX_REQ_SCHEME_HOST) && eval "$SH"
    grep -E "^deb$S+$URI_REGEX_REQ_SCHEME_HOST$S+\
($(lk_implode '|' SUITES))\
($S+($(lk_implode '|' COMPONENTS)))+$S*(#.*|\$)" ${LIST:+"$LIST"} |
        sed -E "s/$S*(#.*)?\$//" |
        awk '{for(i=4;i<=NF;i++)print$1,$2,$3,$i}'
}

function _lk_apt_sources_get_mirror() {
    local _MIRROR
    [[ $1 =~ (-security|/updates)$ ]] &&
        _MIRROR=$SECURITY_MIRROR ||
        _MIRROR=$MIRROR
    lk_require_output awk \
        -v "s=$1" \
        -v "r=-security/?\$" \
        -v "m=$_MIRROR" \
        '!$2{next}$3==s{print$2;m="";exit}$2!~r&&$3!~r{m=$2;next}END{if(m)print m}'
}

# - lk_apt_sources_get_missing [-l LIST] COMPONENT
# - lk_apt_sources_get_missing [-l LIST] SUITE COMPONENT [SUITE COMPONENT]...
function lk_apt_sources_get_missing() {
    local LC_ALL=C LIST SOURCES COMPONENTS \
        MIRROR=${LK_APT_DEFAULT_MIRROR:-} \
        SECURITY_MIRROR=${LK_APT_DEFAULT_SECURITY_MIRROR:-}
    export LC_ALL
    unset LIST
    [ "${1:-}" != -l ] || { LIST=$2 && shift 2; }
    [ $# -gt 0 ] || lk_warn "invalid arguments" || return
    # If there are no existing sources with a valid URI (unlikely), use these
    if lk_is_ubuntu; then
        MIRROR=${MIRROR:-http://archive.ubuntu.com/ubuntu}
        SECURITY_MIRROR=${SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu}
    else
        MIRROR=${MIRROR:-http://deb.debian.org/debian}
        SECURITY_MIRROR=${SECURITY_MIRROR:-http://deb.debian.org/debian-security}
    fi
    SOURCES=$(lk_apt_sources_get_clean ${LIST:+-l "$LIST"}) || return
    COMPONENTS=$(if [ $# -eq 1 ]; then
        SUITE=$(cut -d' ' -f3 <<<"$SOURCES" | sort -u) || exit
        for s in $SUITE; do
            printf '%s %s\n' "$s" "$1"
        done
    else
        while [ $# -ge 2 ]; do
            for c in $2; do
                printf '%s %s\n' "$1" "$c"
            done
            shift 2
        done
    fi) || return
    comm -13 \
        <(cut -d' ' -f3-4 <<<"$SOURCES" | sort -u) \
        <(sort -u <<<"$COMPONENTS") |
        while read -r SUITE COMPONENT; do
            SUITE_MIRROR=$(_lk_apt_sources_get_mirror "$SUITE" <<<"$SOURCES") ||
                lk_warn "no mirror found for suite: $SUITE" || continue
            printf 'deb %s %s %s\n' \
                "$SUITE_MIRROR" \
                "$SUITE" \
                "$COMPONENT"
        done
}

lk_provide debian

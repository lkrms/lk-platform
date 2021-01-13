#!/bin/bash

# shellcheck disable=SC2016,SC2034,SC2206,SC2120,SC2086

function lk_arch_chroot() {
    local ARGS
    [ "${1:-}" != -u ] || {
        [ $# -ge 3 ] || lk_warn "invalid arguments" || return
        ARGS=(-u "$2")
        shift 2
    }
    if [ -n "${LK_ARCH_CHROOT_DIR:-}" ]; then
        arch-chroot ${ARGS[@]+"${ARGS[@]}"} "$LK_ARCH_CHROOT_DIR" "$@"
    elif [ -n "${ARGS+1}" ]; then
        sudo "${ARGS[@]}" "$@"
    else
        lk_elevate "$@"
    fi
}

function lk_arch_path() {
    [[ ${1:-} == /* ]] || lk_warn "path not absolute: ${1:-}" || return
    echo "${LK_ARCH_CHROOT_DIR:+${LK_ARCH_CHROOT_DIR%/}}$1"
}

function lk_pac_configure() {
    local FILE LK_SUDO=1
    FILE=$(lk_arch_path /etc/pacman.conf)
    lk_console_item "Checking" "$FILE"
    lk_file_keep_original "$FILE" &&
        # Leading and trailing whitespace in pacman.conf is ignored
        lk_file_replace "$FILE" \
            "$(sed -E "s/^$S*#$S*(Color|TotalDownload)$S*\$/\1/" "$FILE")"
}

# lk_pac_add_repo REPO...
#
# Add each REPO to /etc/pacman.conf unless it has already been added. REPO is a
# pipe-separated list of values in this order (trailing pipes are optional):
# - REPO
# - SERVER
# - KEY_URL (optional)
# - KEY_ID (optional)
# - SIG_LEVEL (optional)
#
# Examples (line breaks added for legibility):
# - lk_pac_add_repo "aur|file:///srv/repo/aur|||Optional TrustAll"
# - lk_pac_add_repo "sublime-text|
#   https://download.sublimetext.com/arch/stable/\$arch|
#   https://download.sublimetext.com/sublimehq-pub.gpg|
#   8A8F901A"
function lk_pac_add_repo() {
    local IFS='|' FILE SH i r REPO SERVER KEY_URL KEY_ID SIG_LEVEL _FILE \
        LK_SUDO=1
    [ $# -gt 0 ] || lk_warn "no repo" || return
    FILE=$(lk_arch_path /etc/pacman.conf)
    [ -f "$FILE" ] ||
        lk_warn "$FILE: file not found" || return
    SH=$(
        _add_key() { KEY_FILE=$(mktemp) &&
            curl --fail --location --output "$KEY_FILE" "$1" &&
            pacman-key --add "$KEY_FILE"; }
        declare -f _add_key
        echo '_add_key "$1"'
    )
    lk_console_item "Checking repositories in" "$FILE"
    for i in "$@"; do
        r=($i)
        REPO=${r[0]}
        ! pacman-conf --config "$FILE" --repo-list |
            grep -Fx "$REPO" >/dev/null || continue
        SERVER=${r[1]}
        KEY_URL=${r[2]:-}
        KEY_ID=${r[3]:-}
        SIG_LEVEL=${r[4]:-}
        lk_console_detail "Adding $REPO:" "$SERVER"
        if [ -n "$KEY_URL" ]; then
            lk_arch_chroot bash -c "$SH" bash "$KEY_URL"
        elif [ -n "$KEY_ID" ]; then
            lk_arch_chroot pacman-key --recv-keys "$KEY_ID"
        fi || return
        [ -z "$KEY_ID" ] ||
            lk_arch_chroot pacman-key --lsign-key "$KEY_ID" || return
        lk_file_keep_original "$FILE" &&
            lk_file_get_text "$FILE" _FILE &&
            lk_file_replace "$FILE" "$_FILE
[$REPO]${SIG_LEVEL:+
SigLevel = $SIG_LEVEL}
Server = $SERVER"
        unset LK_PACMAN_SYNC
    done
}

function lk_pac_official_repo_list() {
    pacman-conf --repo-list |
        grep -E '^(core|extra|community|multilib)$'
}

function lk_pac_sync() {
    ! lk_is_root && ! lk_can_sudo pacman ||
        lk_is_false LK_PACMAN_SYNC ||
        { lk_console_message "Refreshing package databases" &&
            lk_run_detail lk_elevate pacman -Syy >/dev/null &&
            lk_run_detail lk_elevate pacman -Fyy >/dev/null &&
            LK_PACMAN_SYNC=0; }
}

function lk_pac_groups() {
    lk_pac_sync &&
        pacman -Sgq "$@"
}

# lk_pac_available_list [-o] [PACKAGE...]
function lk_pac_available_list() {
    local OFFICIAL=
    [ "${1:-}" != -o ] || { OFFICIAL=1 && shift; }
    lk_pac_sync || return
    if [ $# -gt 0 ]; then
        comm -12 \
            <(lk_echo_args "$@" | sort -u) \
            <(lk_pac_available_list ${OFFICIAL:+-o} | sort -u)
    else
        local IFS=$'\n' REPOS
        REPOS=${OFFICIAL:+$(lk_pac_official_repo_list)} &&
            pacman -Slq $REPOS
    fi
}

# lk_pac_unavailable_list [-o] PACKAGE...
function lk_pac_unavailable_list() {
    local OFFICIAL=
    [ "${1:-}" != -o ] || { OFFICIAL=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no package" || return
    comm -23 \
        <(lk_echo_args "$@" | sort -u) \
        <(lk_pac_available_list ${OFFICIAL:+-o} | sort -u)
}

lk_provide arch

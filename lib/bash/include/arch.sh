#!/bin/bash

# shellcheck disable=SC2206,SC2120,SC2016

function _lk_arch_maybe_chroot() {
    if [ -n "${LK_ARCH_CHROOT_DIR:-}" ]; then
        arch-chroot ${LK_ARCH_CHROOT_USER:+-u "$LK_ARCH_CHROOT_USER"} "$LK_ARCH_CHROOT_DIR" "$@"
    else
        lk_elevate "$@"
    fi
}

function _lk_arch_path() {
    echo "${LK_ARCH_CHROOT_DIR:-}$1"
}

function lk_pacman_configure() {
    local PACMAN_CONF=${LK_PACMAN_CONF:-/etc/pacman.conf}
    PACMAN_CONF=$(_lk_arch_path "$PACMAN_CONF")
    # leading and trailing whitespace in pacman.conf is ignored
    LK_SUDO=1 lk_maybe_replace "$PACMAN_CONF" \
        "$(sed -E "s/^$S*#$S*(Color|TotalDownload)$S*\$/\1/" "$PACMAN_CONF")"
}

# lk_pacman_add_repo REPO ...
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
# - lk_pacman_add_repo "aur|file:///srv/repo/aur|||Optional TrustAll"
# - lk_pacman_add_repo "sublime-text|\
#   https://download.sublimetext.com/arch/stable/\$arch|\
#   https://download.sublimetext.com/sublimehq-pub.gpg|\
#   8A8F901A"
#
function lk_pacman_add_repo() {
    local PACMAN_CONF=${LK_PACMAN_CONF:-/etc/pacman.conf} IFS='|' \
        REPO_LIST SH i r REPO SERVER KEY_URL KEY_ID SIG_LEVEL
    [ $# -gt 0 ] || return 0
    PACMAN_CONF=$(_lk_arch_path "$PACMAN_CONF")
    [ -f "$PACMAN_CONF" ] ||
        lk_warn "$PACMAN_CONF: file not found" || return
    lk_command_exists pacman-conf ||
        lk_warn "command not found: pacman-conf" || return
    REPO_LIST=$(pacman-conf --config "$PACMAN_CONF" --repo-list) || return
    SH=$(
        _add_key() { KEY_FILE=$(mktemp) &&
            curl --fail --output "$KEY_FILE" "$1" &&
            pacman-key --add "$KEY_FILE"; }
        declare -f _add_key
        echo '_add_key "$1"'
    )
    for i in "$@"; do
        r=($i)
        REPO=${r[0]}
        ! grep -Fx "$REPO" <<<"$REPO_LIST" >/dev/null || continue
        SERVER=${r[1]}
        KEY_URL=${r[2]:-}
        KEY_ID=${r[3]:-}
        SIG_LEVEL=${r[4]:-}
        if [ -n "$KEY_URL" ]; then
            _lk_arch_maybe_chroot bash -c "$SH" bash "$KEY_URL"
        elif [ -n "$KEY_ID" ]; then
            _lk_arch_maybe_chroot pacman-key --recv-keys "$KEY_ID"
        fi || return
        [ -z "$KEY_ID" ] ||
            _lk_arch_maybe_chroot pacman-key --lsign-key "$KEY_ID" || return
        LK_SUDO=1 lk_keep_original "$PACMAN_CONF"
        lk_elevate tee -a "$PACMAN_CONF" <<EOF >/dev/null

[$REPO]${SIG_LEVEL:+
SigLevel = $SIG_LEVEL}
Server = $SERVER
EOF
        unset LK_PACMAN_SYNC
    done
}

function _lk_pacman_sync() {
    if { lk_is_root || lk_can_sudo pacman; } &&
        ! lk_is_false LK_PACMAN_SYNC; then
        lk_elevate pacman -Sy || return
        LK_PACMAN_SYNC=0
    fi
}

function lk_pacman_group_packages() {
    _lk_pacman_sync >&2 || return
    pacman -Sgq "$@"
}

#!/bin/bash

# shellcheck disable=SC2016,SC2034,SC2206,SC2120,SC2086

function lk_arch_chroot() {
    [ "${1:-}" != -u ] || {
        [ $# -ge 3 ] || lk_warn "invalid arguments" || return
        set -- sudo -H "$@"
    }
    if [ -n "${LK_ARCH_CHROOT_DIR:-}" ]; then
        arch-chroot "$LK_ARCH_CHROOT_DIR" "$@"
    else
        lk_elevate "$@"
    fi
}

function lk_arch_path() {
    [[ ${1:-} == /* ]] || lk_warn "path not absolute: ${1:-}" || return
    echo "${LK_ARCH_CHROOT_DIR:+${LK_ARCH_CHROOT_DIR%/}}$1"
}

function lk_arch_configure_pacman() {
    local FILE LK_SUDO=1
    FILE=$(lk_arch_path /etc/pacman.conf)
    lk_console_item "Checking pacman options in" "$FILE"
    lk_file_keep_original "$FILE" &&
        # Leading and trailing whitespace in pacman.conf is ignored
        lk_file_replace "$FILE" \
            "$(sed -E "s/^$S*#$S*(Color|TotalDownload)$S*\$/\1/" "$FILE")"
}

# lk_arch_add_repo REPO...
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
# - lk_arch_add_repo "aur|file:///srv/repo/aur|||Optional TrustAll"
# - lk_arch_add_repo "sublime-text|
#   https://download.sublimetext.com/arch/stable/\$arch|
#   https://download.sublimetext.com/sublimehq-pub.gpg|
#   8A8F901A"
function lk_arch_add_repo() {
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
        lk_console_detail "Adding '$REPO':" "$SERVER"
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

function lk_arch_configure_grub() {
    local FILE _FILE LK_GRUB_CMDLINE LK_SUDO=1
    LK_GRUB_CMDLINE=${LK_GRUB_CMDLINE+"$(lk_escape_ere_replace "$(lk_double_quote "$LK_GRUB_CMDLINE")")"}
    LK_GRUB_CMDLINE=${LK_GRUB_CMDLINE:-\\1}
    FILE=$(lk_arch_path /etc/default/grub)
    _FILE=$(sed -E \
        -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
        -e 's/^#?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
        -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=(.*)/GRUB_CMDLINE_LINUX_DEFAULT=$LK_GRUB_CMDLINE/" \
        "$FILE") &&
        lk_file_keep_original "$FILE" &&
        lk_file_replace "$FILE" "$_FILE" || lk_warn "unable to update $FILE" || return
    FILE=$(lk_arch_path /usr/local/bin/update-grub)
    _FILE="\
#!/bin/bash

set -euo pipefail

[[ ! \${1:-} =~ ^(-i|--install)\$ ]] ||
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg"
    lk_maybe_install -d -m 00755 "${FILE%/*}" &&
        lk_maybe_install -m 00755 /dev/null "$FILE" &&
        lk_file_replace "$FILE" "$_FILE" || lk_warn "unable to update $FILE" || return
}

function lk_pac_official_repo_list() {
    pacman-conf --repo-list |
        grep -E '^(core|extra|community|multilib)$'
}

# lk_pac_installed PACKAGE...
#
# Return true if each PACKAGE is installed.
function lk_pac_installed() {
    local EXPLICIT=
    [ "${1:-}" != -e ] || { EXPLICIT=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no package" || return
    pacman -Qq ${EXPLICIT:+-e} "$@" >/dev/null 2>&1
}

# lk_pac_installed_list [PACKAGE...]
#
# Output each currently installed PACKAGE, or list all installed packages.
function lk_pac_installed_list() {
    local EXPLICIT=
    [ "${1:-}" != -e ] || { EXPLICIT=1 && shift; }
    [ $# -eq 0 ] || {
        comm -12 \
            <(lk_pac_installed_list ${EXPLICIT:+-e} | sort -u) \
            <(lk_echo_args "$@" | sort -u)
        return
    }
    pacman -Qq ${EXPLICIT:+-e} "$@"
}

function lk_pac_sync() {
    ! lk_is_root && ! lk_can_sudo pacman ||
        lk_is_false LK_PACMAN_SYNC ||
        { lk_console_message "Refreshing package databases" &&
            lk_run_detail lk_elevate pacman -Sy >/dev/null &&
            lk_run_detail lk_elevate pacman -Fy >/dev/null &&
            LK_PACMAN_SYNC=0; }
}

function lk_pac_groups() {
    lk_pac_sync &&
        pacman -Sgq "$@"
}

# lk_pac_available_list [-o] [PACKAGE...]
#
# Output the names of all packages available for installation. If -o is set,
# only output packages from official repositories.
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

# lk_pac_installed_explicit [PACKAGE...]
#
# Output each PACKAGE currently marked as "explicitly installed", or list all
# explicitly installed packages.
function lk_pac_installed_explicit() {
    lk_pac_installed_list -e "$@"
}

# lk_pac_not_installed_explicit PACKAGE...
#
# Output each PACKAGE that isn't currently marked as "explicitly installed".
function lk_pac_not_installed_explicit() {
    [ $# -gt 0 ] || lk_warn "no package" || return
    comm -13 \
        <(lk_pac_installed_explicit "$@" | sort -u) \
        <(lk_echo_args "$@" | sort -u)
}

lk_provide arch

#!/bin/bash

# lk_sudo_nopasswd_add <USER>
#
# Add or update /etc/sudoers.d/nopasswd-<USER> with the following policy:
#
#     <USER> ALL=(ALL) NOPASSWD:ALL
function lk_sudo_nopasswd_add() {
    lk_user_exists "${1-}" || lk_warn "user not found: ${1-}" || return
    local LK_SUDO=1 FILE=/etc/sudoers.d/nopasswd-$1
    lk_install -m 00440 "$FILE" &&
        lk_file_replace "$FILE" <<EOF
$1 ALL=(ALL) NOPASSWD:ALL
EOF
}

# lk_sudo_nopasswd_offer
#
# If the current user can run commands via sudo, offer to add a sudoers entry
# allowing them to run sudo commands without being prompted for a password.
# Silently return false if the current user can't run commands via sudo.
function lk_sudo_nopasswd_offer() {
    ! lk_root || lk_warn "cannot run as root" || return
    local FILE=/etc/sudoers.d/nopasswd-$USER
    ! sudo -n test -e "$FILE" 2>/dev/null || return 0
    lk_can_sudo install || return
    lk_tty_yn \
        "Allow '$USER' to run sudo commands without authenticating?" N ||
        return 0
    lk_sudo_nopasswd_add "$USER" &&
        lk_tty_print "User '$USER' may now run any command as any user"
}

#!/bin/bash

# lk_sudo_offer_nopasswd
#   Invite the current user to add themselves to the system's sudoers
#   policy with unlimited access and no password prompts.
function lk_sudo_offer_nopasswd() {
    local FILE
    FILE="/etc/sudoers.d/nopasswd-$USER"
    ! lk_is_root || lk_warn "cannot run as root" || return
    sudo -n test -e "$FILE" 2>/dev/null || {
        lk_can_sudo || return
        lk_confirm "Allow user '$USER' to run sudo without entering a password?" N || return
        sudo install -m 440 /dev/null "$FILE" &&
            sudo tee "$FILE" >/dev/null <<<"$USER ALL=(ALL) NOPASSWD:ALL" &&
            lk_console_message "User '$USER' may now run any command as any user" || return
    }
}

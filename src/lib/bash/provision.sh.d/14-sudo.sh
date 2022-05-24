#!/bin/bash

# lk_sudo_keep_alive [INTERVAL]
#
# Update the user's cached sudo credentials, prompting for a password if
# necessary, then extend the sudo timeout in the background every INTERVAL
# seconds (240 by default) until the (sub)shell exits or `sudo -nv` fails.
function lk_sudo_keep_alive() {
    ! lk_root || return 0
    # Use `sudo bash -c 'exec true'` because `sudo -v` prompts NOPASSWD:ALL
    # users for a password, and succeeds regardless of the user's privileges
    sudo bash -c 'exec true' && lk_set_bashpid || return
    # Killing the background loop on exit should be sufficient to prevent it
    # running indefinitely, but as an additional safeguard, exit the loop if the
    # current shell has exited
    local PID=$BASHPID
    while kill -0 "$PID" 2>/dev/null; do
        sudo -nv &>/dev/null || break
        sleep "${1:-240}"
    done &
    lk_kill_on_exit $!
}

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

# lk_sudo_apply_sudoers ([<prefix>-] <file>)...
function lk_sudo_apply_sudoers() {
    local LK_SUDO=1 PREFIX FILE
    while (($#)); do
        [[ $1 == *- ]] && PREFIX=$1 && shift || PREFIX=
        FILE=/etc/sudoers.d/${PREFIX}${LK_PATH_PREFIX}${1##*/}
        lk_elevate test -e "$FILE" ||
            lk_elevate install -m 00440 /dev/null "$FILE" || return
        if [[ $1 == *.template ]]; then
            lk_file_replace "${FILE%.template}" < <(lk_expand_template "$1")
        else
            lk_file_replace -f "$1" "$FILE"
        fi || return
        shift
    done
}

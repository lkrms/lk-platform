#!/bin/bash

# shellcheck disable=SC2015

lk_include provision

# lk_hosting_add_account LOGIN
function lk_hosting_add_account() {
    local _GROUP _HOME SKEL
    [ -n "${1:-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
    [ -d /srv/www ] || lk_warn "directory not found: /srv/www" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    for SKEL in /etc/skel{${LK_PATH_PREFIX:+.${LK_PATH_PREFIX%-}},}; do
        [ -d "$SKEL" ] && break || unset SKEL
    done
    lk_console_item "Creating user account:" "$1"
    lk_console_detail "Skeleton directory:" "${SKEL-<none>}"
    lk_elevate useradd \
        --base-dir /srv/www \
        ${SKEL+--skel "$SKEL"} \
        --create-home \
        --shell /bin/bash \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_console_message "Account created successfully"
    lk_console_detail "Login group:" "$_GROUP"
    lk_console_detail "Home directory:" "$_HOME"
}

# lk_hosting_configure_backup
function lk_hosting_configure_backup() {
    local LK_SUDO=1 BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE:-} \
        AUTO_REBOOT=${LK_AUTO_REBOOT:-} \
        AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME:-} \
        REGEX INHIBIT_PATH
    REGEX=$(lk_escape_ere "$LK_BASE/lib/hosting/backup-all.sh")
    lk_console_message "Configuring automatic backups"
    if lk_is_false LK_AUTO_BACKUP; then
        lk_console_error \
            "Automatic backups are disabled (LK_AUTO_BACKUP=$LK_AUTO_BACKUP)"
        lk_crontab_remove "$REGEX"
    else
        # If LK_AUTO_BACKUP_SCHEDULE is not set, default to "0 1 * * *" (daily
        # at 1 a.m.) unless AUTO_REBOOT is enabled, in which case default to
        # "((REBOOT_MINUTE)) ((REBOOT_HOUR - 1)) * * *" (daily, 1 hour before
        # any automatic reboots)
        [ -n "$BACKUP_SCHEDULE" ] || ! lk_is_true AUTO_REBOOT ||
            [[ ! $AUTO_REBOOT_TIME =~ ^0*([0-9]+):0*([0-9]+)$ ]] ||
            BACKUP_SCHEDULE="${BASH_REMATCH[2]} $(((BASH_REMATCH[1] + 23) % 24)) * * *"
        BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-"0 1 * * *"}
        INHIBIT_PATH=$(type -P systemd-inhibit) &&
            lk_crontab_apply "$REGEX" "$(printf \
                '%s %s >%q 2>&1 || echo "Scheduled backup failed"' \
                "$BACKUP_SCHEDULE" \
                "$(lk_quote_args "$INHIBIT_PATH" \
                    --what=shutdown \
                    --mode=block \
                    --why="Allow scheduled backup to complete" \
                    "$LK_BASE/lib/hosting/backup-all.sh")" \
                "/var/log/${LK_PATH_PREFIX:-lk-}last-backup.log")"
    fi
}

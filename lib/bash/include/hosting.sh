#!/bin/bash

# shellcheck disable=SC2015

lk_include debian git provision

# lk_hosting_add_admin LOGIN [AUTHORIZED_KEY...]
function lk_hosting_add_admin() {
    local _GROUP _HOME
    [ -n "${1:-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    lk_console_item "Creating admin user:" "$1"
    lk_console_detail "Supplementary groups:" "$(lk_echo_args adm sudo)"
    lk_elevate useradd \
        --groups adm,sudo \
        --create-home \
        --shell /bin/bash \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_console_message "Account created successfully"
    lk_console_detail "Login group:" "$_GROUP"
    lk_console_detail "Home directory:" "$_HOME"
    [ $# -lt 2 ] || {
        local LK_SUDO=1 FILE=$_HOME/.ssh/authorized_keys
        lk_maybe_install -d -m 00700 -o "$1" -g "$_GROUP" "${FILE%/*}"
        lk_maybe_install -m 00600 -o "$1" -g "$_GROUP" /dev/null "$FILE"
        lk_file_replace "$FILE" "$(lk_echo_args "${@:2}")"
    }
    lk_sudo_add_nopasswd "$1"
}

# lk_hosting_add_account LOGIN
function lk_hosting_add_account() {
    local _GROUP _HOME SKEL
    [ -n "${1:-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
    [ -d /srv/www ] || lk_warn "directory not found: /srv/www" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    for SKEL in /etc/skel{.${LK_PATH_PREFIX%-},}; do
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

# lk_hosting_install_repo REMOTE_URL DIR [BRANCH [NAME]]
function lk_hosting_install_repo() {
    local REMOTE_URL DIR BRANCH NAME
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    REMOTE_URL=$1
    DIR=$2
    BRANCH=${3:-}
    NAME=${4:-$1}
    lk_elevate install -d -m 02775 -g adm "$DIR" || return
    if [ -z "$(ls -A "$DIR")" ]; then
        lk_console_item "Installing $NAME to" "$DIR"
        (
            umask 002 &&
                lk_elevate git clone \
                    ${BRANCH:+-b "$BRANCH"} "$REMOTE_URL" "$DIR"
        )
    else
        lk_console_item "Updating $NAME in" "$DIR"
        (
            umask 002 &&
                cd "$DIR" || exit
            REMOTES=$(git remote) &&
                [ "$REMOTES" = origin ] &&
                _REMOTE_URL=$(git remote get-url origin 2>/dev/null) &&
                [ "$_REMOTE_URL" = "$REMOTE_URL" ] || {
                lk_console_detail "Resetting remotes"
                for REMOTE in $REMOTES; do
                    lk_elevate git remote remove "$REMOTE" || exit
                done
                lk_elevate git remote add origin "$REMOTE_URL" || exit
            }
            LK_SUDO=1 \
                lk_git_update_repo_to origin "$BRANCH"
        )
    fi
}

function lk_hosting_configure_modsecurity() {
    lk_apt_install libapache2-mod-security2 &&
        lk_hosting_install_repo \
            https://github.com/coreruleset/coreruleset.git \
            /opt/coreruleset \
            "${LK_OWASP_CRS_BRANCH:-v3.3/master}" \
            "OWASP ModSecurity Core Rule Set" || return
}

# lk_hosting_configure_backup
function lk_hosting_configure_backup() {
    local LK_SUDO=1 BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE:-} \
        AUTO_REBOOT=${LK_AUTO_REBOOT:-} \
        AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME:-} \
        REGEX INHIBIT_PATH
    REGEX=$(lk_escape_ere "${LK_INST:-$LK_BASE}/lib/hosting/backup-all.sh")
    lk_console_message "Configuring automatic backups"
    if lk_is_false LK_AUTO_BACKUP; then
        lk_console_error \
            "Automatic backups are disabled (LK_AUTO_BACKUP=$LK_AUTO_BACKUP)"
        lk_crontab_remove "$REGEX"
    else
        # If LK_AUTO_BACKUP_SCHEDULE is not set, default to "0 1 * * *" (daily
        # at 1 a.m.) unless LK_AUTO_REBOOT is enabled, in which case default to
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
                    "${LK_INST:-$LK_BASE}/lib/hosting/backup-all.sh")" \
                "/var/log/${LK_PATH_PREFIX:-lk-}last-backup.log")"
    fi
}

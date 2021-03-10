#!/bin/bash

# shellcheck disable=SC2046

lk_include debian git provision

# lk_hosting_add_administrator LOGIN [AUTHORIZED_KEY...]
function lk_hosting_add_administrator() {
    local _GROUP _HOME
    [ -n "${1:-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    lk_console_item "Creating administrator account:" "$1"
    lk_console_detail "Supplementary groups:" "adm, sudo"
    lk_elevate useradd \
        --groups adm,sudo \
        --create-home \
        --shell /bin/bash \
        --key UMASK=027 \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_console_message "Account created successfully"
    lk_console_detail "Login group:" "$_GROUP"
    lk_console_detail "Home directory:" "$_HOME"
    [ $# -lt 2 ] || {
        local LK_SUDO=1 FILE=$_HOME/.ssh/authorized_keys
        lk_install -d -m 00700 -o "$1" -g "$_GROUP" "${FILE%/*}"
        lk_install -m 00600 -o "$1" -g "$_GROUP" "$FILE"
        lk_file_replace "$FILE" "$(lk_echo_args "${@:2}")"
    }
    lk_sudo_add_nopasswd "$1"
}

# lk_hosting_add_user LOGIN
function lk_hosting_add_user() {
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
        --key UMASK=027 \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_console_message "Account created successfully"
    lk_console_detail "Login group:" "$_GROUP"
    lk_console_detail "Home directory:" "$_HOME"
}

# lk_hosting_get_site_settings DOMAIN
function lk_hosting_get_site_settings() {
    [ $# -gt 0 ] || lk_warn "no domain" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    (
        unset "${!SITE_@}"
        FILE=$LK_BASE/etc/sites/$1.conf
        [ ! -e "$FILE" ] || . "$FILE" || exit
        _LK_VAR_PREFIX_DEPTH=1 \
            lk_get_quoted_var $({ printf 'SITE_%s\n' \
                ROOT ENABLE DISABLE_WWW DISABLE_HTTPS \
                PHP_FPM_USER PHP_FPM_TIMEOUT PHP_VERSION &&
                lk_echo_args "${!SITE_@}"; } | sort -u)
    )
}

# lk_hosting_set_site_settings DOMAIN
function lk_hosting_set_site_settings() {
    local LK_SUDO=1 FILE
    [ $# -gt 0 ] || lk_warn "no domain" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    FILE=$LK_BASE/etc/sites/$1.conf
    lk_install -d -m 02770 -g adm "$LK_BASE/etc/sites" &&
        lk_install -m 00660 -g adm "$FILE" &&
        lk_file_replace -l "$FILE" "$(lk_get_shell_var "${!SITE_@}")"
}

# lk_hosting_configure_site DOMAIN HOME USER
function lk_hosting_configure_site() {
    local LK_SUDO=1 DOMAIN _HOME _USER SH GROUP
    [ $# -eq 3 ] || lk_warn "invalid arguments" || return
    lk_dirs_exist /srv/www{,/.tmp,/.opcache} ||
        lk_warn "hosting base directories not found" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    lk_user_exists "$3" || lk_warn "user does not exist: $3" || return
    [[ $2 =~ ^/srv/www/$3(/[^/]+)?/?$ ]] &&
        [[ ! ${BASH_REMATCH[1]} =~ ^/(public_html|log|backup|ssl|\..*)$ ]] ||
        lk_warn "invalid directory: $2" || return
    DOMAIN=${1#www.}
    _HOME=${2%/}
    _USER=$3
    lk_console_item "Configuring site:" "$DOMAIN"
    SH=$(lk_hosting_get_site_settings "$DOMAIN") &&
        eval "$SH" || return
    SITE_ROOT=$_HOME
    SITE_ENABLE=${SITE_ENABLE:-Y}
    SITE_DISABLE_WWW=${SITE_DISABLE_WWW:-N}
    SITE_DISABLE_HTTPS=${SITE_DISABLE_HTTPS:-N}
    if lk_apt_installed php-fpm; then
        if lk_user_in_group adm "$_USER"; then
            SITE_PHP_FPM_USER=${SITE_PHP_FPM_USER:-www-data}
        else
            SITE_PHP_FPM_USER=${SITE_PHP_FPM_USER:-$_USER}
        fi
        SITE_PHP_FPM_TIMEOUT=${SITE_PHP_FPM_TIMEOUT:-300}
    fi
    lk_console_detail "Checking files and directories in" "$_HOME"
    GROUP=$(id -gn "$_USER") &&
        lk_install -d -m 00750 -o "$_USER" -g "$GROUP" \
            "$_HOME"/{,public_html,ssl} &&
        lk_install -d -m 02750 -o root -g "$GROUP" \
            "$_HOME/log" || return
    if lk_apt_installed apache2; then
        lk_install -m 00640 -o root -g "$GROUP" "$_HOME/log/error.log"
        lk_install -m 00640 -o root -g "$GROUP" "$_HOME/log/access.log"
        lk_install -m 00640 -o "$_USER" -g "$GROUP" "$_HOME/ssl/$DOMAIN.cert"
        lk_install -m 00640 -o "$_USER" -g "$GROUP" "$_HOME/ssl/$DOMAIN.key"
        lk_user_in_group "$GROUP" www-data || {
            lk_console_detail "Adding user 'www-data' to group:" "$GROUP"
            lk_elevate usermod --append --groups "$GROUP" www-data || return
        }
    fi
    lk_hosting_set_site_settings "$DOMAIN"
}

function lk_hosting_configure_modsecurity() {
    lk_apt_install libapache2-mod-security2 &&
        lk_git_provision_repo -s \
            -o root:adm \
            -b "${LK_OWASP_CRS_BRANCH:-v3.3/master}" \
            -n "OWASP ModSecurity Core Rule Set" \
            https://github.com/coreruleset/coreruleset.git \
            /opt/coreruleset || return
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

lk_provide hosting

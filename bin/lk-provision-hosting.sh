#!/bin/bash

[ "$EUID" -eq 0 ] || {
    [ -z "${BASH_XTRACEFD-}" ] && unset ARGS ||
        ARGS=(-C $((i = BASH_XTRACEFD, (${_LK_FD:=2} > i ? _LK_FD : i) + 1)))
    sudo ${ARGS+"${ARGS[@]}"} -H "$0" "$@"
    exit
}

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
[ "${_FILE%/*}" != "$_FILE" ] || _FILE=./$_FILE
LK_BASE=$(i=0 && F=$_FILE && while [ $((i++)) -le "$_DEPTH" ]; do
    [ "$F" != / ] && [ ! -L "$F" ] &&
        cd "${F%/*}" && F=$PWD || exit
done && pwd -P) || lk_die "symlinks in path are not supported"
[ -d "$LK_BASE/lib/bash" ] || lk_die "unable to locate LK_BASE"
export LK_BASE

shopt -s nullglob

. "$LK_BASE/lib/bash/common.sh"
lk_include debian git hosting linux mysql provision validate

LK_VERBOSE=${LK_VERBOSE-1}

function no_upgrade() {
    lk_has_arg --no-upgrade
}

# maybe_move_old OLD_FILE NEW_FILE
function maybe_move_old() {
    [ ! -e "$1" ] || [ -e "$2" ] || {
        mv -nv "$1" "$2" &&
            LK_FILE_REPLACE_NO_CHANGE=0
    }
}

# maybe_restore_original FILE
function maybe_restore_original() {
    ! lk_is_bootstrap || return 0
    set -- "$1"{.orig,}
    ! lk_files_exist "$@" ||
        diff -q "$@" >/dev/null || {
        lk_file_backup "$2" &&
            lk_run_detail mv -fv "$@" &&
            LK_FILE_REPLACE_NO_CHANGE=0
    }
}

function get_before_file() {
    local CLEAR_VERBOSE=
    [ "${1-}" != -v ] || { unset CLEAR_VERBOSE && shift; }
    _LK_VERBOSE=${LK_VERBOSE-}
    unset LK_FILE_REPLACE_NO_CHANGE ${CLEAR_VERBOSE+LK_VERBOSE}
    [ -n "${BEFORE_FILE-}" ] || {
        BEFORE_FILE=$(lk_mktemp_file) &&
            lk_delete_on_exit "$BEFORE_FILE" || return
    }
    AFTER_FILE=$1
    if [ -e "$1" ]; then
        cp "$1" "$BEFORE_FILE"
    else
        : >"$BEFORE_FILE"
    fi
}

function check_after_file() {
    diff -q "$BEFORE_FILE" "$AFTER_FILE" >/dev/null ||
        lk_console_diff "$BEFORE_FILE" "$AFTER_FILE"
    [ -z "$_LK_VERBOSE" ] || LK_VERBOSE=$_LK_VERBOSE
}

if ! lk_is_bootstrap; then
    function lk_keep_trying {
        "$@"
    }

    SETTINGS_SH=$(lk_settings_getopt "$@")
    eval "$SETTINGS_SH"
    shift "$_LK_SHIFT"

    # TODO: use getopt
    [ $# -eq 0 ] ||
        [ "$1" = --no-upgrade ] ||
        lk_usage "\
Usage: ${0##*/} [--set|--add|--remove|--unset SETTING[=VALUE]]... [--no-upgrade]"
fi

lk_assert_is_root
lk_assert_is_linux
lk_assert_is_ubuntu

export -n \
    LK_NODE_HOSTNAME=${LK_NODE_HOSTNAME-} \
    LK_NODE_FQDN=${LK_NODE_FQDN-} \
    LK_NODE_TIMEZONE=${LK_NODE_TIMEZONE-} \
    LK_NODE_SERVICES=${LK_NODE_SERVICES-} \
    LK_NODE_PACKAGES=${LK_NODE_PACKAGES-} \
    LK_ADMIN_EMAIL=${LK_ADMIN_EMAIL-} \
    LK_TRUSTED_IP_ADDRESSES=${LK_TRUSTED_IP_ADDRESSES-} \
    LK_SSH_TRUSTED_ONLY=${LK_SSH_TRUSTED_ONLY:-N} \
    LK_SSH_TRUSTED_PORT=${LK_SSH_TRUSTED_PORT-} \
    LK_SSH_JUMP_HOST=${LK_SSH_JUMP_HOST-} \
    LK_SSH_JUMP_USER=${LK_SSH_JUMP_USER-} \
    LK_SSH_JUMP_KEY=${LK_SSH_JUMP_KEY-} \
    LK_REJECT_OUTPUT=${LK_REJECT_OUTPUT:-N} \
    LK_ACCEPT_OUTPUT_HOSTS=${LK_ACCEPT_OUTPUT_HOSTS-} \
    LK_INNODB_BUFFER_SIZE=${LK_INNODB_BUFFER_SIZE-} \
    LK_OPCACHE_MEMORY_CONSUMPTION=${LK_OPCACHE_MEMORY_CONSUMPTION-} \
    LK_PHP_SETTINGS=${LK_PHP_SETTINGS-} \
    LK_PHP_ADMIN_SETTINGS=${LK_PHP_ADMIN_SETTINGS-} \
    LK_MEMCACHED_MEMORY_LIMIT=${LK_MEMCACHED_MEMORY_LIMIT-} \
    LK_SMTP_RELAY=${LK_SMTP_RELAY-} \
    LK_EMAIL_BLACKHOLE=${LK_EMAIL_BLACKHOLE-} \
    LK_UPGRADE_EMAIL=${LK_UPGRADE_EMAIL-} \
    LK_AUTO_REBOOT=${LK_AUTO_REBOOT-} \
    LK_AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME-} \
    LK_AUTO_BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE-} \
    LK_SNAPSHOT_HOURLY_MAX_AGE=${LK_SNAPSHOT_HOURLY_MAX_AGE-} \
    LK_SNAPSHOT_DAILY_MAX_AGE=${LK_SNAPSHOT_DAILY_MAX_AGE-} \
    LK_SNAPSHOT_WEEKLY_MAX_AGE=${LK_SNAPSHOT_WEEKLY_MAX_AGE-} \
    LK_SNAPSHOT_FAILED_MAX_AGE=${LK_SNAPSHOT_FAILED_MAX_AGE-} \
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-} \
    LK_DEBUG=${LK_DEBUG:-N} \
    LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

! lk_is_bootstrap ||
    export -n \
        LK_HOST_DOMAIN=${LK_HOST_DOMAIN-} \
        LK_HOST_ACCOUNT=${LK_HOST_ACCOUNT-} \
        LK_HOST_SITE_ENABLE=${LK_HOST_SITE_ENABLE-} \
        LK_ADMIN_USERS=${LK_ADMIN_USERS-} \
        LK_MYSQL_USERNAME=${LK_MYSQL_USERNAME-} \
        LK_MYSQL_PASSWORD=${LK_MYSQL_PASSWORD-} \
        LK_SHUTDOWN_ACTION=${LK_SHUTDOWN_ACTION:-reboot}

eval "$(lk_get_regex)"

FIELD_ERRORS=$'\n'$(
    lk_validate_clear

    # Required fields
    _LK_REQUIRED=1
    lk_validate LK_NODE_HOSTNAME "^$DOMAIN_PART_REGEX\$"
    lk_validate LK_NODE_FQDN "^$DOMAIN_NAME_REGEX\$"
    lk_validate_one_of LK_NODE_TIMEZONE < <(timedatectl list-timezones)
    lk_validate LK_ADMIN_EMAIL "^$EMAIL_ADDRESS_REGEX\$"
    lk_validate_one_of LK_AUTO_REBOOT Y N

    # Optional fields
    _LK_REQUIRED=0
    lk_validate_many_of LK_NODE_SERVICES \
        apache+php \
        mysql \
        memcached
    lk_validate_list LK_NODE_PACKAGES "^$DPKG_SOURCE_REGEX\$"
    ! lk_is_bootstrap || {
        lk_validate LK_HOST_DOMAIN "^$DOMAIN_NAME_REGEX\$"
        lk_validate LK_HOST_ACCOUNT "^$LINUX_USERNAME_REGEX\$"
        [ -z "$LK_HOST_DOMAIN" ] || _LK_REQUIRED=1
        lk_validate_one_of LK_HOST_SITE_ENABLE Y N
        _LK_REQUIRED=0
        lk_validate_list LK_ADMIN_USERS "^$LINUX_USERNAME_REGEX\$"
    }
    [ ! "$LK_SSH_TRUSTED_ONLY" = Y ] || _LK_REQUIRED=1
    lk_validate_list LK_TRUSTED_IP_ADDRESSES "^$IP_OPT_PREFIX_REGEX\$"
    _LK_REQUIRED=0
    lk_validate_one_of LK_SSH_TRUSTED_ONLY Y N
    lk_validate LK_SSH_TRUSTED_PORT "^(102[4-9]|10[3-9][0-9]|1[1-9][0-9]{2}|[2-9][0-9]{3}|[1-9][0-9]{4,})\$"
    lk_validate LK_SSH_JUMP_HOST "^$HOST_REGEX\$"
    lk_validate LK_SSH_JUMP_USER "^$LINUX_USERNAME_REGEX\$"
    lk_validate LK_SSH_JUMP_KEY "^[-a-zA-Z0-9_]+\$"
    lk_validate_one_of LK_REJECT_OUTPUT Y N
    # TODO: allow "URL|JQ_FILTER"
    lk_validate_list LK_ACCEPT_OUTPUT_HOSTS "^$HOST_OPT_PREFIX_REGEX\$"
    ! lk_is_bootstrap || {
        lk_validate LK_MYSQL_USERNAME "^$MYSQL_USERNAME_REGEX\$"
        [ -z "$LK_MYSQL_USERNAME" ] ||
            lk_validate_not_null LK_MYSQL_PASSWORD
    }
    lk_validate LK_INNODB_BUFFER_SIZE "^[0-9]+[kmgtpeKMGTPE]?\$"
    lk_validate LK_OPCACHE_MEMORY_CONSUMPTION "^[0-9]+\$"
    lk_validate_list LK_PHP_SETTINGS "^$PHP_SETTING_REGEX\$"
    lk_validate_list LK_PHP_ADMIN_SETTINGS "^$PHP_SETTING_REGEX\$"
    lk_validate LK_MEMCACHED_MEMORY_LIMIT "^[0-9]+\$"
    lk_validate LK_SMTP_RELAY "^($HOST_REGEX|\\[$HOST_REGEX\\])(:[0-9]+)?\$"
    lk_validate LK_UPGRADE_EMAIL "^$EMAIL_ADDRESS_REGEX\$"
    [ ! "$LK_AUTO_REBOOT" = Y ] || _LK_REQUIRED=1
    lk_validate LK_AUTO_REBOOT_TIME "^(([01][0-9]|2[0-3]):[0-5][0-9]|now)\$"
    _LK_REQUIRED=0
    lk_validate LK_SNAPSHOT_HOURLY_MAX_AGE "^(-1|[0-9]+)\$"
    lk_validate LK_SNAPSHOT_DAILY_MAX_AGE "^(-1|[0-9]+)\$"
    lk_validate LK_SNAPSHOT_WEEKLY_MAX_AGE "^(-1|[0-9]+)\$"
    lk_validate LK_SNAPSHOT_FAILED_MAX_AGE "^(-1|[0-9]+)\$"
    lk_validate LK_PATH_PREFIX "^[a-zA-Z0-9]{2,3}-\$"
    lk_validate_one_of LK_DEBUG Y N
    ! lk_is_bootstrap ||
        lk_validate_one_of LK_SHUTDOWN_ACTION reboot poweroff

    lk_validate_status
) || { FIELD_ERRORS=${FIELD_ERRORS//$'\n'/$'\n  - '} &&
    lk_die "invalid configuration:$FIELD_ERRORS"; }

. /etc/lsb-release

lk_lock LOCK_FILE LOCK_FD "${LK_PATH_PREFIX}install"

if lk_is_bootstrap; then
    FILE=$LK_BASE/etc/lk-platform/lk-platform.conf
    install -m 00664 -g adm /dev/null "$FILE"
    LK_SSH_JUMP_KEY=${LK_SSH_JUMP_KEY:+jump} lk_get_shell_var \
        LK_BASE \
        LK_PATH_PREFIX \
        LK_NODE_HOSTNAME \
        LK_NODE_FQDN \
        LK_NODE_TIMEZONE \
        LK_NODE_SERVICES \
        LK_NODE_PACKAGES \
        LK_ADMIN_EMAIL \
        LK_TRUSTED_IP_ADDRESSES \
        LK_SSH_TRUSTED_ONLY \
        LK_SSH_TRUSTED_PORT \
        LK_SSH_JUMP_HOST \
        LK_SSH_JUMP_USER \
        LK_SSH_JUMP_KEY \
        LK_REJECT_OUTPUT \
        LK_ACCEPT_OUTPUT_HOSTS \
        LK_INNODB_BUFFER_SIZE \
        LK_OPCACHE_MEMORY_CONSUMPTION \
        LK_PHP_SETTINGS \
        LK_PHP_ADMIN_SETTINGS \
        LK_MEMCACHED_MEMORY_LIMIT \
        LK_SMTP_RELAY \
        LK_EMAIL_BLACKHOLE \
        LK_UPGRADE_EMAIL \
        LK_AUTO_REBOOT \
        LK_AUTO_REBOOT_TIME \
        LK_AUTO_BACKUP_SCHEDULE \
        LK_SNAPSHOT_HOURLY_MAX_AGE \
        LK_SNAPSHOT_DAILY_MAX_AGE \
        LK_SNAPSHOT_WEEKLY_MAX_AGE \
        LK_SNAPSHOT_FAILED_MAX_AGE \
        LK_DEBUG \
        LK_PLATFORM_BRANCH >"$FILE"
else
    LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-1}
    LK_FILE_BACKUP_MOVE=1
    (
        LK_VERBOSE=1
        lk_settings_persist "$SETTINGS_SH"
    )
fi

unset BEFORE_FILE REBOOT
P=${LK_PATH_PREFIX%-}_
IPTABLES_TCP_LISTEN=()
IPTABLES_UDP_LISTEN=()
CURL_OPTIONS=(-fsSLH "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 2)

APT_REPOS=()
APT_SUPPRESS=()
APT_FILTER=()
APT_ADD_REPOSITORY_ARGS=(-yn)
APACHE_MODS_SUPPRESS=()
PHPVER=$(lk_hosting_php_get_default_version)

CERTBOT_REPO=ppa:certbot/certbot
case "$DISTRIB_RELEASE" in
16.04)
    APT_REPOS+=("$CERTBOT_REPO")
    APT_SUPPRESS+=(
        icdiff
        php-apcu-bc
        php-yaml
        xxhash
    )
    APT_ADD_REPOSITORY_ARGS=(-y)
    APACHE_MODS_SUPPRESS+=(http2)
    ;;
18.04)
    APT_REPOS+=("$CERTBOT_REPO")
    ;;
20.04)
    APT_SUPPRESS+=(
        php-gettext
    )
    ;;
*)
    lk_die "Ubuntu release not supported: $DISTRIB_RELEASE"
    ;;
esac
APT_FILTER+=("s/^php-opcache$/php$PHPVER-opcache/")

export DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    PIP_NO_INPUT=1

if ! lk_is_bootstrap; then
    lk_log_start /var/log/{lk-platform-,"${LK_PATH_PREFIX}"}*install.out
    lk_log_tty_stdout_off
    [ "$LK_DEBUG" != Y ] ||
        lk_start_trace
fi

{
    lk_console_log "Provisioning Ubuntu for hosting"

    install -d -m 02775 -g adm "$LK_BASE"/{etc,var}
    install -d -m 02770 -g adm "$LK_BASE/var/run"/{,dirty}

    lk_is_bootstrap || [ -d "$LK_BASE/etc/sites" ] ||
        lk_hosting_mark_dirty "legacy-sites.migration"

    install -d -m 02770 -g adm "$LK_BASE/etc/sites"

    lk_console_message "Checking system timezone"
    TIMEZONE=$(lk_system_timezone)
    [ "$TIMEZONE" = "$LK_NODE_TIMEZONE" ] ||
        lk_run_detail timedatectl set-timezone "$LK_NODE_TIMEZONE"

    lk_console_message "Checking system hostname"
    [ "$(hostname -s)" = "$LK_NODE_HOSTNAME" ] || {
        lk_run_detail hostnamectl set-hostname "$LK_NODE_HOSTNAME"
        REBOOT=1
    }

    lk_console_message "Checking hosts file"
    FILE=/etc/hosts
    IPV4_ADDRESS=$(_LK_IP_PUBLIC_ONLY=1 lk_node_ipv4) || IPV4_ADDRESS=
    IPV6_ADDRESS=$(_LK_IP_PUBLIC_ONLY=1 lk_node_ipv6) || IPV6_ADDRESS=
    HOST_NAMES=$LK_NODE_HOSTNAME
    # TODO: check configured sites as well
    lk_is_bootstrap &&
        [ -z "$IPV4_ADDRESS" ] &&
        # Apache doesn't resolve name-based virtual hosts correctly if
        # ServerName resolves to a loopback address, so only associate the
        # host's FQDN with 127.0.1.1 if it's different to the initial hosting
        # domain
        [ "${LK_NODE_FQDN#www.}" = "$LK_HOST_DOMAIN" ] ||
        HOST_NAMES="$LK_NODE_FQDN $HOST_NAMES"
    _FILE=$(HOSTS="# Generated by ${0##*/} at $(lk_date_log)
${IPV4_ADDRESS:-127.0.1.1} $HOST_NAMES${IPV6_ADDRESS:+
$IPV6_ADDRESS $HOST_NAMES}" &&
        awk \
            -v "BLOCK=$HOSTS" \
            -v 'FIRST=^# ((Added|Generated) by |Virtual hosts$)' \
            -f "$LK_BASE/lib/awk/block-replace.awk" \
            "$FILE" && printf .)
    _FILE=${_FILE%.}
    lk_file_keep_original "$FILE"
    lk_file_replace -i "^(#|$S*\$)" "$FILE" "$_FILE"

    lk_console_message "Checking systemd journal"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/systemd/journald.conf.d/90${LK_PATH_PREFIX}default
    lk_install -d -m 00755 "${FILE%/*}"
    lk_install -m 00644 "$FILE"
    lk_file_replace \
        -f "$LK_BASE/share/systemd/journald.conf" \
        "$FILE"
    maybe_restore_original /etc/systemd/journald.conf
    lk_is_bootstrap && ! lk_systemctl_running systemd-journald ||
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        lk_run_detail systemctl restart systemd-journald.service

    lk_console_message "Checking root account"
    STATUS=$(lk_user_passwd_status root)
    [ "$STATUS" = P ] ||
        lk_console_error "No root password has been set"

    lk_console_message "Checking sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default-hosting
    OLD_FILE=/etc/sudoers.d/${LK_PATH_PREFIX}mysql-self-service
    maybe_move_old "$OLD_FILE" "$FILE"
    lk_install -m 00440 "$FILE"
    lk_file_replace "$FILE" "$(
        lk_expand_template "$LK_BASE/share/sudoers.d/default-hosting"
    )"

    lk_console_message "Checking kernel parameters"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/sysctl.d/90-${LK_PATH_PREFIX}default.conf
    OLD_FILE=/etc/sysctl.d/90-${LK_PATH_PREFIX}defaults.conf
    lk_install -d -m 00755 "${FILE%/*}"
    maybe_move_old "$OLD_FILE" "$FILE"
    lk_install -m 00644 "$FILE"
    lk_file_replace \
        -f "$LK_BASE/share/sysctl.d/default.conf" \
        "$FILE"
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        lk_run_detail sysctl --system

    lk_console_message "Checking kernel modules"
    lk_run_detail modprobe nf_conntrack_ftp ||
        lk_die "error loading kernel modules"
    FILE=/etc/modules-load.d/${LK_PATH_PREFIX}nf_conntrack.conf
    lk_install -m 00644 "$FILE"
    lk_file_replace "$FILE" "nf_conntrack_ftp"

    lk_console_message "Checking APT"
    lk_console_detail "Checking sources"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/apt/sources.list
    # Disable source packages, multiverse sources
    _FILE=$(sed -E \
        -e "s/^deb-src$S/#&/" \
        -e "s/^deb$S.*$S$DISTRIB_CODENAME(-(updates|security|backports))?($S+$NS+)*$S+multiverse($S|\$)/#&/" \
        "$FILE")
    # Enable universe (required for certbot), backports
    COMPONENTS=("$DISTRIB_CODENAME"{,-{updates,security,backports}}" "{main,restricted,universe})
    _FILE+=$(printf '\n' &&
        lk_apt_sources_get_missing -l - ${COMPONENTS[*]} <<<"$_FILE")
    lk_file_keep_original "$FILE"
    lk_file_replace "$FILE" "$_FILE"
    if [ ${#APT_REPOS[@]} -gt 0 ]; then
        for REPO in "${APT_REPOS[@]}"; do
            case "$REPO" in
            ppa:*)
                apt-cache policy | grep -E \
                    "\\<https?://ppa\.launchpad\.net/${REPO#ppa:}\\>" \
                    >/dev/null || {
                    lk_console_detail "Adding repository:" "$REPO"
                    lk_keep_trying add-apt-repository \
                        "${APT_ADD_REPOSITORY_ARGS[@]}" "$REPO" &&
                        LK_FILE_REPLACE_NO_CHANGE=0
                }
                ;;
            *)
                lk_die "unknown repo type: $REPO"
                ;;
            esac
        done
    fi
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        _LK_APT_DIRTY=1
    FILE=/etc/apt/apt.conf.d/90${LK_PATH_PREFIX}default
    OLD_FILE=/etc/apt/apt.conf.d/90${LK_PATH_PREFIX}defaults
    maybe_move_old "$OLD_FILE" "$FILE"
    lk_install -m 00644 "$FILE"
    APT_CONF_APPLY=(
        no-install-recommends
        unattended-upgrade
        keep-changed-conffiles
    )
    _FILE=$(
        cd "$LK_BASE/share/apt/apt.conf.d"
        cat "${APT_CONF_APPLY[@]}"
        OPTIONS=(Mail "${LK_UPGRADE_EMAIL:-root}")
        if [ -n "$LK_UPGRADE_EMAIL" ]; then
            OPTIONS+=(MailOnlyOnError false)
        else
            OPTIONS+=(MailOnlyOnError true)
        fi
        if [ "$LK_AUTO_REBOOT" = Y ]; then
            OPTIONS+=(
                Automatic-Reboot true
                Automatic-Reboot-Time "$LK_AUTO_REBOOT_TIME"
            )
        else
            OPTIONS+=(
                Automatic-Reboot false
            )
        fi
        printf 'Unattended-Upgrade::%s "%s";\n' "${OPTIONS[@]}"
    )
    lk_file_replace "$FILE" "$_FILE"

    # See `man invoke-rc.d` for more information
    lk_console_detail \
        "Disabling immediate activation of services installed while provisioning"
    FILE=/usr/sbin/policy-rc.d
    lk_install -m 00755 "$FILE"
    LK_VERBOSE= \
        lk_file_replace -i "^(# |$S*\$)" "$FILE" "$(lk_expand_template -e \
            "$LK_BASE/share/apt/policy-rc.d.template.sh")"

    debconf-set-selections < <(lk_expand_template \
        "$LK_BASE/share/apt/hosting.template.debconf")

    lk_keep_trying lk_apt_update

    if [ -x /usr/local/bin/pip3 ] && ! lk_dpkg_installed python3-pip; then
        PIP3=/usr/local/bin/pip3
        lk_console_message "Removing standalone pip3"
        function pip3_args() {
            python3 \
                -c 'import site; print("\n".join(site.getsitepackages()))' |
                grep '^/usr/local/lib/' |
                while IFS= read -r LINE; do
                    printf '%s %q\n' --path "$LINE"
                done
        }
        function pip3_list() {
            "$PIP3" list "${ARGS[@]}" --format freeze
        }
        function pip3_uninstall() {
            [ ${#UNINSTALL[@]} -eq 0 ] ||
                lk_run_detail \
                    sudo "$PIP3" uninstall --yes "${UNINSTALL[@]}"
        }
        ARGS=($(pip3_args)) ||
            lk_die "no site-packages found in /usr/local"
        # 1. Uninstall everything except pip itself (in case there's an error)
        UNINSTALL=($(pip3_list | sed -E '/^(pip|setuptools|wheel)==/d'))
        pip3_uninstall
        # 2. Uninstall pip
        UNINSTALL=($(pip3_list))
        pip3_uninstall
        # Restore any packages "upgraded" by standalone pip3
        LK_NO_INPUT=1 \
            lk_apt_reinstall_damaged
    fi

    APT_REMOVE=(
        # Recommended by ubuntu-minimal
        rsyslog

        # Recommended by ubuntu-standard
        mlocate

        # Recommended by ubuntu-server
        landscape-common
        lxd
        lxd-agent-loader
        snapd
    )
    [ -n "$LK_UPGRADE_EMAIL" ] ||
        APT_REMOVE+=(
            apt-listchanges
            apticron
        )

    IFS=,
    APT_PACKAGES=($LK_NODE_PACKAGES)
    unset IFS
    . "$LK_BASE/lib/hosting/packages.sh"
    APT_PACKAGES=($(comm -13 \
        <(lk_echo_array APT_SUPPRESS APT_REMOVE | sort -u) \
        <(lk_echo_array APT_PACKAGES | sort -u)))
    [ ${#APT_FILTER[@]} -eq 0 ] ||
        APT_PACKAGES=($(lk_echo_array APT_PACKAGES |
            eval "sed -E$(printf ' -e %q' "${APT_FILTER[@]}")"))

    [ ${#APT_PACKAGES[@]} -eq 0 ] ||
        lk_keep_trying lk_apt_install "${APT_PACKAGES[@]}"
    lk_apt_purge "${APT_REMOVE[@]}"

    lk_console_message "Checking services"
    DISABLE_SERVICES=(
        motd-news.timer
    )
    grep -Fxq "CONFIG_BSD_PROCESS_ACCT=y" "/boot/config-$(uname -r)" ||
        DISABLE_SERVICES+=(atopacct.service)
    for SERVICE in "${DISABLE_SERVICES[@]}"; do
        ! lk_systemctl_exists "$SERVICE" ||
            lk_systemctl_disable_now "$SERVICE"
    done

    if lk_dpkg_installed logrotate; then
        lk_console_message "Checking logrotate"
        _LK_CONF_DELIM=" " \
            lk_conf_set_option su "root adm" /etc/logrotate.conf
        FILE=/etc/logrotate.d/lk-platform
        OLD_FILE=/etc/logrotate.d/${LK_PATH_PREFIX}log
        maybe_move_old "$OLD_FILE" "$FILE"
        lk_install -m 00644 "$FILE"
        _FILE=$(
            LK_PLATFORM_LOGS=$(lk_double_quote "$LK_BASE/var/log/*.log")
            cat "$LK_BASE/share/logrotate.d"/{hosting,default}.template |
                lk_expand_template
        )
        lk_file_replace "$FILE" "$_FILE"
        # Don't run `invoke-rc.d apache2 reload` twice per logrotate
        FILE=/etc/logrotate.d/apache2
        [ ! -e "$FILE" ] ||
            lk_run_detail mv -f "$FILE"{,.disabled}
        # Restore php-fpm options if disabled previously
        FILE=/etc/logrotate.d/php$PHPVER-fpm
        [ ! -e "$FILE.disabled" ] || [ -e "$FILE" ] ||
            lk_run_detail mv -n "$FILE"{.disabled,}
    fi

    if lk_dpkg_installed apt-listchanges apticron; then
        lk_console_message "Checking apticron"
        FILE=/etc/apt/listchanges.conf
        ORIG=$FILE
        [ ! -e "$FILE.orig" ] || ORIG=$FILE.orig
        _FILE=$(lk_mktemp_file)
        lk_delete_on_exit "$_FILE"
        cp "$ORIG" "$_FILE"
        LK_CONF_OPTION_FILE=$_FILE
        (
            unset LK_VERBOSE
            LK_FILE_KEEP_ORIGINAL=0
            lk_conf_set_option -s apt frontend none
            lk_conf_set_option -s apt which both
            lk_conf_set_option -s apt headers true
        )
        lk_file_keep_original "$FILE"
        lk_file_replace -f "$_FILE" "$FILE"

        LK_CONF_OPTION_FILE=/etc/apticron/apticron.conf
        [ -e "$LK_CONF_OPTION_FILE" ] ||
            [ ! -e /usr/lib/apticron/apticron.conf ] ||
            cp -a /usr/lib/apticron/apticron.conf "$LK_CONF_OPTION_FILE"
        get_before_file "$LK_CONF_OPTION_FILE"
        lk_conf_set_option DIFF_ONLY '"1"'
        lk_conf_set_option EMAIL \
            "$(lk_double_quote "${LK_UPGRADE_EMAIL:-root}")"
        lk_conf_set_option LISTCHANGES_PROFILE '"apt"'
        check_after_file
    fi

    lk_console_message "Checking update-motd scripts"
    DIR=/etc/update-motd.d
    for FILE in \
        "$DIR"/*-{fsck-at-reboot,help-text,livepatch,motd-news,release-upgrade}; do
        [ ! -x "$FILE" ] ||
            chmod -v a-x "$FILE"
    done
    # Enable scripts that may have been disabled previously
    for FILE in "$DIR"/*-reboot-required; do
        [ -x "$FILE" ] ||
            chmod -v a+x "$FILE"
    done

    DIR=/etc/skel.${LK_PATH_PREFIX%-}
    lk_console_item \
        "Checking skeleton directory for hosting accounts:" "$DIR"
    cp -naTv /etc/skel "$DIR"
    DIR=$DIR/.ssh
    FILE=$DIR/authorized_keys_${LK_PATH_PREFIX%-}
    if lk_is_bootstrap; then
        if [ -n "${_LK_HOST_KEYS-}" ]; then
            install -d -m 00700 "$DIR"
            lk_install -m 00400 "$FILE"
            lk_file_replace "$FILE" "$_LK_HOST_KEYS"
        fi
    else
        OLD_FILE=$DIR/authorized_keys
        maybe_move_old "$OLD_FILE" "$FILE"
        if [ -s "$FILE" ]; then
            LK_FILE_NO_DIFF=1
            USERS=($(lk_get_standard_users))
            for _USER in ${USERS+"${USERS[@]}"}; do
                _HOME=$(lk_expand_path "~$_USER")
                _DIR=$_HOME/.ssh
                _FILE=$_DIR/authorized_keys_${LK_PATH_PREFIX%-}
                GROUP=$(id -gn "$_USER")
                install -d -m 00700 -o "$_USER" -g "$GROUP" "$_DIR"
                lk_install -m 00400 -o "$_USER" -g "$GROUP" "$_FILE"
                lk_file_replace -f "$FILE" "$_FILE"
                _OLD_FILE=$_DIR/authorized_keys
                if [ -e "$_OLD_FILE" ]; then
                    REMOVE=$(comm -12 \
                        <(sort "$_FILE") \
                        <(sort "$_OLD_FILE") | wc -l)
                    if [ "$REMOVE" -gt 0 ]; then
                        lk_file_replace "$_OLD_FILE" "$(comm -13 \
                            <(sort "$_FILE") \
                            <(sort "$_OLD_FILE"))"
                    fi
                fi
            done
            unset LK_FILE_NO_DIFF
        fi
    fi

    lk_console_message "Checking hosting base directories"
    lk_install -d -m 00751 -g adm /srv/www{,/.tmp,/.opcache}

    lk_console_blank
    LK_NO_LOG=1 \
        lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh" \
        $(! no_upgrade || printf '%s\n' --no-upgrade)

    lk_console_blank
    if lk_is_bootstrap && [ -n "$LK_ADMIN_USERS" ]; then
        IFS=,
        ADMIN_USERS=($LK_ADMIN_USERS)
        unset IFS
        for ADMIN_USER in "${ADMIN_USERS[@]}"; do
            ADMIN_USER_KEY=$(sed -En "/$S$ADMIN_USER\$/p" \
                <<<"${_LK_ADMIN_USER_KEYS-}")
            lk_hosting_user_add_admin \
                "$ADMIN_USER" ${ADMIN_USER_KEY:+"$ADMIN_USER_KEY"}
        done
    fi

    lk_console_message "Checking SSH server"
    unset LK_FILE_REPLACE_NO_CHANGE
    LK_CONF_OPTION_FILE=/etc/ssh/sshd_config
    ! lk_is_bootstrap ||
        [ -z "$LK_ADMIN_USERS" ] ||
        lk_ssh_set_option PermitRootLogin "no"
    lk_ssh_set_option PasswordAuthentication "no"
    lk_ssh_set_option AcceptEnv "LANG LC_*"
    lk_ssh_set_option AuthorizedKeysFile \
        ".ssh/authorized_keys .ssh/authorized_keys_${LK_PATH_PREFIX%-}"
    [ -z "$LK_SSH_TRUSTED_PORT" ] || {
        lk_conf_enable_row "Port 22"
        # Avoid "Directive 'Port' is not allowed within a Match block" by adding
        # "Port TRUSTED_PORT" immediately after "Port 22"
        FILE=$LK_CONF_OPTION_FILE
        grep -Eq "^$S*Port$S+$LK_SSH_TRUSTED_PORT$S*\$" "$FILE" ||
            lk_file_replace "$FILE" < <(sed -E \
                "s/^$S*Port$S+22$S*\$/&\\"$'\n'"Port $LK_SSH_TRUSTED_PORT/" "$FILE")
    }
    # TODO: restore original configuration if restart fails
    lk_is_bootstrap && ! lk_systemctl_running ssh ||
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        lk_run_detail systemctl restart ssh.service

    if lk_dpkg_installed postfix; then
        function get_postconf() {
            lk_require_output postconf -np "$1" |
                sed -E 's/^[^ =]+ ?= ?//'
        }
        function set_postconf() {
            local VALUE
            VALUE=$(get_postconf "$1") && [ "$VALUE" = "$2" ] || {
                lk_run_detail postconf -e "$1 = $2" &&
                    POSTCONF_CHANGE=1
            }
        }
        function unset_postconf() {
            ! get_postconf "$1" >/dev/null || {
                lk_run_detail postconf -X "$1" &&
                    POSTCONF_CHANGE=1
            }
        }
        lk_console_message "Checking Postfix"
        unset POSTCONF_CHANGE
        get_before_file -v /etc/postfix/main.cf
        set_postconf inet_interfaces loopback-only
        FILE=/etc/aliases
        if [ -n "$LK_EMAIL_BLACKHOLE" ]; then
            set_postconf recipient_canonical_maps static:blackhole
            _FILE=$(awk -v "S=$S" -v "blackhole=$LK_EMAIL_BLACKHOLE" '
function maybe_print() {
    if (!printed) {
        print "blackhole:\t" blackhole
        printed = 1
    }
    just_printed = 1
}
tolower($0) ~ "^(blackhole|\"blackhole\")" S "*:" {
    maybe_print()
    next
}
! just_printed || /^[^[:blank:]#]/ {
    print
    just_printed = 0
}
END {
    maybe_print()
}' "$FILE")
        else
            unset_postconf recipient_canonical_maps
            _FILE=$(awk -v "S=$S" '
tolower($0) ~ "^(blackhole|\"blackhole\")" S "*:" {
    just_skipped = 1
    next
}
! just_skipped || /^[^[:blank:]#]/ {
    print
    just_skipped = 0
}' "$FILE")
        fi
        check_after_file
        lk_file_replace "$FILE" "$_FILE"
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_run_detail postalias "$FILE"
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE &&
            ! lk_is_true POSTCONF_CHANGE ||
            { lk_is_bootstrap && ! lk_systemctl_running postfix ||
                lk_run_detail systemctl reload postfix.service; }
    fi

    if lk_dpkg_installed apache2; then
        lk_console_message "Checking Apache"
        unset LK_FILE_REPLACE_NO_CHANGE LK_SYMLINK_NO_CHANGE
        DEFAULT_SITES=(/etc/apache2/sites-enabled/{,000-}default*.conf)
        [ ${#DEFAULT_SITES[@]} -eq "0" ] || {
            lk_console_detail "Disabling sites:" \
                $'\n'"$(lk_echo_array DEFAULT_SITES | lk_basename)"
            lk_file_keep_original "${DEFAULT_SITES[@]}" &&
                rm "${DEFAULT_SITES[@]}" &&
                LK_FILE_REPLACE_NO_CHANGE=0
        }

        APACHE_MODS=(
            # Ubuntu defaults
            access_compat
            alias
            auth_basic
            authn_core
            authn_file
            authz_core
            authz_host
            authz_user
            autoindex
            deflate
            dir
            env
            filter
            mime
            mpm_event
            negotiation
            reqtimeout
            setenvif
            status

            # Extras
            expires
            headers
            http2
            info
            macro
            remoteip
            rewrite
            socache_shmcb
            ssl
        )
        ! lk_dpkg_installed php-fpm || APACHE_MODS+=(
            proxy
            proxy_fcgi
        )
        ! lk_dpkg_installed libapache2-mod-qos ||
            APACHE_MODS+=(
                qos
                unique_id
            )
        APACHE_MODS=($(comm -13 \
            <(lk_echo_array APACHE_MODS_SUPPRESS | sort -u) \
            <(lk_echo_array APACHE_MODS | sort -u)))
        APACHE_MODS_ENABLED=$(a2query -m | awk '{print $1}')
        APACHE_MODS_DISABLE=($(comm -13 \
            <(lk_echo_array APACHE_MODS | sort -u) \
            <(sort -u <<<"$APACHE_MODS_ENABLED")))
        APACHE_MODS_ENABLE=($(comm -23 \
            <(lk_echo_array APACHE_MODS | sort -u) \
            <(sort -u <<<"$APACHE_MODS_ENABLED")))
        [ ${#APACHE_MODS_DISABLE[@]} -eq 0 ] || {
            lk_console_detail "Disabling Apache modules:" \
                $'\n'"$(lk_echo_array APACHE_MODS_DISABLE)"
            a2dismod --force "${APACHE_MODS_DISABLE[@]}" &&
                LK_FILE_REPLACE_NO_CHANGE=0
        }
        [ ${#APACHE_MODS_ENABLE[@]} -eq 0 ] || {
            lk_console_detail "Enabling Apache modules:" \
                $'\n'"$(lk_echo_array APACHE_MODS_ENABLE)"
            a2enmod --force "${APACHE_MODS_ENABLE[@]}" &&
                LK_FILE_REPLACE_NO_CHANGE=0
        }

        FILE=/etc/apache2/conf-available/${LK_PATH_PREFIX}default.conf
        if ! lk_is_bootstrap; then
            lk_console_detail "Checking configuration files"
            OLD_SYMLINK=/etc/apache2/sites-enabled/000-${LK_PATH_PREFIX}default.conf
            [ ! -e "$OLD_SYMLINK" ] || {
                lk_file_backup "$OLD_SYMLINK" &&
                    rm "$OLD_SYMLINK" &&
                    LK_FILE_REPLACE_NO_CHANGE=0
            }
            OLD_FILE=/etc/apache2/sites-available/${LK_PATH_PREFIX}default.conf
            # Move OLD_FILE to its new location in conf-available if possible
            maybe_move_old "$OLD_FILE" "$FILE"
            [ ! -e "$OLD_FILE" ] || {
                lk_file_backup "$OLD_FILE" &&
                    rm "$OLD_FILE" &&
                    LK_FILE_REPLACE_NO_CHANGE=0
            }
        fi
        SSL_DIRECTIVES=$(
            OFFLINE=$(<"$LK_BASE/share/mozilla/ssl-config/latest.json") || exit
            URL=https://ssl-config.mozilla.org/guidelines/latest.json
            ONLINE=$(lk_curl "$URL") ||
                lk_warn "unable to retrieve $URL" || unset ONLINE
            for JSON in ${ONLINE+"$ONLINE"} "$OFFLINE"; do
                jq -r \
                    --arg config intermediate \
                    -f "$LK_BASE/lib/jq/httpd_get_ssl_directives.jq" \
                    <<<"$JSON" ||
                    lk_warn "error processing Mozilla SSL recommendations" ||
                    continue
                exit
            done
            exit 1
        )
        CLOUDFLARE_IPS=$(
            OFFLINE=$(<"$LK_BASE/share/cloudflare/ips/latest.json") || exit
            URL=https://api.cloudflare.com/client/v4/ips
            ONLINE=$(lk_curl "$URL") ||
                lk_warn "unable to retrieve $URL" || unset ONLINE
            for JSON in ${ONLINE+"$ONLINE"} "$OFFLINE"; do
                jq -r '[.result | (.ipv4_cidrs[], .ipv6_cidrs[])] | join(" ")' \
                    <<<"$JSON" ||
                    lk_warn "error processing Cloudflare IP addresses" ||
                    continue
                exit
            done
            exit 1
        )
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$(
            LK_REQUIRE_TRUSTED=${LK_TRUSTED_IP_ADDRESSES:+$'\n'    Require ip ${LK_TRUSTED_IP_ADDRESSES//,/ }}
            TRUSTED_EXPR="127.0.0.0/8,::1"${LK_TRUSTED_IP_ADDRESSES:+,$LK_TRUSTED_IP_ADDRESSES}
            LK_EXPR_TRUSTED="(-R '"${TRUSTED_EXPR//,/"' || -R '"}"')"
            lk_expand_template "$LK_BASE/share/httpd/default-hosting.template.conf"
        )"
        DIR=${FILE%/*}
        lk_symlink \
            "../${DIR##*/}/${FILE##*/}" "${FILE/-available\//-enabled\/}"
        FILE=/etc/letsencrypt/options-ssl-apache.conf
        if [ -s "$FILE" ]; then
            lk_console_detail "Truncating" "$FILE"
            lk_file_keep_original "$FILE"
            : >"$FILE"
            LK_FILE_REPLACE_NO_CHANGE=0
        fi
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE &&
            ! lk_is_false LK_SYMLINK_NO_CHANGE ||
            lk_hosting_mark_dirty "apache2.service"
        IPTABLES_TCP_LISTEN+=(80 443)
    fi

    if lk_dpkg_installed php-fpm; then
        lk_console_message "Checking PHP-FPM"
        if ! lk_is_bootstrap; then
            lk_console_detail "Checking configuration files"
            OLD_POOLS=(/etc/php/*/fpm/pool.d.orig/*.conf)
            [ ${#OLD_POOLS[@]} -eq 0 ] || {
                lk_file_keep_original "${OLD_POOLS[@]}" &&
                    rm "${OLD_POOLS[@]}" &&
                    for FILE in /etc/php/*/fpm/pool.d.orig/*.orig; do
                        mv -nv "$FILE" "${FILE/.orig/}"
                    done &&
                    rmdir /etc/php/*/fpm/pool.d.orig
            }
        fi

        POOLS=(/etc/php/*/fpm/pool.d/*.conf)
        [ ${#POOLS[@]} -eq 0 ] || {
            # The listen directive of a custom pool will always contain "$pool"
            lk_mapfile DEFAULT_POOLS \
                <(grep -Pl "^listen$S*=(.(?!\\\$pool\\b))*\$" "${POOLS[@]}")
            [ ${#DEFAULT_POOLS[@]} -eq 0 ] || {
                lk_console_detail "Disabling pools:" \
                    $'\n'"$(lk_echo_array DEFAULT_POOLS | lk_basename)"
                lk_file_keep_original "${DEFAULT_POOLS[@]}" &&
                    rm "${DEFAULT_POOLS[@]}" &&
                    lk_hosting_mark_dirty "php$PHPVER-fpm.service"
            }
        }

        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/systemd/system/php$PHPVER-fpm.service.d/90-${LK_PATH_PREFIX}override.conf
        OLD_FILE=/etc/systemd/system/php$PHPVER-fpm.service.d/override.conf
        lk_install -d -m 00755 "${FILE%/*}"
        maybe_move_old "$OLD_FILE" "$FILE"
        lk_install -m 00644 "$FILE"
        lk_file_replace \
            -f "$LK_BASE/share/systemd/php-fpm.service" \
            "$FILE"
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE || {
            lk_run_detail systemctl daemon-reload &&
                lk_hosting_mark_dirty "php$PHPVER-fpm.service"
        }

        lk_console_message "Checking WP-CLI"
        FILE=/usr/local/bin/wp
        lk_install -m 00755 "$FILE"
        if [ -s "$FILE" ]; then
            lk_run_detail "$FILE" cli update --yes
        else
            lk_console_detail "Installing WP-CLI to" "$FILE"
            _FILE=$(lk_mktemp_file)
            lk_delete_on_exit "$_FILE"
            URL=https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
            curl "${CURL_OPTIONS[@]}" --output "$_FILE" "$URL" ||
                lk_die "unable to download: $URL"
            cp "$_FILE" "$FILE"
        fi

        lk_keep_trying lk_git_provision_repo -fs \
            -o :adm \
            -n opcache-gui \
            https://github.com/lkrms/opcache-gui.git \
            /opt/opcache-gui
    fi

    if lk_dpkg_installed mariadb-server; then
        lk_console_message "Checking MariaDB (MySQL)"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/mysql/mariadb.conf.d/90-${LK_PATH_PREFIX}default.cnf
        OLD_FILE=/etc/mysql/mariadb.conf.d/90-${LK_PATH_PREFIX}defaults.cnf
        lk_install -d -m 00755 "${FILE%/*}"
        maybe_move_old "$OLD_FILE" "$FILE"
        lk_install -m 00644 "$FILE"
        # TODO: calculate default LK_MYSQL_MAX_CONNECTIONS (must exceed the sum
        # of pm.max_children across all PHP-FPM pools)
        _FILE=$(
            LK_MYSQL_MAX_CONNECTIONS=${LK_MYSQL_MAX_CONNECTIONS:-301}
            LK_INNODB_BUFFER_SIZE=${LK_INNODB_BUFFER_SIZE:-128M}
            BUFFER_BYTES=$(lk_mysql_bytes "$LK_INNODB_BUFFER_SIZE") || exit
            ((LK_INNODB_BUFFERS = (BUFFER_BYTES / 1024 ** 2 - 1) / 1024 + 1))
            lk_expand_template \
                "$LK_BASE/share/mariadb.conf.d/default-hosting.template.cnf"
        )
        lk_file_replace "$FILE" "$_FILE"
        if lk_is_bootstrap; then
            # Ubuntu 16.04's MariaDB packages don't install `mariadb.service`
            # and later versions install a `mysql.service` alias, so use
            # `mysql.service` for maximum portability
            lk_run_detail systemctl start mysql.service
            if [ -n "$LK_MYSQL_USERNAME" ]; then
                lk_tty_detail "Creating MariaDB administrator:" \
                    "$LK_MYSQL_USERNAME"
                mysql -uroot <<EOF
GRANT ALL PRIVILEGES ON *.*
TO '$(lk_mysql_escape "$LK_MYSQL_USERNAME")'@'localhost'
IDENTIFIED BY '$(lk_mysql_escape "$LK_MYSQL_PASSWORD")'
WITH GRANT OPTION
EOF
            fi
        else
            ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
                lk_run_detail systemctl restart mysql.service
        fi
    fi

    if lk_dpkg_installed memcached; then
        lk_console_message "Checking Memcached"
        LK_CONF_OPTION_FILE=/etc/memcached.conf
        get_before_file "$LK_CONF_OPTION_FILE"
        _LK_CONF_DELIM=" " \
            lk_conf_set_option -m "${LK_MEMCACHED_MEMORY_LIMIT:-64}"
        check_after_file
        lk_is_bootstrap && ! lk_systemctl_running memcached ||
            ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_run_detail systemctl restart memcached.service
    fi

    if lk_is_bootstrap && [ -n "$LK_HOST_ACCOUNT" ]; then
        lk_hosting_user_add "$LK_HOST_ACCOUNT"
        if [ -n "$LK_HOST_DOMAIN" ]; then
            [ "$LK_HOST_SITE_ENABLE" = Y ] || {
                FILE=$LK_BASE/etc/sites/${LK_HOST_DOMAIN,,}.conf
                lk_install -m 00660 -g adm "$FILE" &&
                    lk_file_replace "$FILE" \
                        "$(SITE_ENABLE=N lk_get_shell_var SITE_ENABLE)"
            }
            HOST_SITE_ROOT=$(lk_expand_path "~$LK_HOST_ACCOUNT")
            lk_hosting_site_configure "$LK_HOST_DOMAIN" "$HOST_SITE_ROOT"
        fi
    fi

    ! lk_hosting_is_dirty "legacy-sites.migration" ||
        lk_hosting_site_migrate_legacy

    if ! lk_hosting_site_list | wc -l | tr -d ' ' | grep -Fxq 0; then
        lk_console_blank
        lk_hosting_site_configure_all
    fi

    unset SKIP_TEST
    if lk_dpkg_installed php-fpm apache2; then
        if lk_hosting_is_dirty "php$PHPVER-fpm.service" ||
            lk_hosting_is_dirty "apache2.service"; then
            lk_console_message "Checking hosting services"
            lk_hosting_php_fpm_config_test &&
                lk_hosting_httpd_config_test ||
                lk_console_error -r "Resolve invalid settings and try again" ||
                lk_die ""
            SKIP_TEST=1
        fi
    fi

    if lk_dpkg_installed php-fpm &&
        lk_hosting_is_dirty "php$PHPVER-fpm.service"; then
        lk_hosting_php_fpm_config_apply ${SKIP_TEST+-s} "$PHPVER"
    fi

    if lk_dpkg_installed apache2 &&
        lk_hosting_is_dirty "apache2.service"; then
        lk_hosting_httpd_config_apply ${SKIP_TEST+-s}
    fi

    if lk_dpkg_installed fail2ban; then
        lk_console_message "Checking Fail2ban"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/fail2ban/jail.d/${LK_PATH_PREFIX}default.local
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$(
            LK_IGNOREIP=${LK_TRUSTED_IP_ADDRESSES:+ ${LK_TRUSTED_IP_ADDRESSES//,/ }}
            lk_expand_template \
                "$LK_BASE/share/fail2ban/default-hosting.template.conf"
        )"
        maybe_restore_original /etc/fail2ban/jail.conf
        lk_is_bootstrap && ! lk_systemctl_running fail2ban ||
            ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_run_detail systemctl restart fail2ban.service
    fi

    lk_console_message "Checking firewall (iptables)"
    unset LK_FILE_REPLACE_NO_CHANGE
    if [ "$LK_REJECT_OUTPUT" != N ]; then
        HOSTS=($(
            grep -Eo "^[^#]+${S}https?://[^/[:blank:]]+" /etc/apt/sources.list |
                sed -E 's/.*:\/\///' |
                sort -u
        )) || lk_die "no active repositories in /etc/apt/sources.list"
        HOSTS+=(
            entropy.ubuntu.com
            keyserver.ubuntu.com
            launchpad.net
            ppa.launchpad.net

            pypi.org
            bootstrap.pypa.io
            files.pythonhosted.org

            "https://api.github.com/meta|.web[]\\,.api[]\\,.git[]"
        )
        if lk_node_service_enabled php-fpm; then
            HOSTS+=(
                api.wordpress.org
                downloads.wordpress.org
                plugins.svn.wordpress.org
                wordpress.org
            )
        fi
        IFS=,
        LK_ACCEPT_OUTPUT_HOSTS=${HOSTS[*]}${LK_ACCEPT_OUTPUT_HOSTS:+,$LK_ACCEPT_OUTPUT_HOSTS}
        unset IFS
    fi
    FILE=$(lk_mktemp_file)
    lk_delete_on_exit "$FILE"
    for i in "" 6; do
        lk_expand_template -e \
            "$LK_BASE/share/iptables/ip${i}tables.template.rules" >"$FILE"
        # Remove security table rules if not supported by the kernel
        grep -Eq '^CONFIG_IP6?_NF_SECURITY=(y|m)$' "/boot/config-$(uname -r)" ||
            LK_VERBOSE= LK_FILE_BACKUP_TAKE= lk_file_replace "$FILE" < <(awk '
/^\*security$/  { skip = 1 }
!skip           { print }
/^COMMIT$/      { skip = 0 }' "$FILE")
        "ip${i}tables-restore" --test <"$FILE" &&
            lk_file_replace -f "$FILE" "/etc/iptables/rules.v${i:-4}" ||
            lk_die "error updating iptables"
    done
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE || {
        lk_run_detail iptables-restore </etc/iptables/rules.v4 &&
            lk_run_detail ip6tables-restore </etc/iptables/rules.v6
    } || lk_die "error applying iptables rules"

    no_upgrade ||
        lk_apt_upgrade_all

    lk_hosting_configure_backup

    lk_console_message "Cleaning up"
    no_upgrade ||
        lk_apt_purge_removed
    [ ! -e /etc/glances ] ||
        lk_run_detail rm -Rf /etc/glances
    [ ! -e /etc/apt/listchanges.conf.orig ] ||
        lk_dpkg_installed apt-listchanges ||
        lk_run_detail rm -f /etc/apt/listchanges.conf.orig

    lk_console_blank
    lk_console_success "Provisioning complete"

    exit
}

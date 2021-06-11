#!/bin/bash

# shellcheck disable=SC2001,SC2086,SC2206,SC2088
#
# <UDF name="LK_NODE_HOSTNAME" label="Short hostname" example="web01-dev-syd" />
# <UDF name="LK_NODE_FQDN" label="Host FQDN" example="web01-dev-syd.linode.linacreative.com" />
# <UDF name="LK_NODE_TIMEZONE" label="System timezone" default="Australia/Sydney" />
# <UDF name="LK_NODE_SERVICES" label="Services to install and configure" manyof="apache+php,mysql,memcached,fail2ban,wp-cli,jre" default="" />
# <UDF name="LK_NODE_PACKAGES" label="Additional packages to install (comma-delimited)" default="" />
# <UDF name="LK_HOST_DOMAIN" label="Initial hosting domain" example="clientname.com.au" default="" />
# <UDF name="LK_HOST_ACCOUNT" label="Initial hosting account name (default: based on domain)" example="clientname" default="" />
# <UDF name="LK_HOST_SITE_ENABLE" label="Enable initial hosting site at launch" oneof="Y,N" default="N" />
# <UDF name="LK_ADMIN_USERS" label="Admin users to create (comma-delimited)" default="linac" />
# <UDF name="LK_ADMIN_EMAIL" label="Forwarding address for system email" example="tech@linacreative.com" />
# <UDF name="LK_TRUSTED_IP_ADDRESSES" label="Trusted IP addresses (comma-delimited)" example="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" default="" />
# <UDF name="LK_SSH_TRUSTED_ONLY" label="Block SSH access from untrusted IP addresses (trusted IP addresses required)" oneof="Y,N" default="N" />
# <UDF name="LK_SSH_JUMP_HOST" label="SSH jump proxy: hostname and optional port" example="jump.linacreative.com:9922" default="" />
# <UDF name="LK_SSH_JUMP_USER" label="SSH jump proxy: default user" default="" />
# <UDF name="LK_SSH_JUMP_KEY" label="SSH jump proxy: default key (must match the comment field of one installed key)" default="" />
# <UDF name="LK_REJECT_OUTPUT" label="Reject outgoing traffic by default" oneof="Y,N" default="N" />
# <UDF name="LK_ACCEPT_OUTPUT_HOSTS" label="Accept outgoing traffic to hosts (comma-delimited)" example="192.168.128.0/17,ip-ranges.amazonaws.com" default="" />
# <UDF name="LK_MYSQL_USERNAME" label="MySQL admin username (password required)" example="dbadmin" default="" />
# <UDF name="LK_MYSQL_PASSWORD" label="MySQL admin password (ignored if username not set)" default="" />
# <UDF name="LK_INNODB_BUFFER_SIZE" label="InnoDB buffer size (~80% of RAM for MySQL-only servers)" oneof="128M,256M,512M,768M,1024M,1536M,2048M,2560M,3072M,4096M,5120M,6144M,7168M,8192M" default="256M" />
# <UDF name="LK_OPCACHE_MEMORY_CONSUMPTION" label="PHP OPcache size" oneof="128,256,512,768,1024" default="256" />
# <UDF name="LK_PHP_SETTINGS" label="php.ini settings (user can overwrite, comma-delimited, flag assumed if value is On/True/Yes or Off/False/No)" example="upload_max_filesize=24M,display_errors=On" default="" />
# <UDF name="LK_PHP_ADMIN_SETTINGS" label="Enforced php.ini settings (comma-delimited)" example="post_max_size=50M,log_errors=Off" default="" />
# <UDF name="LK_MEMCACHED_MEMORY_LIMIT" label="Memcached size" oneof="64,128,256,512,768,1024" default="256" />
# <UDF name="LK_SMTP_RELAY" label="SMTP relay (system-wide)" example="[mail.clientname.com.au]:587" default="" />
# <UDF name="LK_EMAIL_BLACKHOLE" label="Email black hole (system-wide, STAGING ONLY)" example="/dev/null" default="" />
# <UDF name="LK_UPGRADE_EMAIL" label="Email address for unattended upgrade notifications" example="unattended-upgrades@linode.linacreative.com" />
# <UDF name="LK_AUTO_REBOOT" label="Reboot automatically after unattended upgrades" oneof="Y,N" />
# <UDF name="LK_AUTO_REBOOT_TIME" label="Preferred automatic reboot time" oneof="02:00,03:00,04:00,05:00,06:00,07:00,08:00,09:00,10:00,11:00,12:00,13:00,14:00,15:00,16:00,17:00,18:00,19:00,20:00,21:00,22:00,23:00,00:00,01:00,now" default="02:00" />
# <UDF name="LK_AUTO_BACKUP_SCHEDULE" label="Automatic backup schedule (format: 0-59 0-23 1-31 1-12|jan-dec 0-7|sun-sat)" example="0 1 * * *" default="" />
# <UDF name="LK_SNAPSHOT_HOURLY_MAX_AGE" label="Backup: hourly snapshot max age (hours, -1 = no maximum)" example="72" default="24" />
# <UDF name="LK_SNAPSHOT_DAILY_MAX_AGE" label="Backup: daily snapshot max age (days, -1 = no maximum)" example="14" default="7" />
# <UDF name="LK_SNAPSHOT_WEEKLY_MAX_AGE" label="Backup: weekly snapshot max age (weeks, -1 = no maximum)" example="-1" default="52" />
# <UDF name="LK_SNAPSHOT_FAILED_MAX_AGE" label="Backup: failed snapshot max age (days, -1 = no maximum)" default="28" />
# <UDF name="LK_PATH_PREFIX" label="Prefix for files installed by lk-platform" default="lk-" />
# <UDF name="LK_DEBUG" label="Create trace output from provisioning script" oneof="Y,N" default="N" />
# <UDF name="LK_SHUTDOWN_ACTION" label="Reboot or power down after provisioning" oneof="reboot,poweroff" default="reboot" />
# <UDF name="LK_SHUTDOWN_DELAY" label="Delay before shutdown/reboot after provisioning (in minutes)" default="0" />
# <UDF name="LK_PLATFORM_BRANCH" label="lk-platform tracking branch" oneof="master,develop,provision-hosting" default="master" />

SCRIPT_VARS=$(
    unset BASH_EXECUTION_STRING
    declare -p
)
SCRIPT_ENV=$(printenv | sed '/^LS_COLORS=/d' | sort)

# Use lk_bash_udf_defaults to regenerate the following after changes above
export -n \
    LK_NODE_HOSTNAME=${LK_NODE_HOSTNAME-} \
    LK_NODE_FQDN=${LK_NODE_FQDN-} \
    LK_NODE_TIMEZONE=${LK_NODE_TIMEZONE:-Australia/Sydney} \
    LK_NODE_SERVICES=${LK_NODE_SERVICES-} \
    LK_NODE_PACKAGES=${LK_NODE_PACKAGES-} \
    LK_HOST_DOMAIN=${LK_HOST_DOMAIN-} \
    LK_HOST_ACCOUNT=${LK_HOST_ACCOUNT-} \
    LK_HOST_SITE_ENABLE=${LK_HOST_SITE_ENABLE:-N} \
    LK_ADMIN_USERS=${LK_ADMIN_USERS:-linac} \
    LK_ADMIN_EMAIL=${LK_ADMIN_EMAIL-} \
    LK_TRUSTED_IP_ADDRESSES=${LK_TRUSTED_IP_ADDRESSES-} \
    LK_SSH_TRUSTED_ONLY=${LK_SSH_TRUSTED_ONLY:-N} \
    LK_SSH_JUMP_HOST=${LK_SSH_JUMP_HOST-} \
    LK_SSH_JUMP_USER=${LK_SSH_JUMP_USER-} \
    LK_SSH_JUMP_KEY=${LK_SSH_JUMP_KEY-} \
    LK_REJECT_OUTPUT=${LK_REJECT_OUTPUT:-N} \
    LK_ACCEPT_OUTPUT_HOSTS=${LK_ACCEPT_OUTPUT_HOSTS-} \
    LK_MYSQL_USERNAME=${LK_MYSQL_USERNAME-} \
    LK_MYSQL_PASSWORD=${LK_MYSQL_PASSWORD-} \
    LK_INNODB_BUFFER_SIZE=${LK_INNODB_BUFFER_SIZE:-256M} \
    LK_OPCACHE_MEMORY_CONSUMPTION=${LK_OPCACHE_MEMORY_CONSUMPTION:-256} \
    LK_PHP_SETTINGS=${LK_PHP_SETTINGS-} \
    LK_PHP_ADMIN_SETTINGS=${LK_PHP_ADMIN_SETTINGS-} \
    LK_MEMCACHED_MEMORY_LIMIT=${LK_MEMCACHED_MEMORY_LIMIT:-256} \
    LK_SMTP_RELAY=${LK_SMTP_RELAY-} \
    LK_EMAIL_BLACKHOLE=${LK_EMAIL_BLACKHOLE-} \
    LK_UPGRADE_EMAIL=${LK_UPGRADE_EMAIL-} \
    LK_AUTO_REBOOT=${LK_AUTO_REBOOT-} \
    LK_AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME:-02:00} \
    LK_AUTO_BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE-} \
    LK_SNAPSHOT_HOURLY_MAX_AGE=${LK_SNAPSHOT_HOURLY_MAX_AGE:-24} \
    LK_SNAPSHOT_DAILY_MAX_AGE=${LK_SNAPSHOT_DAILY_MAX_AGE:-7} \
    LK_SNAPSHOT_WEEKLY_MAX_AGE=${LK_SNAPSHOT_WEEKLY_MAX_AGE:-52} \
    LK_SNAPSHOT_FAILED_MAX_AGE=${LK_SNAPSHOT_FAILED_MAX_AGE:-28} \
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-} \
    LK_DEBUG=${LK_DEBUG:-N} \
    LK_SHUTDOWN_ACTION=${LK_SHUTDOWN_ACTION:-reboot} \
    LK_SHUTDOWN_DELAY=${LK_SHUTDOWN_DELAY:-0} \
    LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

[ ! "$LK_DEBUG" = Y ] || {
    TRACE_FILE=/var/log/${LK_PATH_PREFIX}install.trace
    install -m 00640 -g adm /dev/null "$TRACE_FILE"
    exec 4>>"$TRACE_FILE"
    BASH_XTRACEFD=4
    set -x
}

set -euo pipefail
shopt -s nullglob
lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (exit $s) && false || exit; }

FIELD_ERRORS=$(
    STATUS=0
    function _list() {
        eval "local FN=\$1 $2=\$$2 IFS=, NULL=1 VALID=1 SELECTED i"
        shift
        SELECTED=(${!1})
        unset IFS
        for i in ${SELECTED[@]+"${SELECTED[@]}"}; do
            eval "$1=\$i"
            [ -z "${!1}" ] || { NULL=0 && "$FN" "$@" || VALID=0; }
        done
        [ "$VALID" -eq 1 ] &&
            { [ "${REQUIRED:-0}" -eq 0 ] || [ "$NULL" -eq 0 ] ||
                { printf "Required: %s\n" "$1" && STATUS=1 && false; }; }
    }
    function not_null() {
        [ -n "${!1}" ] ||
            { printf "Required: %s\n" "$1" && STATUS=1 && false; }
    }
    function valid() {
        ! { [ "${REQUIRED:-0}" -eq 0 ] || not_null "$1"; } ||
            [ -z "${!1}" ] || {
            [[ "${!1}" =~ $2 ]] ||
                { printf "Invalid %s: %q\n" "$1" "${!1}" && STATUS=1 && false; }
        }
    }
    function valid_list() {
        _list valid "$@"
    }
    function one_of() {
        ! { [ "${REQUIRED:-0}" -eq 0 ] || not_null "$1"; } ||
            [ -z "${!1}" ] || {
            { [ $# -gt 1 ] && printf '%s\n' "${@:2}" || cat; } |
                grep -Fx "${!1}" >/dev/null ||
                { printf "Unknown %s: %q\n" "$1" "${!1}" && STATUS=1 && false; }
        }
    }
    function many_of() {
        _list one_of "$@"
    }

    DOMAIN_PART_REGEX="[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?"
    DOMAIN_NAME_REGEX="$DOMAIN_PART_REGEX(\\.$DOMAIN_PART_REGEX)+"
    EMAIL_ADDRESS_REGEX="[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~]([-a-zA-Z0-9.!#\$%&'*+/=?^_\`{|}~]{,62}[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~])?@$DOMAIN_NAME_REGEX"
    LINUX_USERNAME_REGEX="[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\\\$)"
    MYSQL_USERNAME_REGEX="[a-zA-Z0-9_]+"
    # https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source
    DPKG_SOURCE_REGEX="[a-z0-9][-a-z0-9+.]+"

    _O="(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])"
    IPV4_REGEX="($_O\\.){3}$_O"
    IPV4_OPT_PREFIX_REGEX="$IPV4_REGEX(/(3[0-2]|[12][0-9]|[1-9]))?"

    _H="[0-9a-fA-F]{1,4}"
    _P="/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])"
    IPV6_REGEX="(($_H:){7}(:|$_H)|($_H:){6}(:|:$_H)|($_H:){5}(:|(:$_H){1,2})|($_H:){4}(:|(:$_H){1,3})|($_H:){3}(:|(:$_H){1,4})|($_H:){2}(:|(:$_H){1,5})|$_H:(:|(:$_H){1,6})|:(:|(:$_H){1,7}))"
    IPV6_OPT_PREFIX_REGEX="$IPV6_REGEX($_P)?"

    IP_OPT_PREFIX_REGEX="($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX)"
    HOST_REGEX="($IPV4_REGEX|$IPV6_REGEX|$DOMAIN_PART_REGEX|$DOMAIN_NAME_REGEX)"
    HOST_OPT_PREFIX_REGEX="($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX|$DOMAIN_PART_REGEX|$DOMAIN_NAME_REGEX)"

    PHP_SETTING_NAME_REGEX="[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*"
    PHP_SETTING_REGEX="$PHP_SETTING_NAME_REGEX=.+"

    # required fields
    REQUIRED=1
    valid LK_NODE_HOSTNAME "^$DOMAIN_PART_REGEX\$"
    valid LK_NODE_FQDN "^$DOMAIN_NAME_REGEX\$"
    # if tzdata isn't part of the image, `timedatectl list-timezones` will only
    # list UTC
    if [ -e /usr/share/zoneinfo/Australia/Sydney ]; then
        one_of LK_NODE_TIMEZONE < <(timedatectl list-timezones)
    else
        not_null LK_NODE_TIMEZONE
    fi
    valid LK_ADMIN_EMAIL "^$EMAIL_ADDRESS_REGEX\$"
    valid LK_UPGRADE_EMAIL "^$EMAIL_ADDRESS_REGEX\$"
    one_of LK_AUTO_REBOOT Y N

    # optional fields
    REQUIRED=0
    many_of LK_NODE_SERVICES \
        "apache+php" \
        "mysql" \
        "memcached" \
        "fail2ban" \
        "wp-cli" \
        "jre"
    valid_list LK_NODE_PACKAGES "^$DPKG_SOURCE_REGEX\$"
    valid LK_HOST_DOMAIN "^$DOMAIN_NAME_REGEX\$"
    valid LK_HOST_ACCOUNT "^$LINUX_USERNAME_REGEX\$"
    [ -z "$LK_HOST_DOMAIN" ] || REQUIRED=1
    one_of LK_HOST_SITE_ENABLE Y N
    REQUIRED=0
    valid_list LK_ADMIN_USERS "^$LINUX_USERNAME_REGEX\$"
    [ ! "$LK_SSH_TRUSTED_ONLY" = Y ] || REQUIRED=1
    valid_list LK_TRUSTED_IP_ADDRESSES "^$IP_OPT_PREFIX_REGEX\$"
    REQUIRED=0
    one_of LK_SSH_TRUSTED_ONLY Y N
    valid LK_SSH_JUMP_HOST "^$HOST_REGEX\$"
    valid LK_SSH_JUMP_USER "^$LINUX_USERNAME_REGEX\$"
    valid LK_SSH_JUMP_KEY "^[-a-zA-Z0-9_]+\$"
    one_of LK_REJECT_OUTPUT Y N
    valid_list LK_ACCEPT_OUTPUT_HOSTS "^$HOST_OPT_PREFIX_REGEX\$"
    valid LK_MYSQL_USERNAME "^$MYSQL_USERNAME_REGEX\$"
    [ -z "$LK_MYSQL_USERNAME" ] || not_null LK_MYSQL_PASSWORD
    valid LK_INNODB_BUFFER_SIZE "^[0-9]+[kmgtpeKMGTPE]?\$"
    valid LK_OPCACHE_MEMORY_CONSUMPTION "^[0-9]+\$"
    valid_list LK_PHP_SETTINGS "^$PHP_SETTING_REGEX\$"
    valid_list LK_PHP_ADMIN_SETTINGS "^$PHP_SETTING_REGEX\$"
    valid LK_MEMCACHED_MEMORY_LIMIT "^[0-9]+\$"
    valid LK_SMTP_RELAY "^($HOST_REGEX|\\[$HOST_REGEX\\])(:[0-9]+)?\$"
    # TODO: validate LK_EMAIL_BLACKHOLE
    [ ! "$LK_AUTO_REBOOT" = Y ] || REQUIRED=1
    valid LK_AUTO_REBOOT_TIME "^(([01][0-9]|2[0-3]):[0-5][0-9]|now)\$"
    REQUIRED=0
    # TODO: validate LK_AUTO_BACKUP_SCHEDULE
    valid LK_SNAPSHOT_HOURLY_MAX_AGE "^(-1|[0-9]+)\$"
    valid LK_SNAPSHOT_DAILY_MAX_AGE "^(-1|[0-9]+)\$"
    valid LK_SNAPSHOT_WEEKLY_MAX_AGE "^(-1|[0-9]+)\$"
    valid LK_SNAPSHOT_FAILED_MAX_AGE "^(-1|[0-9]+)\$"
    valid LK_PATH_PREFIX "^[a-zA-Z0-9]{2,3}-\$"
    one_of LK_DEBUG Y N
    one_of LK_SHUTDOWN_ACTION reboot poweroff
    valid LK_SHUTDOWN_DELAY "^[0-9]+\$"
    # TODO: validate LK_PLATFORM_BRANCH
    exit $STATUS
) || lk_die "$(printf '%s\n' "invalid fields" \
    "  - ${FIELD_ERRORS//$'\n'/$'\n'  - }")"

[ "$EUID" -eq 0 ] || lk_die "not running as root"
[ "$(uname -s)" = Linux ] || lk_die "not running on Linux"
[ "$(lsb_release -si)" = Ubuntu ] || lk_die "not running on Ubuntu"

KEYS_FILE=/root/.ssh/authorized_keys
[ -s "$KEYS_FILE" ] || lk_die "no public keys at $KEYS_FILE"

LK_HOST_DOMAIN=${LK_HOST_DOMAIN#www.}
LK_HOST_ACCOUNT=${LK_HOST_ACCOUNT:-${LK_HOST_DOMAIN%%.*}}

# The following functions are the minimum required to install lk-platform before
# sourcing core.sh and everything else required to provision the system

function lk_dpkg_installed() {
    local STATUS
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}' "$1" 2>/dev/null) &&
        [ "$STATUS" = installed ]
}

function lk_apt_update() {
    lk_console_message "Updating APT package indexes"
    lk_keep_trying apt-get -q update
}

function lk_apt_install() {
    lk_console_item "Installing APT package(s):" "$(printf '%s\n' "$@")"
    lk_keep_trying \
        apt-get --no-install-recommends --no-install-suggests -yq install "$@"
}

function lk_date_log() {
    date +"%Y-%m-%d %H:%M:%S %z"
}

function lk_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(lk_date_log)" "$LINE"
    done
}

function lk_console_message() {
    echo "\
${_LK_TTY_PREFIX-==> }\
${1//$'\n'/$'\n'"${_LK_TTY_SPACES-  }"}" >&"${_LK_FD:-2}"
}

function lk_console_item() {
    lk_console_message "$1$(
        [ "${2/$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"$2"
    )"
}

#function lk_console_detail() {
#    local _LK_TTY_PREFIX="   -> " _LK_TTY_SPACES="    "
#    [ $# -le 1 ] &&
#        lk_console_message "$1" ||
#        lk_console_item "$1" "$2"
#}

#function lk_file_keep_original() {
#    [ ! -e "$1" ] ||
#        cp -nav "$1" "$1.orig"
#}

# edit_file FILE SEARCH_PATTERN REPLACE_PATTERN [ADD_TEXT]
function edit_file() {
    local SED_SCRIPT="0,/$2/{s/$2/$3/}" BEFORE AFTER
    [ -f "$1" ] || [ -n "${4-}" ] || lk_die "file not found: $1"
    [ "${MATCH_MANY:-N}" = "N" ] || SED_SCRIPT="s/$2/$3/"
    if grep -Eq -e "$2" "$1" 2>/dev/null; then
        lk_file_keep_original "$1"
        BEFORE="$(cat "$1")"
        AFTER="$(sed -E "$SED_SCRIPT" "$1")"
        [ "$BEFORE" = "$AFTER" ] || {
            sed -Ei "$SED_SCRIPT" "$1"
        }
    elif [ -n "${4-}" ]; then
        echo "$4" >>"$1"
    else
        lk_die "no line matching $2 in $1"
    fi
    [ "${EDIT_FILE_LOG:-Y}" = "N" ] || lk_console_diff "$1"
}

function lk_keep_trying() {
    local MAX_ATTEMPTS=${LK_KEEP_TRYING_MAX:-10} \
        ATTEMPT=1 WAIT=5 LAST_WAIT=3 NEW_WAIT EXIT_STATUS
    if ! "$@"; then
        while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
            lk_console_message "Command failed:" "$*" ${LK_RED+"$LK_RED"}
            lk_console_detail "Waiting $WAIT seconds"
            sleep "$WAIT"
            ((NEW_WAIT = WAIT + LAST_WAIT))
            LAST_WAIT=$WAIT
            WAIT=$NEW_WAIT
            lk_console_detail "Retrying (attempt $((++ATTEMPT))/$MAX_ATTEMPTS)"
            if "$@"; then
                return
            else
                EXIT_STATUS=$?
            fi
        done
        return "$EXIT_STATUS"
    fi
}

# these are ONLY suitable for filtering trusted addresses (inadequate for validation)
function is_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$ ]]
}

function is_ipv6() {
    [[ "$1" =~ ^(([0-9a-fA-F]{1,4}:)*|:)+(:|(:[0-9a-fA-F]{1,4})*)+(/[0-9]+)?$ ]]
}

function iptables() {
    command iptables "$@"
    command ip6tables "$@"
}

LOCK_FILE=/tmp/${LK_PATH_PREFIX}install.lock
exec 9>"$LOCK_FILE"
flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"

LOG_FILE=/var/log/${LK_PATH_PREFIX}install.log
OUT_FILE=/var/log/${LK_PATH_PREFIX}install.out
install -m 00640 -g adm /dev/null "$LOG_FILE"
install -m 00640 -g adm /dev/null "$OUT_FILE"
exec > >(tee >(lk_log >>"$OUT_FILE")) 2>&1
exec 3> >(tee >(lk_log >>"$LOG_FILE") >&1)
_LK_FD=3

S="[[:space:]]"
P="${LK_PATH_PREFIX%-}_"
DECLARE_LK_DATE_LOG=$(declare -f lk_date_log)
export LK_BASE=/opt/lk-platform \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    PIP_NO_INPUT=1

lk_console_message "Bootstrapping Ubuntu for hosting"
lk_console_item "Environment:" "$SCRIPT_ENV"
[ ! "$LK_DEBUG" = Y ] ||
    lk_console_item "Variables:" "$SCRIPT_VARS"

IMAGE_BASE_PACKAGES=($(apt-mark showmanual))
lk_console_item "Pre-installed packages:" \
    "$(printf '%s\n' "${IMAGE_BASE_PACKAGES[@]}")"

IPV4_ADDRESS=$(
    for REGEX in \
        '^(127|10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.' \
        '^127\.'; do
        ip a |
            awk '/inet / { print $2 }' |
            grep -Ev "$REGEX" |
            head -n1 |
            sed -E 's/\/[0-9]+$//' && break
    done
) || IPV4_ADDRESS=
lk_console_item "IPv4 address:" "${IPV4_ADDRESS:-<none>}"

IPV6_ADDRESS=$(
    for REGEX in \
        '^(::1/128|fe80::|f[cd])' \
        '^::1/128'; do
        ip a |
            awk '/inet6 / { print $2 }' |
            grep -Eiv "$REGEX" |
            head -n1 |
            sed -E 's/\/[0-9]+$//' && break
    done
) || IPV6_ADDRESS=
lk_console_item "IPv6 address:" "${IPV6_ADDRESS:-<none>}"

lk_dpkg_installed git || {
    lk_apt_update
    lk_apt_install git
}

lk_console_item "Downloading lk-platform to" "$LK_BASE"
install -v -d -m 02775 -g adm "$LK_BASE"
if [ -z "$(ls -A "$LK_BASE")" ]; then
    (
        umask 002
        lk_keep_trying \
            git clone -b "$LK_PLATFORM_BRANCH" \
            "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
    )
fi

TERM='' . "$LK_BASE/lib/bash/common.sh"
lk_include debian hosting provision

install -d -m 02775 -g adm "$LK_BASE"/{etc{,/lk-platform},var}
install -d -m 00777 -g adm "$LK_BASE"/var/log
install -d -m 00750 -g adm "$LK_BASE"/var/backup
FILE=$LK_BASE/etc/lk-platform/lk-platform.conf
install -m 00664 -g adm /dev/null "$FILE"
LK_SSH_JUMP_KEY=${LK_SSH_JUMP_KEY:+jump} \
    lk_get_shell_var \
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

install -v -d -m 02775 -g adm "$LK_BASE/etc"
install -m 00664 -g adm /dev/null "$LK_BASE/etc/packages.conf"
printf '%s=(\n%s\n)\n' \
    "IMAGE_BASE_PACKAGES" "$(
        printf '    %q\n' "${IMAGE_BASE_PACKAGES[@]}"
    )" >"$LK_BASE/etc/packages.conf"

### move to lk-provision-hosting.sh
. /etc/lsb-release

APT_GET_ARGS=(
    --no-install-recommends
    --no-install-suggests
)
REPOS=()
ADD_APT_REPOSITORY_ARGS=(-yn)
EXCLUDE_PACKAGES=()
GET_PIP_URL=https://bootstrap.pypa.io/get-pip.py
CERTBOT_REPO=ppa:certbot/certbot
case "$DISTRIB_RELEASE" in
16.04)
    REPOS+=("$CERTBOT_REPO")
    ADD_APT_REPOSITORY_ARGS=(-y)
    EXCLUDE_PACKAGES+=(icdiff php-apcu-bc php-yaml)
    GET_PIP_URL=https://bootstrap.pypa.io/pip/3.5/get-pip.py
    PHPVER=7.0
    ;;
18.04)
    REPOS+=("$CERTBOT_REPO")
    PHPVER=7.2
    ;;
20.04)
    EXCLUDE_PACKAGES+=(php-gettext)
    PHPVER=7.4
    ;;
*)
    lk_die "Ubuntu release not supported: $DISTRIB_RELEASE"
    ;;
esac

grep -Eq "\
^deb$S+http://\w+(\.\w+)*(:[0-9]+)?(/ubuntu)?/?$S+(\w+$S+)*\
$DISTRIB_CODENAME$S+(\w+$S+)*universe($S|\$)" \
    /etc/apt/sources.list ||
    REPOS+=(universe)

lk_console_message "Enabling persistent journald storage"
edit_file "/etc/systemd/journald.conf" "^#?Storage=.*\$" "Storage=persistent"
systemctl restart systemd-journald.service
### //

lk_console_message "Setting system hostname"
lk_console_detail "Running:" "hostnamectl set-hostname $LK_NODE_HOSTNAME"
hostnamectl set-hostname "$LK_NODE_HOSTNAME"

# Apache won't resolve a name-based <VirtualHost> correctly if ServerName
# resolves to a loopback address, so if the host's FQDN is also the initial
# hosting domain, don't associate it with 127.0.1.1
[ "${LK_NODE_FQDN#www.}" = "$LK_HOST_DOMAIN" ] || HOSTS_NODE_FQDN="$LK_NODE_FQDN"
FILE=/etc/hosts
lk_console_detail "Adding entries to" "$FILE"
cat <<EOF >>"$FILE"

# Added by ${0##*/} at $(lk_date_log)
127.0.1.1 ${HOSTS_NODE_FQDN:+$HOSTS_NODE_FQDN }$LK_NODE_HOSTNAME${HOSTS_NODE_FQDN:+${IPV4_ADDRESS:+
$IPV4_ADDRESS $LK_NODE_FQDN}${IPV6_ADDRESS:+
$IPV6_ADDRESS $LK_NODE_FQDN}}
EOF
lk_console_diff "$FILE"

### move to lk-provision-hosting.sh
lk_console_message "Configuring APT"
FILE=/etc/apt/apt.conf.d/90${LK_PATH_PREFIX}defaults
APT_OPTIONS=()
lk_console_detail "Disabling installation of recommended and suggested packages"
APT_OPTIONS+=(
    "APT::Install-Recommends" "false"
    "APT::Install-Suggests" "false"
)
lk_console_detail "Enabling unattended upgrades (security packages only)"
APT_OPTIONS+=(
    "APT::Periodic::Update-Package-Lists" "1"
    "APT::Periodic::Unattended-Upgrade" "1"
    "Unattended-Upgrade::Mail" "$LK_UPGRADE_EMAIL"
    "Unattended-Upgrade::Remove-Unused-Kernel-Packages" "true"
)
if [ "$LK_AUTO_REBOOT" = Y ]; then
    lk_console_detail "Enabling automatic reboot"
    APT_OPTIONS+=(
        "Unattended-Upgrade::Automatic-Reboot" "true"
        "Unattended-Upgrade::Automatic-Reboot-Time" "$LK_AUTO_REBOOT_TIME"
    )
fi
{
    printf '# Created by %s at %s\n' "${0##*/}" "$(lk_date_log)"
    printf '%s "%s";\n' "${APT_OPTIONS[@]}"
} >"$FILE"
lk_console_diff "$FILE"
### //

# see `man invoke-rc.d` for more information
lk_console_message "Disabling automatic \"systemctl start\" when new services are installed"
cat <<EOF >"/usr/sbin/policy-rc.d"
#!/bin/bash
# Created by ${0##*/} at $(lk_date_log)
$DECLARE_LK_DATE_LOG
LOG=(
    "====> \${0##*/}: init script policy helper invoked"
    "Arguments:
\$([ "\$#" -eq 0 ] || printf '  - %q\n' "\$@")")
DEPLOY_PENDING=N
EXIT_STATUS=0
exec 9>"/tmp/${LK_PATH_PREFIX}install.lock"
if ! flock -n 9; then
    DEPLOY_PENDING=Y
    [ "\${DPKG_MAINTSCRIPT_NAME-}" != postinst ] || EXIT_STATUS=101
fi
LOG+=("Deploy pending: \$DEPLOY_PENDING")
LOG+=("Exit status: \$EXIT_STATUS")
printf '%s %s\n%s\n' "\$(lk_date_log)" "\${LOG[0]}" "\$(
    LOG=("\${LOG[@]:1}")
    printf '  %s\n' "\${LOG[@]//\$'\n'/\$'\n' }"
)" >>"/var/log/${LK_PATH_PREFIX}policy-rc.log"
exit "\$EXIT_STATUS"
EOF
chmod a+x "/usr/sbin/policy-rc.d"
lk_console_diff "/usr/sbin/policy-rc.d"

REMOVE_PACKAGES=(
    mlocate # waste of CPU
    rsyslog # waste of space (assuming journald storage is persistent)

    # Canonical cruft
    landscape-common
    snapd
    ubuntu-advantage-tools
)
for i in "${!REMOVE_PACKAGES[@]}"; do
    lk_dpkg_installed "${REMOVE_PACKAGES[$i]}" ||
        unset "REMOVE_PACKAGES[$i]"
done
if [ ${#REMOVE_PACKAGES[@]} -gt 0 ]; then
    lk_console_item "Removing APT packages:" "${REMOVE_PACKAGES[*]}"
    apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq purge "${REMOVE_PACKAGES[@]}"
fi

lk_console_message "Disabling unnecessary motd scripts"
for FILE in 10-help-text 50-motd-news 91-release-upgrade 98-fsck-at-reboot; do
    [ ! -x "/etc/update-motd.d/$FILE" ] || chmod -c a-x "/etc/update-motd.d/$FILE"
done

lk_console_message "Configuring kernel parameters"
FILE="/etc/sysctl.d/90-${LK_PATH_PREFIX}defaults.conf"
cat <<EOF >"$FILE"
# Avoid paging and swapping if at all possible
vm.swappiness = 1

# Apache and PHP-FPM both default to listen.backlog = 511, but the
# default value of SOMAXCONN is only 128
net.core.somaxconn = 1024
EOF
lk_console_diff "$FILE"
sysctl --system

lk_console_message "Sourcing $LK_BASE/lib/bash/rc.sh in ~/.bashrc for all users"
RC_ESCAPED="$(printf '%q' "$LK_BASE/lib/bash/rc.sh")"
BASH_SKEL="
if [ -f $RC_ESCAPED ]; then
    . $RC_ESCAPED
fi"
echo "$BASH_SKEL" >>"/etc/skel/.bashrc"
if [ -f "/root/.bashrc" ]; then
    echo "$BASH_SKEL" >>"/root/.bashrc"
else
    cp "/etc/skel/.bashrc" "/root/.bashrc"
fi

lk_console_message "Sourcing Byobu in ~/.profile by default"
cat <<EOF >>"/etc/skel/.profile"
_byobu_sourced=1 . /usr/bin/byobu-launch 2>/dev/null || true
EOF
DIR="/etc/skel/.byobu"
install -v -d -m 00755 "$DIR"
# disable byobu-prompt
echo -n >"$DIR/prompt"
# configure status line
cat <<EOF >"$DIR/status"
screen_upper_left="color"
screen_upper_right="color whoami hostname #ip_address menu"
screen_lower_left="color #logo #distro release #arch #session"
screen_lower_right="color #network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk #time_utc date time"
tmux_left="#logo #distro release #arch #session"
tmux_right="#network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk whoami hostname #ip_address #time_utc date time"
EOF
cat <<EOF >"$DIR/datetime.tmux"
BYOBU_DATE="%-d%b"
BYOBU_TIME="%H:%M:%S%z"
EOF
# disable UTF-8 support by default
cat <<EOF >"$DIR/statusrc"
[ ! -f "/etc/arch-release" ] || RELEASE_ABBREVIATED=1
BYOBU_CHARMAP=x
EOF

ADMIN_USER_KEYS=$([ -z "$LK_ADMIN_USERS" ] ||
    grep -E "$S(${LK_ADMIN_USERS//,/|})\$" "$KEYS_FILE") || true
HOST_KEYS=$([ -z "$LK_ADMIN_USERS" ] &&
    cat "$KEYS_FILE" ||
    grep -Ev "$S(${LK_ADMIN_USERS//,/|})\$" "$KEYS_FILE") || true
JUMP_KEY=$([ -z "$LK_SSH_JUMP_KEY" ] ||
    grep -E "$S$LK_SSH_JUMP_KEY\$" "$KEYS_FILE") || true
[ -z "$LK_SSH_JUMP_KEY" ] ||
    case "$([ -z "$JUMP_KEY" ] && echo 0 || wc -l <<<"$JUMP_KEY")" in
    0)
        lk_console_item "SSH jump proxy key not found:" "$LK_SSH_JUMP_KEY"
        ;;
    1)
        lk_console_item "SSH jump proxy key found:" "$LK_SSH_JUMP_KEY"
        ;;
    *)
        lk_console_item "Too many keys for SSH jump proxy key:" "$LK_SSH_JUMP_KEY"
        JUMP_KEY=
        ;;
    esac

lk_console_message "Configuring SSH client defaults"
DIR=/etc/skel
install -v -d -m 00700 "$DIR/.ssh"{,"/$LK_PATH_PREFIX"{config.d,keys}}
lk_file_keep_original "$DIR/.ssh/config"
cat <<EOF >"$DIR/.ssh/config"
# Added by ${0##*/} at $(lk_date_log)
Include ~/.ssh/${LK_PATH_PREFIX}config.d/*
EOF
lk_console_diff "$DIR/.ssh/config"
cat <<EOF >"$DIR/.ssh/${LK_PATH_PREFIX}config.d/90-defaults"
Host                    ${LK_PATH_PREFIX}*
IdentitiesOnly          yes
ForwardAgent            yes
StrictHostKeyChecking   accept-new
ControlMaster           auto
ControlPath             /tmp/ssh_%h-%p-%r-%l
ControlPersist          120
SendEnv                 LANG LC_*
ServerAliveInterval     30
EOF
lk_console_diff "$DIR/.ssh/${LK_PATH_PREFIX}config.d/90-defaults"
[ -z "$LK_SSH_JUMP_HOST" ] || {
    HOST=$LK_SSH_JUMP_HOST
    [[ ! $HOST =~ (.*):([0-9]+)$ ]] || {
        HOST=${BASH_REMATCH[1]}
        PORT=${BASH_REMATCH[2]}
    }
    cat <<EOF >"$DIR/.ssh/${LK_PATH_PREFIX}config.d/40-jump"
Host                    ${LK_PATH_PREFIX}jump
HostName                $HOST${PORT:+
Port                    $PORT}${LK_SSH_JUMP_USER:+
User                    $LK_SSH_JUMP_USER}${JUMP_KEY:+
IdentityFile            "~/.ssh/${LK_PATH_PREFIX}keys/jump"}
EOF
}
[ -z "$JUMP_KEY" ] || {
    install -m 00600 /dev/null "$DIR/.ssh/${LK_PATH_PREFIX}keys/jump"
    echo "$JUMP_KEY" >"$DIR/.ssh/${LK_PATH_PREFIX}keys/jump"
}
chmod -Rc -077 "$DIR/.ssh"

DIR=/etc/skel.${LK_PATH_PREFIX%-}
[ ! -e "$DIR" ] || lk_die "already exists: $DIR"
lk_console_message "Creating $DIR (for hosting accounts)"
cp -av "/etc/skel" "$DIR"
install -m 00600 /dev/null "$DIR/.ssh/authorized_keys"
[ -z "$HOST_KEYS" ] || echo "$HOST_KEYS" >>"$DIR/.ssh/authorized_keys"

unset FIRST_ADMIN
for USERNAME in ${LK_ADMIN_USERS//,/ }; do
    FIRST_ADMIN="${FIRST_ADMIN:-$USERNAME}"
    lk_console_message "Creating superuser '$USERNAME'"
    # HOME_DIR may already exist, e.g. if filesystems have been mounted in it
    useradd --no-create-home --groups "adm,sudo" --shell "/bin/bash" "$USERNAME"
    USER_GROUP="$(id -gn "$USERNAME")"
    USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
    install -v -d -m 00750 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME"
    if [ -z "$ADMIN_USER_KEYS" ]; then
        [ ! -e "/root/.ssh" ] || {
            lk_console_message "Moving /root/.ssh to $USER_HOME/.ssh"
            mv "/root/.ssh" "$USER_HOME/"
        }
    else
        install -v -d -m 00700 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME/.ssh"
        install -m 00600 -o "$USERNAME" -g "$USER_GROUP" /dev/null "$USER_HOME/.ssh/authorized_keys"
        grep -E "$S$USERNAME\$" <<<"$ADMIN_USER_KEYS" >>"$USER_HOME/.ssh/authorized_keys" || true
    fi
    cp -nRTv "/etc/skel" "$USER_HOME"
    chown -R "$USERNAME": "$USER_HOME"
    install -m 00440 /dev/null "/etc/sudoers.d/nopasswd-$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/nopasswd-$USERNAME"
done

if [ -n "${FIRST_ADMIN-}" ] && [ -e "$KEYS_FILE" ]; then
    lk_console_item "Deleting" "$KEYS_FILE"
    rm -v "$KEYS_FILE"
fi

lk_console_message "Disabling root password"
passwd -l root

# TODO: configure chroot jail
lk_console_message "Disabling clear text passwords when authenticating with SSH"
MATCH_MANY=Y edit_file "/etc/ssh/sshd_config" \
    "^#?(PasswordAuthentication${FIRST_ADMIN+|PermitRootLogin})\b.*\$" \
    "\1 no"

systemctl restart sshd.service
FIRST_ADMIN="${FIRST_ADMIN:-root}"

lk_console_message "Upgrading pre-installed packages"
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -q update
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq dist-upgrade

debconf-set-selections <<EOF
iptables-persistent	iptables-persistent/autosave_v4	boolean	false
iptables-persistent	iptables-persistent/autosave_v6	boolean	false
postfix	postfix/main_mailer_type	select	Internet Site
postfix	postfix/mailname	string	$LK_NODE_FQDN
postfix	postfix/relayhost	string	$LK_SMTP_RELAY
postfix	postfix/root_address	string	$LK_ADMIN_EMAIL
EOF

# bare necessities
PACKAGES=(
    #
    atop
    ntp

    #
    bash-completion
    byobu
    ca-certificates
    coreutils
    cron
    curl
    diffutils
    dnsutils
    git
    htop
    iptables
    iptables-persistent
    iputils-ping
    iputils-tracepath
    jq
    less
    logrotate
    lsof
    nano
    netcat-openbsd
    perl
    psmisc
    pv
    rdfind
    rsync
    tcpdump
    telnet
    time
    tzdata
    vim
    wget
    whiptail
    $(lk_apt_available_list icdiff)

    #
    apt-listchanges
    software-properties-common # provides add-apt-repository
    unattended-upgrades

    #
    build-essential
    python3
    python3-dev
)

lk_console_item "Installing APT packages:" "${PACKAGES[*]}"
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq install "${PACKAGES[@]}"

lk_console_message "Configuring iptables"
install -m 00660 -g adm /dev/null "$LK_BASE/etc/firewall.conf"
if [ "$LK_REJECT_OUTPUT" != "N" ]; then
    APT_SOURCE_HOSTS=($(grep -Eo "^[^#]+${S}https?://[^/[:space:]]+" "/etc/apt/sources.list" |
        sed -E 's/^.*:\/\///' | sort -u)) || lk_die "no active package sources in /etc/apt/sources.list"
    if [[ ",$LK_NODE_SERVICES," =~ .*,wp-cli,.* ]]; then
        WORDPRESS_HOSTS="\
    # used by wp-cli when installing WordPress plugins and updates
    api.wordpress.org
    downloads.wordpress.org
    plugins.svn.wordpress.org
    wordpress.org"
    fi
    ACCEPT_OUTPUT_HOSTS_SH="\
# active package sources are automatically added from /etc/apt/sources.list
ACCEPT_OUTPUT_HOSTS=(
    # \"entropy-as-a-service\" endpoint used by pollinate
    entropy.ubuntu.com

    # used by add-apt-repository when adding a PPA (e.g. ppa:certbot/certbot)
    keyserver.ubuntu.com
    launchpad.net
    ppa.launchpad.net

    # used when installing pip and PyPI packages
    pypi.org
    bootstrap.pypa.io
    files.pythonhosted.org

    # if 'api.github.com' is allowed, so are all addresses in https://api.github.com/meta
    api.github.com
    raw.githubusercontent.com${WORDPRESS_HOSTS:+

$WORDPRESS_HOSTS}

    # ==== user-defined
${LK_ACCEPT_OUTPUT_HOSTS:+    ${LK_ACCEPT_OUTPUT_HOSTS//,/$'\n'    }
})"
    . /dev/stdin <<<"$ACCEPT_OUTPUT_HOSTS_SH"
    if [[ " ${LK_ACCEPT_OUTPUT_HOSTS[*]} " =~ .*" api.github.com ".* ]]; then
        lk_keep_trying eval "GITHUB_META=\"\$(curl --fail \"https://api.github.com/meta\")\""
        GITHUB_IPS=($(jq -r ".web[]" <<<"$GITHUB_META"))
    fi
    OUTPUT_ALLOW=(
        "${APT_SOURCE_HOSTS[@]}"
        "${LK_ACCEPT_OUTPUT_HOSTS[@]}"
        ${GITHUB_IPS[@]+"${GITHUB_IPS[@]}"}
    )
    OUTPUT_ALLOW_IPV4=()
    OUTPUT_ALLOW_IPV6=()
    for i in "${!OUTPUT_ALLOW[@]}"; do
        ALLOW="${OUTPUT_ALLOW[$i]}"
        if is_ipv4 "$ALLOW"; then
            OUTPUT_ALLOW_IPV4+=("$ALLOW")
            unset "OUTPUT_ALLOW[$i]"
        elif is_ipv6 "$ALLOW"; then
            OUTPUT_ALLOW_IPV6+=("$ALLOW")
            unset "OUTPUT_ALLOW[$i]"
        fi
    done
    OUTPUT_ALLOW_IPV4=($(lk_keep_trying \
        lk_hosts_get_records +VALUE A "${OUTPUT_ALLOW[@]}"))
    OUTPUT_ALLOW_IPV6=($(lk_keep_trying \
        lk_hosts_get_records +VALUE AAAA "${OUTPUT_ALLOW[@]}"))
    echo "\
$ACCEPT_OUTPUT_HOSTS_SH
$(printf '%s=%q\n' \
        "ACCEPT_OUTPUT_CHAIN" "${P}output")" >"$LK_BASE/etc/firewall.conf"
fi

modprobe nf_conntrack_ftp nf_nat_ftp
FILE=/etc/modules-load.d/${LK_PATH_PREFIX}nf_conntrack.conf
install -m 00644 /dev/null "$FILE"
cat <<EOF >"$FILE"
nf_conntrack_ftp
nf_nat_ftp
EOF
lk_console_diff "$FILE"

iptables-restore <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
:${P}check - [0:0]
:${P}forward - [0:0]
:${P}input - [0:0]
:${P}output - [0:0]
:${P}reject - [0:0]
:${P}trusted - [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -j ${P}check
-A INPUT -j ${P}input
-A INPUT -j ${P}reject
-A FORWARD -j ${P}check
-A FORWARD -j ${P}forward
-A FORWARD -j ${P}reject
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -j ${P}check
-A OUTPUT -p udp -m udp --dport 67 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -j ${P}output
-A OUTPUT -m limit --limit 12/min -j LOG --log-prefix "outgoing packet blocked: "
-A OUTPUT -j ${P}reject
-A ${P}check -m conntrack --ctstate ESTABLISHED -j ACCEPT
-A ${P}check -m conntrack --ctstate INVALID -j DROP
-A ${P}check -p tcp -m conntrack --ctstate RELATED -m helper --helper ftp -m tcp --dport 1024:65535 -j ACCEPT
-A ${P}check -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset
-A ${P}check -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
-A ${P}input -p tcp -m tcp --dport 22 -j ${P}trusted
-A ${P}reject -p udp -m udp -j REJECT --reject-with icmp-port-unreachable
-A ${P}reject -p tcp -m tcp -j REJECT --reject-with tcp-reset
-A ${P}reject -j REJECT --reject-with icmp-proto-unreachable
COMMIT
*raw
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A PREROUTING -p tcp -m tcp --dport 21 -j CT --helper ftp
COMMIT
EOF
ip6tables-restore <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
:${P}check - [0:0]
:${P}check_ll - [0:0]
:${P}forward - [0:0]
:${P}input - [0:0]
:${P}output - [0:0]
:${P}reject - [0:0]
:${P}trusted - [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -j ${P}check_ll
-A INPUT -j ${P}check
-A INPUT -j ${P}input
-A INPUT -j ${P}reject
-A FORWARD -j ${P}check
-A FORWARD -j ${P}forward
-A FORWARD -j ${P}reject
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -j ${P}check_ll
-A OUTPUT -j ${P}check
-A OUTPUT -p udp -m udp --dport 547 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -j ${P}output
-A OUTPUT -m limit --limit 12/min -j LOG --log-prefix "outgoing packet blocked: "
-A OUTPUT -j ${P}reject
-A ${P}check -m conntrack --ctstate ESTABLISHED -j ACCEPT
-A ${P}check -m conntrack --ctstate INVALID -j DROP
-A ${P}check -p tcp -m conntrack --ctstate RELATED -m helper --helper ftp -m tcp --dport 1024:65535 -j ACCEPT
-A ${P}check -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT
-A ${P}check -p ipv6-icmp -m icmp6 --icmpv6-type 129 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 130 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 131 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 132 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 133 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 134 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 135 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 136 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m hl --hl-eq 1 -m icmp6 --icmpv6-type 151 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m hl --hl-eq 1 -m icmp6 --icmpv6-type 152 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m hl --hl-eq 1 -m icmp6 --icmpv6-type 153 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 141 -j ACCEPT
-A ${P}check_ll -p ipv6-icmp -m hl --hl-eq 255 -m icmp6 --icmpv6-type 142 -j ACCEPT
-A ${P}check_ll -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 143 -j ACCEPT
-A ${P}input -p tcp -m tcp --dport 22 -j ${P}trusted
-A ${P}reject -p udp -m udp -j REJECT --reject-with icmp6-port-unreachable
-A ${P}reject -p tcp -m tcp -j REJECT --reject-with tcp-reset
-A ${P}reject -j REJECT --reject-with icmp6-adm-prohibited
COMMIT
*raw
:PREROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A PREROUTING -p tcp -m tcp --dport 21 -j CT --helper ftp
COMMIT
EOF
if [ "$LK_REJECT_OUTPUT" = "N" ]; then
    iptables -A "${P}output" -j ACCEPT
else
    for IPV4 in "${OUTPUT_ALLOW_IPV4[@]}"; do
        command iptables -A "${P}output" -d "$IPV4" -j ACCEPT
    done
    for IPV6 in "${OUTPUT_ALLOW_IPV6[@]}"; do
        command ip6tables -A "${P}output" -d "$IPV6" -j ACCEPT
    done
fi
if [ "$LK_SSH_TRUSTED_ONLY" = "N" ] || [ -z "$LK_TRUSTED_IP_ADDRESSES" ]; then
    iptables -A "${P}trusted" -j ACCEPT
else
    for IP in ${LK_TRUSTED_IP_ADDRESSES[*]//,/ }; do
        if is_ipv4 "$IP"; then
            command iptables -A "${P}trusted" -s "$IP" -j ACCEPT
        elif is_ipv6 "$IP"; then
            command ip6tables -A "${P}trusted" -s "$IP" -j ACCEPT
        fi
    done
fi

lk_console_message "Configuring logrotate"
edit_file "/etc/logrotate.conf" "^#?su( .*)?\$" "su root adm" "su root adm"

lk_console_message "Setting system timezone to '$LK_NODE_TIMEZONE'"
timedatectl set-timezone "$LK_NODE_TIMEZONE"

lk_console_message "Configuring apt-listchanges"
lk_file_keep_original "/etc/apt/listchanges.conf"
cat <<EOF >"/etc/apt/listchanges.conf"
[apt]
frontend=pager
which=both
email_address=$LK_UPGRADE_EMAIL
email_format=html
confirm=false
headers=true
reverse=false
save_seen=/var/lib/apt/listchanges.db
EOF
lk_console_diff "/etc/apt/listchanges.conf"

FILE="/boot/config-$(uname -r)"
if [ -f "$FILE" ] && ! grep -Fxq "CONFIG_BSD_PROCESS_ACCT=y" "$FILE"; then
    lk_console_message "Disabling atopacct.service (process accounting not available)"
    systemctl disable atopacct.service
fi

"$LK_BASE/bin/lk-platform-configure.sh" --no-log

# TODO: verify downloads
lk_console_message "Installing pip, ps_mem, Glances, awscli"
lk_keep_trying curl --fail --output /root/get-pip.py "$GET_PIP_URL"
python3 /root/get-pip.py
lk_keep_trying pip install ps_mem glances awscli

lk_console_message "Configuring Glances"
install -v -d -m 00755 "/etc/glances"
cat <<EOF >"/etc/glances/glances.conf"
# Created by ${0##*/} at $(lk_date_log)

[global]
check_update=false

[ip]
disable=true
EOF

lk_console_message "Creating virtual host base directory at /srv/www"
install -v -d -m 00751 -g adm "/srv/www"
install -v -d -m 00751 -g adm "/srv/www/.opcache"
install -v -d -m 00751 -g adm "/srv/www/.tmp"

PACKAGES=(
    postfix
    certbot
)
case ",$LK_NODE_SERVICES," in
*,apache+php,*)
    PACKAGES+=(
        #
        apache2
        libapache2-mod-qos
        php-fpm
        python3-certbot-apache

        #
        php-apcu
        php-apcu-bc
        php-bcmath
        php-cli
        php-curl
        php-gd
        php-gettext
        php-imagick
        php-imap
        php-intl
        php-json
        php-ldap
        php-mbstring
        php-memcache
        php-memcached
        php-mysql
        php-opcache
        php-pear
        php-pspell
        php-readline
        php-redis
        php-soap
        php-sqlite3
        php-xml
        php-xmlrpc
        php-yaml
        php-zip
    )
    ;;&

*,mysql,*)
    PACKAGES+=(
        mariadb-server
    )
    ;;&

*,memcached,*)
    PACKAGES+=(
        memcached
    )
    ;;&

*,fail2ban,*)
    PACKAGES+=(
        fail2ban
    )
    ;;&

*,jre,*)
    PACKAGES+=(
        default-jre
    )
    ;;&

*,wp-cli,*)
    PACKAGES+=(
        php-cli
    )
    lk_console_message "Downloading wp-cli to /usr/local/bin"
    lk_keep_trying curl --fail --output "/usr/local/bin/wp" "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    chmod a+x "/usr/local/bin/wp"
    ;;

esac

PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | sort -u))
[ ${#EXCLUDE_PACKAGES[@]} -eq 0 ] ||
    PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | grep -Fxv "$(printf '%s\n' "${EXCLUDE_PACKAGES[@]}")"))

lk_file_keep_original "/etc/apt/sources.list"

if [ ${#REPOS[@]} -gt 0 ]; then
    lk_console_item "Adding APT repositories:" "$(printf '%s\n' "${REPOS[@]}")"
    for REPO in "${REPOS[@]}"; do
        lk_keep_trying add-apt-repository "${ADD_APT_REPOSITORY_ARGS[@]}" "$REPO"
    done
fi

lk_console_item "Installing APT packages:" "${PACKAGES[*]}"
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -q update
# new repos may include updates for pre-installed packages
[ ${#REPOS[@]} -eq 0 ] || lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq upgrade
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq install "${PACKAGES[@]}"

if [ -n "$LK_HOST_DOMAIN" ]; then
    COPY_SKEL=0
    PHP_FPM_POOL_USER="www-data"
    id "$LK_HOST_ACCOUNT" &>/dev/null || {
        lk_console_message "Creating user account '$LK_HOST_ACCOUNT'"
        useradd --no-create-home --home-dir "/srv/www/$LK_HOST_ACCOUNT" --shell "/bin/bash" "$LK_HOST_ACCOUNT"
        COPY_SKEL=1
        PHP_FPM_POOL_USER="$LK_HOST_ACCOUNT"
        APACHE_MODS=(
            qos
            unique_id # used by "qos"
        )
    }
    HOST_ACCOUNT_GROUP="$(id -gn "$LK_HOST_ACCOUNT")"
    install -v -d -m 00750 -o "$LK_HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$LK_HOST_ACCOUNT"
    install -v -d -m 00750 -o "$LK_HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$LK_HOST_ACCOUNT/public_html"
    install -v -d -m 00750 -o "$LK_HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$LK_HOST_ACCOUNT/ssl"
    install -v -d -m 02750 -g "$HOST_ACCOUNT_GROUP" "/srv/www/$LK_HOST_ACCOUNT/log"
    [ "$COPY_SKEL" -eq 0 ] || {
        cp -nRTv "/etc/skel.${LK_PATH_PREFIX%-}" "/srv/www/$LK_HOST_ACCOUNT" &&
            chown -R "$LK_HOST_ACCOUNT": "/srv/www/$LK_HOST_ACCOUNT" || exit
    }
    ! lk_dpkg_installed apache2 || {
        lk_console_message "Adding user 'www-data' to group '$HOST_ACCOUNT_GROUP'"
        usermod --append --groups "$HOST_ACCOUNT_GROUP" "www-data"
    }
fi

if [ -n "$LK_NODE_PACKAGES" ]; then
    lk_console_message "Installing additional packages"
    lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq install ${LK_NODE_PACKAGES//,/ }
fi

if lk_dpkg_installed fail2ban; then
    # TODO: configure jails other than sshd
    lk_console_message "Configuring Fail2Ban"
    FILE="/etc/fail2ban/jail.conf"
    EDIT_FILE_LOG=N edit_file "$FILE" \
        "^#?backend$S*=($S*(pyinotify|gamin|polling|systemd|auto))?($S*; .*)?\$" \
        "backend = systemd\3"
    [ -z "$LK_TRUSTED_IP_ADDRESSES" ] ||
        EDIT_FILE_LOG=N edit_file "$FILE" \
            "^#?ignoreip$S*=($S*[^#]+)?($S*; .*)?\$" \
            "ignoreip = 127.0.0.1\\/8 ::1 ${LK_TRUSTED_IP_ADDRESSES//\//\\\/}\2"
    lk_console_diff "$FILE"
fi

if lk_dpkg_installed postfix; then
    lk_console_message "Binding Postfix to the loopback interface"
    postconf -e "inet_interfaces = loopback-only"
    if [ -n "$LK_EMAIL_BLACKHOLE" ]; then
        lk_console_message "Configuring Postfix to map all recipient addresses to '$LK_EMAIL_BLACKHOLE'"
        postconf -e "recipient_canonical_maps = static:blackhole"
        cat <<EOF >>"/etc/aliases"

# Added by ${0##*/} at $(lk_date_log)
blackhole:	$LK_EMAIL_BLACKHOLE
EOF
        newaliases
    fi
    lk_console_diff "/etc/postfix/main.cf"
    lk_console_diff "/etc/aliases"
fi

if lk_dpkg_installed apache2; then
    APACHE_MODS=(
        # Ubuntu 18.04 defaults
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

        # extras
        expires # required by W3 Total Cache
        headers
        info
        macro
        proxy
        proxy_fcgi
        remoteip
        rewrite
        socache_shmcb # dependency of "ssl"
        ssl

        #
        ${APACHE_MODS[@]+"${APACHE_MODS[@]}"}
    )
    APACHE_MODS_ENABLED="$(a2query -m | grep -Eo '^[^ ]+' | sort -u || :)"
    APACHE_DISABLE_MODS=($(comm -13 <(printf '%s\n' "${APACHE_MODS[@]}" | sort -u) <(echo "$APACHE_MODS_ENABLED")))
    APACHE_ENABLE_MODS=($(comm -23 <(printf '%s\n' "${APACHE_MODS[@]}" | sort -u) <(echo "$APACHE_MODS_ENABLED")))
    [ ${#APACHE_DISABLE_MODS[@]} -eq 0 ] || {
        lk_console_item "Disabling Apache HTTPD modules:" "${APACHE_DISABLE_MODS[*]}"
        a2dismod --force "${APACHE_DISABLE_MODS[@]}"
    }
    [ ${#APACHE_ENABLE_MODS[@]} -eq 0 ] || {
        lk_console_item "Enabling Apache HTTPD modules:" "${APACHE_ENABLE_MODS[*]}"
        a2enmod --force "${APACHE_ENABLE_MODS[@]}"
    }

    # TODO: make PHP-FPM setup conditional
    [ -e "/opt/opcache-gui" ] || {
        lk_console_message "Cloning 'https://github.com/lkrms/opcache-gui.git' to '/opt/opcache-gui'"
        install -v -d -m 02775 -o "$FIRST_ADMIN" -g adm "/opt/opcache-gui"
        lk_keep_trying sudo -Hu "$FIRST_ADMIN" \
            git clone "https://github.com/lkrms/opcache-gui.git" \
            "/opt/opcache-gui"
    }

    lk_console_message "Configuring Apache HTTPD to serve PHP-FPM virtual hosts"
    cat <<EOF >"/etc/apache2/sites-available/${LK_PATH_PREFIX}default.conf"
<IfModule event.c>
    MaxRequestWorkers 300
    ThreadsPerChild 25
</IfModule>
<Macro RequireTrusted>
    Require local${LK_TRUSTED_IP_ADDRESSES:+
    Require ip ${LK_TRUSTED_IP_ADDRESSES//,/ }}
</Macro>
# Add 'Use Staging' to virtual hosts search engines should ignore
<Macro Staging>
    Header set X-Robots-Tag "noindex, nofollow"
</Macro>
# 'AllowOverride' is only valid in 'Directory', so use a macro in lieu of
# 'DirectoryMatch'
<Macro PublicDirectory %dirpath%>
    <Directory %dirpath%>
        Options SymLinksIfOwnerMatch
        AllowOverride All Options=Indexes,MultiViews,SymLinksIfOwnerMatch,ExecCGI
        Require all granted
    </Directory>
</Macro>
Use PublicDirectory /srv/www/*/public_html
Use PublicDirectory /srv/www/*/*/public_html
<Directory /opt/opcache-gui>
    Options None
    AllowOverride None
    Use RequireTrusted
</Directory>
<IfModule mod_status.c>
    ExtendedStatus On
</IfModule>
<VirtualHost *:80>
    ServerAdmin $LK_ADMIN_EMAIL
    DocumentRoot /var/www/html
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    <IfModule mod_status.c>
        <Location /httpd-status>
            SetHandler server-status
            Use RequireTrusted
        </Location>
    </IfModule>
    <IfModule mod_info.c>
        <Location /httpd-info>
            SetHandler server-info
            Use RequireTrusted
        </Location>
    </IfModule>
    <IfModule mod_qos.c>
        <Location /httpd-qos>
            SetHandler qos-viewer
            Use RequireTrusted
        </Location>
    </IfModule>
</VirtualHost>
<Macro PhpFpmVirtualHostCustom${PHPVER//./} %sitename% %customroot%>
    ServerAdmin $LK_ADMIN_EMAIL
    DocumentRoot /srv/www/%sitename%%customroot%public_html
    Alias /php-opcache /opt/opcache-gui
    ErrorLog /srv/www/%sitename%%customroot%log/error.log
    CustomLog /srv/www/%sitename%%customroot%log/access.log combined
    DirectoryIndex index.php index.html index.htm
    ProxyPassMatch ^/php-opcache/(.*\.php(/.*)?)\$ fcgi://%sitename%/opt/opcache-gui/\$1
    ProxyPassMatch ^/(.*\.php(/.*)?)\$ fcgi://%sitename%/srv/www/%sitename%%customroot%public_html/\$1
    <LocationMatch ^/(php-fpm-(status|ping))\$>
        ProxyPassMatch fcgi://%sitename%/\$1
        Use RequireTrusted
    </LocationMatch>
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteRule ^/php-fpm-(status|ping)\$ - [END]
    </IfModule>
    <IfModule mod_alias.c>
        RedirectMatch 404 .*/\.(git|svn|${LK_PATH_PREFIX}settings)
    </IfModule>
</Macro>
<Macro PhpFpmVirtualHost${PHPVER//./} %sitename%>
    Use PhpFpmVirtualHostCustom${PHPVER//./} %sitename% /
</Macro>
<Macro PhpFpmVirtualHostSsl${PHPVER//./} %sitename%>
    Use PhpFpmVirtualHostCustom${PHPVER//./} %sitename% /
</Macro>
<Macro PhpFpmVirtualHostChild${PHPVER//./} %sitename% %childname%>
    Use PhpFpmVirtualHostCustom${PHPVER//./} %sitename% /%childname%/
</Macro>
<Macro PhpFpmVirtualHostSslChild${PHPVER//./} %sitename% %childname%>
    Use PhpFpmVirtualHostCustom${PHPVER//./} %sitename% /%childname%/
</Macro>
<Macro PhpFpmProxy${PHPVER//./} %sitename% %timeout%>
    <Proxy unix:/run/php/php$PHPVER-fpm-%sitename%.sock|fcgi://%sitename%>
        ProxySet enablereuse=Off timeout=%timeout%
    </Proxy>
</Macro>
EOF
    rm -f "/etc/apache2/sites-enabled"/*
    ln -s "../sites-available/${LK_PATH_PREFIX}default.conf" "/etc/apache2/sites-enabled/000-${LK_PATH_PREFIX}default.conf"
    lk_console_diff "/etc/apache2/sites-available/${LK_PATH_PREFIX}default.conf"

    lk_console_message "Disabling pre-installed PHP-FPM pools"
    lk_file_keep_original "/etc/php/$PHPVER/fpm/pool.d"
    rm -f "/etc/php/$PHPVER/fpm/pool.d"/*.conf

    if [ -n "$LK_HOST_DOMAIN" ]; then
        lk_console_message "Adding site to Apache HTTPD: $LK_HOST_DOMAIN"
        cat <<EOF >"/etc/apache2/sites-available/$LK_HOST_ACCOUNT.conf"
<VirtualHost *:80>
    ServerName $LK_HOST_DOMAIN
    ServerAlias www.$LK_HOST_DOMAIN
    Use PhpFpmVirtualHost${PHPVER//./} $LK_HOST_ACCOUNT
</VirtualHost>
<VirtualHost *:443>
    ServerName $LK_HOST_DOMAIN
    ServerAlias www.$LK_HOST_DOMAIN
    Use PhpFpmVirtualHostSsl${PHPVER//./} $LK_HOST_ACCOUNT
    SSLEngine on
    SSLCertificateFile /srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.cert
    SSLCertificateKeyFile /srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.key
</VirtualHost>
# PhpFpmProxy${PHPVER//./} %sitename% %timeout%
#   %timeout% should correlate with \`request_terminate_timeout\`
#   in /etc/php/$PHPVER/fpm/pool.d/$LK_HOST_ACCOUNT.conf
Use PhpFpmProxy${PHPVER//./} $LK_HOST_ACCOUNT 300
EOF
        install -m 00640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/log/error.log"
        install -m 00640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/log/access.log"
        install -m 00640 -o "$LK_HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.cert"
        install -m 00640 -o "$LK_HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.key"

        lk_console_message "Creating a self-signed SSL certificate for '$LK_HOST_DOMAIN'"
        OPENSSL_CONF=$(cat /etc/ssl/openssl.cnf)
        OPENSSL_EXT_CONF=$(printf '\n%s' \
            "[ san ]" \
            "subjectAltName = DNS:$LK_HOST_DOMAIN, DNS:www.$LK_HOST_DOMAIN")
        openssl genrsa \
            -out "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.key" \
            2048
        openssl req -new \
            -key "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.key" \
            -subj "/CN=$LK_HOST_DOMAIN" \
            -reqexts san \
            -config <(cat <<<"$OPENSSL_CONF$OPENSSL_EXT_CONF") \
            -out "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.csr"
        openssl x509 -req -days 365 \
            -in "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.csr" \
            -extensions san \
            -extfile <(cat <<<"$OPENSSL_EXT_CONF") \
            -signkey "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.key" \
            -out "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.cert"
        rm -f "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.csr"

        lk_console_detail "Adding self-signed certificate to local trust store"
        install -v -m 00644 "/srv/www/$LK_HOST_ACCOUNT/ssl/$LK_HOST_DOMAIN.cert" \
            "/usr/local/share/ca-certificates/$LK_HOST_DOMAIN.crt"
        update-ca-certificates

        [ "$LK_HOST_SITE_ENABLE" = "N" ] ||
            ln -s "../sites-available/$LK_HOST_ACCOUNT.conf" "/etc/apache2/sites-enabled/$LK_HOST_ACCOUNT.conf"
        lk_console_diff "/etc/apache2/sites-available/$LK_HOST_ACCOUNT.conf"

        lk_console_message "Configuring PHP-FPM umask for group-writable files"
        FILE="/etc/systemd/system/php$PHPVER-fpm.service.d/override.conf"
        install -v -d -m 00755 "$(dirname "$FILE")"
        cat <<EOF >"$FILE"
[Service]
UMask=0002
EOF
        systemctl daemon-reload
        lk_console_diff "$FILE"

        lk_console_message "Adding pool to PHP-FPM: $LK_HOST_ACCOUNT"
        cat <<EOF >"/etc/php/$PHPVER/fpm/pool.d/$LK_HOST_ACCOUNT.conf"
; Values in /etc/apache2/sites-available/$LK_HOST_ACCOUNT.conf and/or
; /etc/mysql/mariadb.conf.d/90-${LK_PATH_PREFIX}defaults.cnf should be updated
; if \`request_terminate_timeout\` or \`pm.max_children\` are changed here
[$LK_HOST_ACCOUNT]
user = $PHP_FPM_POOL_USER
listen = /run/php/php$PHPVER-fpm-\$pool.sock
listen.owner = www-data
listen.group = www-data
; ondemand can't handle sudden bursts: https://github.com/php/php-src/pull/1308
pm = static
; tune based on memory consumed per process under load
pm.max_children = 30
; respawn occasionally in case of memory leaks
pm.max_requests = 10000
; because \`max_execution_time\` only counts CPU time
request_terminate_timeout = 300
; check \`ulimit -Hn\` and raise in /etc/security/limits.d/ if needed
rlimit_files = 1048576
pm.status_path = /php-fpm-status
ping.path = /php-fpm-ping
access.log = "/srv/www/\$pool/log/php$PHPVER-fpm.access.log"
access.format = "%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"
catch_workers_output = yes${LK_OPCACHE_MEMORY_CONSUMPTION:+
; tune based on system resources
php_admin_value[opcache.memory_consumption] = $LK_OPCACHE_MEMORY_CONSUMPTION}
php_admin_value[opcache.file_cache] = "/srv/www/.opcache/\$pool"
php_admin_flag[opcache.validate_permission] = On
php_admin_value[error_log] = "/srv/www/\$pool/log/php$PHPVER-fpm.error.log"
php_admin_flag[log_errors] = On
php_flag[display_errors] = Off
php_flag[display_startup_errors] = Off
php_value[upload_max_filesize] = 24M
php_value[post_max_size] = 50M
env[TMPDIR] = "/srv/www/.tmp/\$pool"

; do not uncomment the following in production (also, install php-xdebug first)
;php_admin_flag[opcache.enable] = Off
;php_admin_flag[xdebug.remote_enable] = On
;php_admin_flag[xdebug.remote_autostart] = On
;php_admin_flag[xdebug.remote_connect_back] = On
;php_admin_value[xdebug.remote_log] = "/srv/www/\$pool/log/php$PHPVER-fpm.xdebug.log"
EOF
        install -v -d -m 02750 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" "/srv/www/.opcache/$LK_HOST_ACCOUNT"
        install -v -d -m 02770 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" "/srv/www/.tmp/$LK_HOST_ACCOUNT"
        install -m 00640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/log/php$PHPVER-fpm.access.log"
        install -m 00640 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/log/php$PHPVER-fpm.error.log"
        install -m 00640 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$LK_HOST_ACCOUNT/log/php$PHPVER-fpm.xdebug.log"
        lk_console_diff "/etc/php/$PHPVER/fpm/pool.d/$LK_HOST_ACCOUNT.conf"
    fi

    lk_console_message "Adding virtual host log files to logrotate.d"
    mv -v "/etc/logrotate.d/apache2" "/etc/logrotate.d/apache2.disabled"
    mv -v "/etc/logrotate.d/php$PHPVER-fpm" "/etc/logrotate.d/php$PHPVER-fpm.disabled"
    cat <<EOF >"/etc/logrotate.d/${LK_PATH_PREFIX}log"
/var/log/apache2/*.log /var/log/php$PHPVER-fpm.log /srv/www/*/log/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create
    sharedscripts
    postrotate
        test ! -x /usr/lib/php/php$PHPVER-fpm-reopenlogs || /usr/lib/php/php$PHPVER-fpm-reopenlogs
        ! invoke-rc.d apache2 status &>/dev/null || invoke-rc.d apache2 reload &>/dev/null
    endscript
}
EOF

    lk_console_message "Adding iptables rules for Apache HTTPD"
    iptables -A "${P}input" -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A "${P}input" -p tcp -m tcp --dport 443 -j ACCEPT
fi

if lk_dpkg_installed mariadb-server; then
    FILE="/etc/mysql/mariadb.conf.d/90-${LK_PATH_PREFIX}defaults.cnf"
    cat <<EOF >"$FILE"
[mysqld]
# must exceed the sum of pm.max_children across all PHP-FPM pools
max_connections = 301${LK_INNODB_BUFFER_SIZE:+

innodb_buffer_pool_size = $LK_INNODB_BUFFER_SIZE
innodb_buffer_pool_instances = $(((${LK_INNODB_BUFFER_SIZE%M} - 1) / 1024 + 1))
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1}
EOF
    lk_console_diff "$FILE"
    lk_console_message "Starting mysql.service (MariaDB)"
    systemctl start mysql.service
    if [ -n "$LK_MYSQL_USERNAME" ]; then
        LK_MYSQL_PASSWORD="${LK_MYSQL_PASSWORD//\\/\\\\}"
        LK_MYSQL_PASSWORD="${LK_MYSQL_PASSWORD//\'/\\\'}"
        lk_console_message "Creating MySQL administrator '$LK_MYSQL_USERNAME'"
        echo "\
GRANT ALL PRIVILEGES ON *.* \
TO '$LK_MYSQL_USERNAME'@'localhost' \
IDENTIFIED BY '$LK_MYSQL_PASSWORD' \
WITH GRANT OPTION" | mysql -uroot
    fi

    lk_console_message "Configuring MySQL account self-service"
    install -m 00440 /dev/null "/etc/sudoers.d/${LK_PATH_PREFIX}mysql-self-service"
    cat <<EOF >"/etc/sudoers.d/${LK_PATH_PREFIX}mysql-self-service"
ALL ALL=(root) NOPASSWD:$LK_BASE/bin/lk-mysql-grant.sh
EOF
    lk_console_diff "/etc/sudoers.d/${LK_PATH_PREFIX}mysql-self-service"

    # TODO: create $LK_HOST_ACCOUNT database
fi

if lk_dpkg_installed memcached; then
    lk_console_message "Configuring Memcached"
    FILE="/etc/memcached.conf"
    edit_file "$FILE" \
        "^#?(-m$S+|--memory-limit(=|$S+))[0-9]+$S*\$" \
        "\1$LK_MEMCACHED_MEMORY_LIMIT" \
        "-m $LK_MEMCACHED_MEMORY_LIMIT"
fi

lk_console_message "Saving iptables rules"
iptables-save >"/etc/iptables/rules.v4"
ip6tables-save >"/etc/iptables/rules.v6"
lk_console_diff "/etc/iptables/rules.v4"
lk_console_diff "/etc/iptables/rules.v6"

lk_console_message "Running apt-get autoremove"
apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq autoremove

lk_hosting_configure_backup

lk_console_message "Provisioning complete"
lk_console_detail "Running:" "shutdown --$LK_SHUTDOWN_ACTION +$LK_SHUTDOWN_DELAY"
shutdown --"$LK_SHUTDOWN_ACTION" +"$LK_SHUTDOWN_DELAY"

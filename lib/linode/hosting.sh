#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob
lk_die() { s=$? && echo "$0: ${1-error $s}" >&2 && (exit $s) && false || exit; }

# <UDF name="LK_NODE_FQDN" label="Host FQDN" example="web01-dev-syd.linode.linacreative.com" />
# <UDF name="LK_NODE_TIMEZONE" label="System timezone" default="Australia/Sydney" />
# <UDF name="LK_FEATURES" label="Features to enable (comma-delimited)" manyof="nginx,apache+php,mysql,memcached" default="" />
# <UDF name="LK_PACKAGES" label="Additional packages to install (comma-delimited)" example="default-jre" default="" />
# <UDF name="LK_HOST_DOMAIN" label="Initial hosting domain" example="clientname.com.au" default="" />
# <UDF name="LK_HOST_ACCOUNT" label="Initial hosting account name (default: based on domain)" example="clientname" default="" />
# <UDF name="LK_HOST_SITE_ENABLE" label="Enable initial hosting site at launch" oneof="Y,N" default="N" />
# <UDF name="LK_ADMIN_USERS" label="Admin users to create (comma-delimited)" default="linac" />
# <UDF name="LK_ADMIN_EMAIL" label="Forwarding address for system email" example="tech@linacreative.com" />
# <UDF name="LK_TRUSTED_IP_ADDRESSES" label="Trusted IP addresses (comma-delimited)" example="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" default="" />
# <UDF name="LK_SSH_TRUSTED_ONLY" label="Block SSH access from untrusted IP addresses (trusted IP addresses required)" oneof="Y,N" default="N" />
# <UDF name="LK_SSH_TRUSTED_PORT" label="Trusted port for SSH access (login attempts allowed from any IP, must be higher than 1023)" example="2222" default="" />
# <UDF name="LK_SSH_JUMP_HOST" label="SSH jump proxy: hostname and optional port" example="jump.linacreative.com:9922" default="" />
# <UDF name="LK_SSH_JUMP_USER" label="SSH jump proxy: default user" default="" />
# <UDF name="LK_SSH_JUMP_KEY" label="SSH jump proxy: default key (must match the comment field of one installed key)" default="" />
# <UDF name="LK_REJECT_OUTPUT" label="Reject outgoing traffic by default" oneof="Y,N" default="N" />
# <UDF name="LK_ACCEPT_OUTPUT_HOSTS" label="Accept outgoing traffic to hosts (comma-delimited)" example="192.168.128.0/17,ip-ranges.amazonaws.com" default="" />
# <UDF name="LK_MYSQL_USERNAME" label="MySQL admin username (password required)" example="dbadmin" default="" />
# <UDF name="LK_MYSQL_PASSWORD" label="MySQL admin password (ignored if username not set)" default="" />
# <UDF name="LK_INNODB_BUFFER_SIZE" label="InnoDB buffer size (~80% of RAM for MySQL-only servers)" oneof="128M,256M,512M,768M,1024M,1536M,2048M,2560M,3072M,4096M,5120M,6144M,7168M,8192M" default="256M" />
# <UDF name="LK_OPCACHE_MEMORY_CONSUMPTION" label="PHP OPcache size" oneof="128,256,512,768,1024" default="256" />
# <UDF name="LK_PHP_VERSIONS" label="PHP versions to install (apache+php required, official packages removed if set)" manyof="5.6,7.0,7.1,7.2,7.3,7.4,8.0,8.1,8.2,8.3" default="" />
# <UDF name="LK_PHP_DEFAULT_VERSION" label="Default PHP version" oneof="5.6,7.0,7.1,7.2,7.3,7.4,8.0,8.1,8.2,8.3" default="" />
# <UDF name="LK_PHP_SETTINGS" label="php.ini settings (user can overwrite, comma-delimited, flag assumed if value is On/True/Yes or Off/False/No)" example="upload_max_filesize=24M,display_errors=On" default="" />
# <UDF name="LK_PHP_ADMIN_SETTINGS" label="Enforced php.ini settings (comma-delimited)" example="post_max_size=50M,log_errors=Off" default="" />
# <UDF name="LK_PHP_FPM_PM" label="Specify PHP-FPM process manager (default: based on pool count)" oneof="static,ondemand,dynamic" default="" />
# <UDF name="LK_SITE_PHP_FPM_MAX_CHILDREN" label="Default PHP-FPM pm.max_children" example="8" default="" />
# <UDF name="LK_SITE_PHP_FPM_MEMORY_LIMIT" label="Default PHP-FPM memory_limit" example="256" default="" />
# <UDF name="LK_MEMCACHED_MEMORY_LIMIT" label="Memcached size" oneof="64,128,256,512,768,1024" default="256" />
# <UDF name="LK_SMTP_RELAY" label="SMTP relay (system-wide)" example="[mail.clientname.com.au]:587" default="" />
# <UDF name="LK_SMTP_CREDENTIALS" label="SMTP relay credentials" example="username:Passw0rd!" default="" />
# <UDF name="LK_SMTP_SENDERS" label="Only relay email from these senders (comma-delimited)" example="@linode.linacreative.com,linode@linacreative.com" default="" />
# <UDF name="LK_SMTP_TRANSPORT_MAPS" label="Map comma-delimited recipient domains and addresses to next hop (semicolon-delimited)" example="domain1.com,domain2.com=[domain.com]:587;user@domain3.com=domain4.net" default="" />
# <UDF name="LK_EMAIL_DESTINATION" label="Only deliver email to this location (system-wide, STAGING ONLY)" example="/dev/null" default="" />
# <UDF name="LK_UPGRADE_EMAIL" label="Email address for unattended upgrade notifications" example="unattended-upgrades@linode.linacreative.com" default="" />
# <UDF name="LK_AUTO_REBOOT" label="Reboot automatically after unattended upgrades" oneof="Y,N" />
# <UDF name="LK_AUTO_REBOOT_TIME" label="Preferred automatic reboot time" oneof="02:00,03:00,04:00,05:00,06:00,07:00,08:00,09:00,10:00,11:00,12:00,13:00,14:00,15:00,16:00,17:00,18:00,19:00,20:00,21:00,22:00,23:00,00:00,01:00,now" default="02:00" />
# <UDF name="LK_AUTO_BACKUP_SCHEDULE" label="Automatic backup schedule (format: 0-59 0-23 1-31 1-12|jan-dec 0-7|sun-sat)" example="0 1 * * *" default="" />
# <UDF name="LK_SNAPSHOT_HOURLY_MAX_AGE" label="Backup: hourly snapshot max age (hours, -1 = no maximum)" example="72" default="24" />
# <UDF name="LK_SNAPSHOT_DAILY_MAX_AGE" label="Backup: daily snapshot max age (days, -1 = no maximum)" example="14" default="7" />
# <UDF name="LK_SNAPSHOT_WEEKLY_MAX_AGE" label="Backup: weekly snapshot max age (weeks, -1 = no maximum)" example="-1" default="52" />
# <UDF name="LK_SNAPSHOT_FAILED_MAX_AGE" label="Backup: failed snapshot max age (days, -1 = no maximum)" default="28" />
# <UDF name="LK_LAUNCHPAD_PPA_MIRROR" label="PPA base URL (default: http://ppa.launchpadcontent.net)" example="http://ppa.mirror" default="" />
# <UDF name="LK_PATH_PREFIX" label="Prefix for files installed by lk-platform" default="lk-" />
# <UDF name="LK_DEBUG" label="Create trace output from provisioning script" oneof="Y,N" default="N" />
# <UDF name="LK_SHUTDOWN_ACTION" label="Reboot or power down after provisioning" oneof="reboot,poweroff" default="reboot" />
# <UDF name="LK_PLATFORM_BRANCH" label="lk-platform tracking branch" oneof="main,develop,master" default="main" />

# Redirect output to /dev/console if there is no controlling terminal
{ : >/dev/tty ||
    ! : >/dev/console; } 2>/dev/null ||
    exec &>/dev/console

SCRIPT_VARS=$(declare -p $(eval \
    "printf '%s\n'$(printf ' "${!%s@}"' {a..z} {A..Z} _)" |
    grep -Evi 'password'))
SCRIPT_ENV=$(printenv | grep -Evi '^[^=]*password[^=]*=' || true)

# Apply defaults from the tags above (use `lk_linode_get_udf_vars` to generate)
LK_NODE_FQDN=${LK_NODE_FQDN-}
LK_NODE_TIMEZONE=${LK_NODE_TIMEZONE:-Australia/Sydney}
LK_FEATURES=${LK_FEATURES-}
LK_PACKAGES=${LK_PACKAGES-}
LK_HOST_DOMAIN=${LK_HOST_DOMAIN-}
LK_HOST_ACCOUNT=${LK_HOST_ACCOUNT-}
LK_HOST_SITE_ENABLE=${LK_HOST_SITE_ENABLE:-N}
LK_ADMIN_USERS=${LK_ADMIN_USERS:-linac}
LK_ADMIN_EMAIL=${LK_ADMIN_EMAIL-}
LK_TRUSTED_IP_ADDRESSES=${LK_TRUSTED_IP_ADDRESSES-}
LK_SSH_TRUSTED_ONLY=${LK_SSH_TRUSTED_ONLY:-N}
LK_SSH_TRUSTED_PORT=${LK_SSH_TRUSTED_PORT-}
LK_SSH_JUMP_HOST=${LK_SSH_JUMP_HOST-}
LK_SSH_JUMP_USER=${LK_SSH_JUMP_USER-}
LK_SSH_JUMP_KEY=${LK_SSH_JUMP_KEY-}
LK_REJECT_OUTPUT=${LK_REJECT_OUTPUT:-N}
LK_ACCEPT_OUTPUT_HOSTS=${LK_ACCEPT_OUTPUT_HOSTS-}
LK_MYSQL_USERNAME=${LK_MYSQL_USERNAME-}
LK_MYSQL_PASSWORD=${LK_MYSQL_PASSWORD-}
LK_INNODB_BUFFER_SIZE=${LK_INNODB_BUFFER_SIZE:-256M}
LK_OPCACHE_MEMORY_CONSUMPTION=${LK_OPCACHE_MEMORY_CONSUMPTION:-256}
LK_PHP_VERSIONS=${LK_PHP_VERSIONS-}
LK_PHP_DEFAULT_VERSION=${LK_PHP_DEFAULT_VERSION-}
LK_PHP_SETTINGS=${LK_PHP_SETTINGS-}
LK_PHP_ADMIN_SETTINGS=${LK_PHP_ADMIN_SETTINGS-}
LK_PHP_FPM_PM=${LK_PHP_FPM_PM-}
LK_SITE_PHP_FPM_MAX_CHILDREN=${LK_SITE_PHP_FPM_MAX_CHILDREN-}
LK_SITE_PHP_FPM_MEMORY_LIMIT=${LK_SITE_PHP_FPM_MEMORY_LIMIT-}
LK_MEMCACHED_MEMORY_LIMIT=${LK_MEMCACHED_MEMORY_LIMIT:-256}
LK_SMTP_RELAY=${LK_SMTP_RELAY-}
LK_SMTP_CREDENTIALS=${LK_SMTP_CREDENTIALS-}
LK_SMTP_SENDERS=${LK_SMTP_SENDERS-}
LK_SMTP_TRANSPORT_MAPS=${LK_SMTP_TRANSPORT_MAPS-}
LK_EMAIL_DESTINATION=${LK_EMAIL_DESTINATION-}
LK_UPGRADE_EMAIL=${LK_UPGRADE_EMAIL-}
LK_AUTO_REBOOT=${LK_AUTO_REBOOT-}
LK_AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME:-02:00}
LK_AUTO_BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE-}
LK_SNAPSHOT_HOURLY_MAX_AGE=${LK_SNAPSHOT_HOURLY_MAX_AGE:-24}
LK_SNAPSHOT_DAILY_MAX_AGE=${LK_SNAPSHOT_DAILY_MAX_AGE:-7}
LK_SNAPSHOT_WEEKLY_MAX_AGE=${LK_SNAPSHOT_WEEKLY_MAX_AGE:-52}
LK_SNAPSHOT_FAILED_MAX_AGE=${LK_SNAPSHOT_FAILED_MAX_AGE:-28}
LK_LAUNCHPAD_PPA_MIRROR=${LK_LAUNCHPAD_PPA_MIRROR-}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_DEBUG=${LK_DEBUG:-N}
LK_SHUTDOWN_ACTION=${LK_SHUTDOWN_ACTION:-reboot}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-main}

[ "$EUID" -eq 0 ] || lk_die "not running as root"
[ "$OSTYPE" = linux-gnu ] || lk_die "not running on Linux"
([ -r /etc/os-release ] && . /etc/os-release && [ "$NAME" = Ubuntu ]) ||
    lk_die "not running on Ubuntu"

KEYS_FILE=/root/.ssh/authorized_keys
[ -s "$KEYS_FILE" ] || lk_die "no public keys in $KEYS_FILE"

LK_NODE_HOSTNAME=${LK_NODE_FQDN%%.*}
LK_HOST_DOMAIN=${LK_HOST_DOMAIN#www.}
LK_HOST_ACCOUNT=${LK_HOST_ACCOUNT:-${LK_HOST_DOMAIN%%.*}}

! id "$LK_HOST_ACCOUNT" &>/dev/null ||
    lk_die "illegal username: $LK_HOST_ACCOUNT"

LK_BASE=/opt/lk-platform
export "${!LK_@}" \
    _LK_BOOTSTRAP=1 \
    _LK_COLUMNS=120 \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true

_DIR=/tmp/${LK_PATH_PREFIX}install
mkdir -p "$_DIR"

CURL_OPTIONS=(-fsSLH "Cache-Control: no-cache" -H "Pragma: no-cache" --retry 9 --retry-max-time 120)
YELLOW=$'\E[33m'
CYAN=$'\E[36m'
BOLD=$'\E[1m'
RESET=$'\E[m'
echo "$BOLD$CYAN==> $RESET${BOLD}Acquiring prerequisites$RESET" >&2
REPO_URL=https://raw.githubusercontent.com/lkrms/lk-platform
_LK_SOURCED=
for FILE_PATH in \
    /lib/bash/include/{core,debian,git}.sh /share/sudoers.d/default; do
    FILE=$_DIR/${FILE_PATH##*/}
    URL=$REPO_URL/$LK_PLATFORM_BRANCH$FILE_PATH
    MESSAGE="$BOLD$YELLOW -> $RESET{}$YELLOW $URL$RESET"
    if [ ! -e "$FILE" ]; then
        echo "${MESSAGE/{\}/Downloading:}" >&2
        curl "${CURL_OPTIONS[@]}" --output "$FILE" "$URL" || {
            rm -f "$FILE"
            lk_die "download failed: $URL"
        }
    else
        echo "${MESSAGE/{\}/Already downloaded:}" >&2
    fi
    # TODO: verify before sourcing
    [[ ! $FILE_PATH =~ /include/([a-z0-9_]+)\.sh$ ]] || {
        _LK_SOURCED+=,${BASH_REMATCH[1]}
        . "$FILE"
    }
done

IMAGE_BASE_PACKAGES=$(lk_mktemp_file)
IMAGE_INITIAL_PACKAGE_STATE=$(lk_mktemp_file)
lk_delete_on_exit "$IMAGE_BASE_PACKAGES" "$IMAGE_INITIAL_PACKAGE_STATE"
lk_apt_marked_manual_list | sort >"$IMAGE_BASE_PACKAGES"
lk_dpkg_installed_versions | sort >"$IMAGE_INITIAL_PACKAGE_STATE"

INSTALL=(
    bsdmainutils
    debconf
    git
    jq
    perl
    tzdata
    $(lk_apt_available_list icdiff)
)
lk_keep_trying lk_apt_install "${INSTALL[@]}"

LOG_FILE=/var/log/lk-platform-install
install -m 00640 -g adm /dev/null "$LOG_FILE.log"
lk_log_start "$LOG_FILE"

if lk_debug; then
    install -m 00640 -g adm /dev/null "$LOG_FILE.trace"
    LK_LOG_TRACE_FILE=$LOG_FILE.trace \
        lk_start_trace
fi

lk_tty_log "Bootstrapping Ubuntu for hosting"
lk_tty_print "Checking system state"
lk_tty_detail "Environment:" "$SCRIPT_ENV"
! lk_debug ||
    lk_tty_detail "Variables:" "$SCRIPT_VARS"
lk_tty_list_detail - \
    "Pre-installed packages marked as 'manually installed':" \
    <"$IMAGE_BASE_PACKAGES"
lk_tty_detail "All pre-installed packages:" \
    "$(wc -l <"$IMAGE_INITIAL_PACKAGE_STATE") (see $LK_BASE/etc/packages.conf)"

lk_keep_trying lk_git_provision_repo -s \
    -o :adm \
    -b "$LK_PLATFORM_BRANCH" \
    -n lk-platform \
    https://github.com/lkrms/lk-platform.git \
    "$LK_BASE"

install -d -m 02775 -g adm "$LK_BASE"/{etc{,/lk-platform},var}
install -d -m 01777 -g adm "$LK_BASE"/var/log
install -d -m 00750 -g adm "$LK_BASE"/var/backup
install -m 00664 -g adm /dev/null "$LK_BASE"/etc/packages.conf
for FILE in IMAGE_BASE_PACKAGES IMAGE_INITIAL_PACKAGE_STATE; do
    echo "$FILE=("
    sed -E 's/^/    /' "${!FILE}"
    echo ")"
done >"$LK_BASE"/etc/packages.conf

eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
if ADMIN_USERS=($(grep -Eo "$LINUX_USERNAME_REGEX" <<<"$LK_ADMIN_USERS")); then
    REGEX=$(lk_regex_implode "${ADMIN_USERS[@]}")
    ADMIN_USER_KEYS=$(sed -E "/$S$REGEX\$/!d" "$KEYS_FILE")
    HOST_KEYS=$(sed -E "/$S$REGEX\$/d" "$KEYS_FILE")
else
    ADMIN_USER_KEYS=
    HOST_KEYS=$(cat "$KEYS_FILE")
fi

if [[ $LK_SSH_JUMP_KEY =~ ^[-a-zA-Z0-9_]+$ ]] &&
    JUMP_KEY=$(grep -E "$S$LK_SSH_JUMP_KEY\$" "$KEYS_FILE") &&
    [ "$(wc -l <<<"$JUMP_KEY")" -eq 1 ]; then
    FILE=/etc/skel/.ssh/${LK_PATH_PREFIX}keys/jump
    lk_tty_print "Installing default key for SSH jump proxy:" "$FILE"
    install -d -m 00700 /etc/skel/.ssh{,"/${LK_PATH_PREFIX}keys"} &&
        install -m 00600 /dev/null "$FILE" &&
        echo "$JUMP_KEY" >"$FILE"
fi

_LK_ADMIN_USER_KEYS=$ADMIN_USER_KEYS \
    _LK_HOST_KEYS=$HOST_KEYS \
    _LK_NO_LOG=1 \
    lk_maybe_trace "$LK_BASE/bin/lk-provision-hosting.sh" || lk_die ""

lk_tty_print
lk_tty_print "Finalising bootstrap"

if [ ${#ADMIN_USERS[@]} -gt 0 ]; then
    lk_tty_run_detail rm -v "$KEYS_FILE"
fi

lk_tty_run_detail shutdown "--$LK_SHUTDOWN_ACTION" now

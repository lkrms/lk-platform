#!/bin/bash
# shellcheck disable=SC1091,SC2001,SC2086,SC2206,SC2207
#
# <UDF name="NODE_HOSTNAME" label="Short hostname" example="web01-dev-syd" />
# <UDF name="NODE_FQDN" label="Host FQDN" example="web01-dev-syd.linode.linacreative.com" />
# <UDF name="NODE_TIMEZONE" label="System timezone" default="Australia/Sydney" />
# <UDF name="NODE_SERVICES" label="Services to install and configure" manyof="apache+php,mysql,memcached,fail2ban,wp-cli,jre" default="" />
# <UDF name="NODE_PACKAGES" label="Additional packages to install (comma-delimited)" default="" />
# <UDF name="HOST_DOMAIN" label="Initial hosting domain" example="clientname.com.au" default="" />
# <UDF name="HOST_ACCOUNT" label="Initial hosting account name (default: based on domain)" example="clientname" default="" />
# <UDF name="HOST_SITE_ENABLE" label="Enable initial hosting site at launch" oneof="Y,N" default="N" />
# <UDF name="ADMIN_USERS" label="Admin users to create (comma-delimited)" default="linac" />
# <UDF name="ADMIN_EMAIL" label="Forwarding address for system email" example="tech@linacreative.com" />
# <UDF name="TRUSTED_IP_ADDRESSES" label="Trusted IP addresses (comma-delimited)" example="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" default="" />
# <UDF name="SSH_TRUSTED_ONLY" label="Block SSH access from untrusted IP addresses (trusted IP addresses required)" oneof="Y,N" default="N" />
# <UDF name="REJECT_OUTPUT" label="Reject outgoing traffic by default" oneof="Y,N" default="N" />
# <UDF name="ACCEPT_OUTPUT_HOSTS" label="Accept outgoing traffic to hosts (comma-delimited)" example="192.168.128.0/17,ip-ranges.amazonaws.com" default="" />
# <UDF name="MYSQL_USERNAME" label="MySQL admin username (password required)" example="dbadmin" default="" />
# <UDF name="MYSQL_PASSWORD" label="MySQL admin password (ignored if username not set)" default="" />
# <UDF name="INNODB_BUFFER_SIZE" label="InnoDB buffer size (~80% of RAM for MySQL-only servers)" oneof="128M,256M,512M,768M,1024M,1536M,2048M,2560M,3072M,4096M,5120M,6144M,7168M,8192M" default="256M" />
# <UDF name="OPCACHE_MEMORY_CONSUMPTION" label="PHP OPcache size" oneof="128,256,512,768,1024" default="256" />
# <UDF name="PHP_SETTINGS" label="php.ini settings (user can overwrite, comma-delimited, flag assumed if value is On/True/Yes or Off/False/No)" example="upload_max_filesize=24M,display_errors=On" default="" />
# <UDF name="PHP_ADMIN_SETTINGS" label="Enforced php.ini settings (comma-delimited)" example="post_max_size=50M,log_errors=Off" default="" />
# <UDF name="MEMCACHED_MEMORY_LIMIT" label="Memcached size" oneof="64,128,256,512,768,1024" default="256" />
# <UDF name="SMTP_RELAY" label="SMTP relay (system-wide)" example="[mail.clientname.com.au]:587" default="" />
# <UDF name="EMAIL_BLACKHOLE" label="Email black hole (system-wide, STAGING ONLY)" example="/dev/null" default="" />
# <UDF name="AUTO_REBOOT" label="Reboot automatically after unattended upgrades" oneof="Y,N" />
# <UDF name="AUTO_REBOOT_TIME" label="Preferred automatic reboot time" oneof="02:00,03:00,04:00,05:00,06:00,07:00,08:00,09:00,10:00,11:00,12:00,13:00,14:00,15:00,16:00,17:00,18:00,19:00,20:00,21:00,22:00,23:00,00:00,01:00,now" default="02:00" />
# <UDF name="PATH_PREFIX" label="Prefix for files installed by this script" default="lk-" />
# <UDF name="SCRIPT_DEBUG" label="Create trace output from provisioning script" oneof="Y,N" default="Y" />
# <UDF name="SHUTDOWN_ACTION" label="Reboot or power down after provisioning" oneof="reboot,poweroff" default="reboot" />
# <UDF name="SHUTDOWN_DELAY" label="Delay before shutdown/reboot after provisioning (in minutes)" default="0" />
# <UDF name="LK_PLATFORM_BRANCH" label="lk-platform tracking branch" oneof="master,develop" default="master" />

[ ! "${SCRIPT_DEBUG:-Y}" = Y ] ||
    SCRIPT_DEBUG_VARS="$(
        unset BASH_EXECUTION_STRING
        declare -p
    )"

# Use lk_bash_udf_defaults to regenerate the following after changes above
NODE_HOSTNAME=${NODE_HOSTNAME:-}
NODE_FQDN=${NODE_FQDN:-}
NODE_TIMEZONE=${NODE_TIMEZONE:-Australia/Sydney}
NODE_SERVICES=${NODE_SERVICES:-}
NODE_PACKAGES=${NODE_PACKAGES:-}
HOST_DOMAIN=${HOST_DOMAIN:-}
HOST_ACCOUNT=${HOST_ACCOUNT:-}
HOST_SITE_ENABLE=${HOST_SITE_ENABLE:-N}
ADMIN_USERS=${ADMIN_USERS:-linac}
ADMIN_EMAIL=${ADMIN_EMAIL:-}
TRUSTED_IP_ADDRESSES=${TRUSTED_IP_ADDRESSES:-}
SSH_TRUSTED_ONLY=${SSH_TRUSTED_ONLY:-N}
REJECT_OUTPUT=${REJECT_OUTPUT:-N}
ACCEPT_OUTPUT_HOSTS=${ACCEPT_OUTPUT_HOSTS:-}
MYSQL_USERNAME=${MYSQL_USERNAME:-}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-}
INNODB_BUFFER_SIZE=${INNODB_BUFFER_SIZE:-256M}
OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION:-256}
PHP_SETTINGS=${PHP_SETTINGS:-}
PHP_ADMIN_SETTINGS=${PHP_ADMIN_SETTINGS:-}
MEMCACHED_MEMORY_LIMIT=${MEMCACHED_MEMORY_LIMIT:-256}
SMTP_RELAY=${SMTP_RELAY:-}
EMAIL_BLACKHOLE=${EMAIL_BLACKHOLE:-}
AUTO_REBOOT=${AUTO_REBOOT:-}
AUTO_REBOOT_TIME=${AUTO_REBOOT_TIME:-02:00}
PATH_PREFIX=${PATH_PREFIX:-lk-}
SCRIPT_DEBUG=${SCRIPT_DEBUG:-Y}
SHUTDOWN_ACTION=${SHUTDOWN_ACTION:-reboot}
SHUTDOWN_DELAY=${SHUTDOWN_DELAY:-0}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

[ ! "$SCRIPT_DEBUG" = Y ] || {
    TRACE_FILE=/var/log/${PATH_PREFIX}install.trace
    install -v -m 0640 -g "adm" /dev/null "$TRACE_FILE"
    exec 4>>"$TRACE_FILE"
    BASH_XTRACEFD=4
    set -x
}

set -euo pipefail
shopt -s nullglob
lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (return $s) && false || exit; }

FIELD_ERRORS=$(
    STATUS=0
    function _list() {
        eval "local FN=\$1 $2=\$$2 IFS=, NULL=1 VALID=1 SELECTED i"
        shift
        SELECTED=(${!1})
        unset IFS
        for i in "${SELECTED[@]}"; do
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
    FQDN_REGEX="($DOMAIN_PART_REGEX(\\.|\$)){2,}"
    EMAIL_ADDRESS_REGEX="[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~]([-a-zA-Z0-9.!#\$%&'*+/=?^_\`{|}~]{,62}[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~])?@$FQDN_REGEX"
    USERNAME_REGEX="[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\\\$)"
    # https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source
    DEB_PKG_REGEX="[a-z0-9][-a-z0-9+.]+"

    OCTET="(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])"
    IPV4_REGEX="($OCTET\\.){3}$OCTET(/(3[0-2]|[12][0-9]|[1-9]))?"

    HEXTET="[0-9a-fA-F]{1,4}"
    PREFIX="/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])"
    IPV6_REGEX="(($HEXTET:){7}(:|$HEXTET)|($HEXTET:){6}(:|:$HEXTET)|($HEXTET:){5}(:|(:$HEXTET){1,2})|($HEXTET:){4}(:|(:$HEXTET){1,3})|($HEXTET:){3}(:|(:$HEXTET){1,4})|($HEXTET:){2}(:|(:$HEXTET){1,5})|$HEXTET:(:|(:$HEXTET){1,6})|:(:|(:$HEXTET){1,7}))($PREFIX)?"

    IP_REGEX="($IPV4_REGEX|$IPV6_REGEX)"
    HOST_REGEX="($IPV4_REGEX|$IPV6_REGEX|$DOMAIN_PART_REGEX|$FQDN_REGEX)"

    PHP_SETTING_NAME_REGEX="[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*"
    PHP_SETTING_REGEX="$PHP_SETTING_NAME_REGEX=.+"

    # required fields
    REQUIRED=1
    valid NODE_HOSTNAME "^$DOMAIN_PART_REGEX\$"
    valid NODE_FQDN "^$FQDN_REGEX\$"
    one_of NODE_TIMEZONE < <(timedatectl list-timezones)
    valid ADMIN_EMAIL "^$EMAIL_ADDRESS_REGEX\$"
    one_of AUTO_REBOOT Y N

    # optional fields
    REQUIRED=0
    many_of NODE_SERVICES \
        "apache+php" \
        "mysql" \
        "memcached" \
        "fail2ban" \
        "wp-cli" \
        "jre"
    valid_list NODE_PACKAGES "^$DEB_PKG_REGEX\$"
    valid HOST_DOMAIN "^$FQDN_REGEX\$"
    valid HOST_ACCOUNT "^$USERNAME_REGEX\$"
    [ -z "$HOST_DOMAIN" ] || REQUIRED=1
    one_of HOST_SITE_ENABLE Y N
    REQUIRED=0
    valid_list ADMIN_USERS "^$USERNAME_REGEX\$"
    [ ! "$SSH_TRUSTED_ONLY" = Y ] || REQUIRED=1
    valid_list TRUSTED_IP_ADDRESSES "^$IP_REGEX\$"
    REQUIRED=0
    one_of SSH_TRUSTED_ONLY Y N
    one_of REJECT_OUTPUT Y N
    valid_list ACCEPT_OUTPUT_HOSTS "^$HOST_REGEX\$"
    valid MYSQL_USERNAME "^$USERNAME_REGEX\$"
    [ -z "$MYSQL_USERNAME" ] || not_null MYSQL_PASSWORD
    valid INNODB_BUFFER_SIZE "^[0-9]+[kmgtpeKMGTPE]?\$"
    valid OPCACHE_MEMORY_CONSUMPTION "^[0-9]+\$"
    valid_list PHP_SETTINGS "^$PHP_SETTING_REGEX\$"
    valid_list PHP_ADMIN_SETTINGS "^$PHP_SETTING_REGEX\$"
    valid MEMCACHED_MEMORY_LIMIT "^[0-9]+\$"
    valid SMTP_RELAY "^($HOST_REGEX|\\[$HOST_REGEX\\])(:[0-9]+)?\$"
    # TODO: validate EMAIL_BLACKHOLE
    [ ! "$AUTO_REBOOT" = Y ] || REQUIRED=1
    valid AUTO_REBOOT_TIME "^(([01][0-9]|2[0-3]):[0-5][0-9]|now)\$"
    REQUIRED=0
    valid PATH_PREFIX "^$DOMAIN_PART_REGEX-\$"
    one_of SCRIPT_DEBUG Y N
    one_of SHUTDOWN_ACTION reboot poweroff
    valid SHUTDOWN_DELAY "^[0-9]+\$"
    # TODO: validate LK_PLATFORM_BRANCH
    exit $STATUS
) || lk_die "$(printf '%s\n' "invalid fields" \
    "  - ${FIELD_ERRORS//$'\n'/$'\n'  - }")"

[ "$EUID" -eq 0 ] || lk_die "not running as root"
[ "$(uname -s)" = Linux ] || lk_die "not running on Linux"
[ "$(lsb_release -si)" = Ubuntu ] || lk_die "not running on Ubuntu"

KEYS_FILE=/root/.ssh/authorized_keys
[ -s "$KEYS_FILE" ] || lk_die "no public keys at $KEYS_FILE"

PATH_PREFIX_ALPHA=$(sed 's/[^a-zA-Z0-9]//g' <<<"$PATH_PREFIX")
HOST_DOMAIN=${HOST_DOMAIN#www.}
HOST_ACCOUNT=${HOST_ACCOUNT:-${HOST_DOMAIN%%.*}}

# The following functions are the minimum required to install lk-platform before
# sourcing core.sh and everything else required to provision the system

function lk_dpkg_installed() {
    local STATUS
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}' "$1" 2>/dev/null) &&
        [ "$STATUS" = installed ]
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
${LK_CONSOLE_PREFIX-==> }\
${1//$'\n'/$'\n'"${LK_CONSOLE_SPACES-    }"}" >&"${_LK_FD:-2}"
}

function lk_console_item() {
    lk_console_message "$1$(
        [ "${2//$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"$2"
    )"
}

function lk_console_detail() {
    local LK_CONSOLE_PREFIX="   -> " LK_CONSOLE_SPACES="      "
    [ $# -le 1 ] &&
        lk_console_message "$1" ||
        lk_console_item "$1" "$2"
}

function lk_keep_original() {
    [ ! -e "$1" ] ||
        cp -nav "$1" "$1.orig"
}

# edit_file FILE SEARCH_PATTERN REPLACE_PATTERN [ADD_TEXT]
function edit_file() {
    local SED_SCRIPT="0,/$2/{s/$2/$3/}" BEFORE AFTER
    [ -f "$1" ] || [ -n "${4:-}" ] || lk_die "file not found: $1"
    [ "${MATCH_MANY:-N}" = "N" ] || SED_SCRIPT="s/$2/$3/"
    if grep -Eq -e "$2" "$1" 2>/dev/null; then
        lk_keep_original "$1"
        BEFORE="$(cat "$1")"
        AFTER="$(sed -E "$SED_SCRIPT" "$1")"
        [ "$BEFORE" = "$AFTER" ] || {
            sed -Ei "$SED_SCRIPT" "$1"
        }
    elif [ -n "${4:-}" ]; then
        echo "$4" >>"$1"
    else
        lk_die "no line matching $2 in $1"
    fi
    [ "${EDIT_FILE_LOG:-Y}" = "N" ] || lk_console_file "$1"
}

function lk_console_file() {
    lk_console_item "$1:" "\
<<<<
$(if [ -f "$1.orig" ]; then
        ! diff "$1.orig" "$1" || echo "<unchanged>"
    else
        cat "$1"
    fi)
>>>>"
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

LOCK_FILE=/tmp/${PATH_PREFIX}install.lock
exec 9>"$LOCK_FILE"
flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"

LOG_FILE=/var/log/${PATH_PREFIX}install.log
OUT_FILE=/var/log/${PATH_PREFIX}install.out
install -v -m 0640 -g "adm" /dev/null "$LOG_FILE"
install -v -m 0640 -g "adm" /dev/null "$OUT_FILE"
exec > >(tee >(lk_log >>"$OUT_FILE")) 2>&1
exec 3> >(tee >(lk_log >>"$LOG_FILE") >&1)
_LK_FD=3

S="[[:space:]]"

ADMIN_USER_KEYS="$([ -z "$ADMIN_USERS" ] ||
    grep -E "$S(${ADMIN_USERS//,/|})\$" "$KEYS_FILE")" || true
HOST_KEYS="$([ -z "$ADMIN_USERS" ] &&
    cat "$KEYS_FILE" ||
    grep -Ev "$S(${ADMIN_USERS//,/|})\$" "$KEYS_FILE")" || true

lk_console_message "Provisioning Ubuntu"
lk_console_detail "Environment:" \
    "$(printenv | grep -v '^LS_COLORS=' | sort)"
[ ! "$SCRIPT_DEBUG" = Y ] ||
    lk_console_detail "Variables:" "$SCRIPT_DEBUG_VARS"

# Don't propagate field values to the environment of other commands
export -n \
    HOST_DOMAIN HOST_ACCOUNT HOST_SITE_ENABLE \
    ADMIN_USERS TRUSTED_IP_ADDRESSES SSH_TRUSTED_ONLY \
    REJECT_OUTPUT ACCEPT_OUTPUT_HOSTS \
    MYSQL_USERNAME MYSQL_PASSWORD \
    INNODB_BUFFER_SIZE \
    OPCACHE_MEMORY_CONSUMPTION PHP_SETTINGS PHP_ADMIN_SETTINGS \
    MEMCACHED_MEMORY_LIMIT \
    SMTP_RELAY EMAIL_BLACKHOLE \
    AUTO_REBOOT AUTO_REBOOT_TIME \
    SCRIPT_DEBUG SHUTDOWN_ACTION SHUTDOWN_DELAY

export LK_BASE=/opt/${PATH_PREFIX}platform \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    PIP_NO_INPUT=1

IMAGE_BASE_PACKAGES=($(apt-mark showmanual))
lk_console_detail "Pre-installed packages:" \
    "$(printf '%s\n' "${IMAGE_BASE_PACKAGES[@]}")"

### move to lk-provision-hosting.sh
. /etc/lsb-release

APT_GET_ARGS=(
    --no-install-recommends
    --no-install-suggests
)
REPOS=()
ADD_APT_REPOSITORY_ARGS=(-yn)
EXCLUDE_PACKAGES=()
CERTBOT_REPO=ppa:certbot/certbot
case "$DISTRIB_RELEASE" in
16.04)
    REPOS+=("$CERTBOT_REPO")
    ADD_APT_REPOSITORY_ARGS=(-y)
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
### //

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
lk_console_detail "IPv4 address:" "${IPV4_ADDRESS:-<none>}"

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
lk_console_detail "IPv6 address:" "${IPV6_ADDRESS:-<none>}"

### move to lk-provision-hosting.sh
lk_console_message "Enabling persistent journald storage"
edit_file "/etc/systemd/journald.conf" "^#?Storage=.*\$" "Storage=persistent"
systemctl restart systemd-journald.service
### //

lk_console_message "Setting system hostname"
lk_console_detail "Running:" "hostnamectl set-hostname $NODE_HOSTNAME"
hostnamectl set-hostname "$NODE_HOSTNAME"

# Apache won't resolve a name-based <VirtualHost> correctly if ServerName
# resolves to a loopback address, so if the host's FQDN is also the initial
# hosting domain, don't associate it with 127.0.1.1
[ "${NODE_FQDN#www.}" = "$HOST_DOMAIN" ] || HOSTS_NODE_FQDN="$NODE_FQDN"
FILE=/etc/hosts
lk_console_detail "Adding entries to" "$FILE"
cat <<EOF >>"$FILE"

# Added by ${0##*/} at $(lk_date_log)
127.0.1.1 ${HOSTS_NODE_FQDN:+$HOSTS_NODE_FQDN }$NODE_HOSTNAME${HOSTS_NODE_FQDN:+${IPV4_ADDRESS:+
$IPV4_ADDRESS $NODE_FQDN}${IPV6_ADDRESS:+
$IPV6_ADDRESS $NODE_FQDN}}
EOF
lk_console_file "$FILE"

### move to lk-provision-hosting.sh
lk_console_message "Configuring APT"
FILE=/etc/apt/apt.conf.d/90${PATH_PREFIX}defaults
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
    "Unattended-Upgrade::Mail" "root"
    "Unattended-Upgrade::Remove-Unused-Kernel-Packages" "true"
)
if [ "$AUTO_REBOOT" = Y ]; then
    lk_console_detail "Enabling automatic reboot"
    APT_OPTIONS+=(
        "Unattended-Upgrade::Automatic-Reboot" "true"
        "Unattended-Upgrade::Automatic-Reboot-Time" "$AUTO_REBOOT_TIME"
    )
fi
{
    printf '# Created by %s at %s\n' "${0##*/}" "$(lk_date_log)"
    printf '%s "%s";\n' "${APT_OPTIONS[@]}"
} >"$FILE"
lk_console_file "$FILE"
### //

# see `man invoke-rc.d` for more information
lk_console_message "Disabling automatic \"systemctl start\" when new services are installed"
cat <<EOF >"/usr/sbin/policy-rc.d"
#!/bin/bash
# Created by ${0##*/} at $(lk_date_log)
$(declare -f lk_date_log)
LOG=(
    "====> \${0##*/}: init script policy helper invoked"
    "Arguments:
\$([ "\$#" -eq 0 ] || printf '  - %q\n' "\$@")")
DEPLOY_PENDING=N
EXIT_STATUS=0
exec 9>"/tmp/${PATH_PREFIX}install.lock"
if ! flock -n 9; then
    DEPLOY_PENDING=Y
    [ "\${DPKG_MAINTSCRIPT_NAME:-}" != postinst ] || EXIT_STATUS=101
fi
LOG+=("Deploy pending: \$DEPLOY_PENDING")
LOG+=("Exit status: \$EXIT_STATUS")
printf '%s %s\n%s\n' "\$(lk_date_log)" "\${LOG[0]}" "\$(
    LOG=("\${LOG[@]:1}")
    printf '  %s\n' "\${LOG[@]//\$'\n'/\$'\n' }"
)" >>"/var/log/${PATH_PREFIX}policy-rc.log"
exit "\$EXIT_STATUS"
EOF
chmod a+x "/usr/sbin/policy-rc.d"
lk_console_file "/usr/sbin/policy-rc.d"

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
if [ "${#REMOVE_PACKAGES[@]}" -gt 0 ]; then
    lk_console_item "Removing APT packages:" "${REMOVE_PACKAGES[*]}"
    apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq purge "${REMOVE_PACKAGES[@]}"
fi

lk_console_message "Disabling unnecessary motd scripts"
for FILE in 10-help-text 50-motd-news 91-release-upgrade 98-fsck-at-reboot; do
    [ ! -x "/etc/update-motd.d/$FILE" ] || chmod -c a-x "/etc/update-motd.d/$FILE"
done

lk_console_message "Configuring kernel parameters"
FILE="/etc/sysctl.d/90-${PATH_PREFIX}defaults.conf"
cat <<EOF >"$FILE"
# Avoid paging and swapping if at all possible
vm.swappiness = 1

# Apache and PHP-FPM both default to listen.backlog = 511, but the
# default value of SOMAXCONN is only 128
net.core.somaxconn = 1024
EOF
lk_console_file "$FILE"
sysctl --system

lk_console_message "Sourcing $LK_BASE/lib/bash/rc.sh in ~/.bashrc for all users"
RC_ESCAPED="$(printf '%q' "$LK_BASE/lib/bash/rc.sh")"
BASH_SKEL="
# Added by ${0##*/} at $(lk_date_log)
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
install -v -d -m 0755 "$DIR"
# disable byobu-prompt
cat <<EOF >"$DIR/prompt"
[ -r /usr/share/byobu/profiles/bashrc ] && . /usr/share/byobu/profiles/bashrc  #byobu-prompt#
EOF
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
BYOBU_CHARMAP=x
EOF

DIR="/etc/skel.$PATH_PREFIX_ALPHA"
[ ! -e "$DIR" ] || lk_die "already exists: $DIR"
lk_console_message "Creating $DIR (for hosting accounts)"
cp -av "/etc/skel" "$DIR"
install -v -d -m 0755 "$DIR/.ssh"
install -v -m 0644 /dev/null "$DIR/.ssh/authorized_keys"
[ -z "$HOST_KEYS" ] || echo "$HOST_KEYS" >>"$DIR/.ssh/authorized_keys"

for USERNAME in ${ADMIN_USERS//,/ }; do
    FIRST_ADMIN="${FIRST_ADMIN:-$USERNAME}"
    lk_console_message "Creating superuser '$USERNAME'"
    # HOME_DIR may already exist, e.g. if filesystems have been mounted in it
    useradd --no-create-home --groups "adm,sudo" --shell "/bin/bash" "$USERNAME"
    USER_GROUP="$(id -gn "$USERNAME")"
    USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
    install -v -d -m 0750 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME"
    sudo -Hu "$USERNAME" cp -nRTv "/etc/skel" "$USER_HOME"
    if [ -z "$ADMIN_USER_KEYS" ]; then
        [ ! -e "/root/.ssh" ] || {
            lk_console_message "Moving /root/.ssh to /home/$USERNAME/.ssh"
            mv "/root/.ssh" "/home/$USERNAME/" &&
                chown -R "$USERNAME": "/home/$USERNAME/.ssh" || exit
        }
    else
        install -v -d -m 0700 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME/.ssh"
        install -v -m 0600 -o "$USERNAME" -g "$USER_GROUP" /dev/null "$USER_HOME/.ssh/authorized_keys"
        grep -E "$S$USERNAME\$" <<<"$ADMIN_USER_KEYS" >>"$USER_HOME/.ssh/authorized_keys" || :
    fi
    install -v -m 0440 /dev/null "/etc/sudoers.d/nopasswd-$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/nopasswd-$USERNAME"
done

lk_console_message "Disabling root password"
passwd -l root

# TODO: configure chroot jail
lk_console_message "Disabling clear text passwords when authenticating with SSH"
MATCH_MANY=Y edit_file "/etc/ssh/sshd_config" \
    "^#?(PasswordAuthentication${FIRST_ADMIN+|PermitRootLogin})\b.*\$" \
    "\1 no"

systemctl restart sshd.service
FIRST_ADMIN="${FIRST_ADMIN:-root}"

lk_console_message "Configuring sudoers"
install -v -m 0440 /dev/null "/etc/sudoers.d/${PATH_PREFIX}defaults"
cat <<EOF >"/etc/sudoers.d/${PATH_PREFIX}defaults"
Defaults !mail_no_user
Defaults !mail_badpass
Defaults env_keep += "LK_*"
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$LK_BASE/bin"
EOF
lk_console_file "/etc/sudoers.d/${PATH_PREFIX}defaults"

lk_console_message "Upgrading pre-installed packages"
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -q update
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq dist-upgrade

debconf-set-selections <<EOF
iptables-persistent	iptables-persistent/autosave_v4	boolean	false
iptables-persistent	iptables-persistent/autosave_v6	boolean	false
postfix	postfix/main_mailer_type	select	Internet Site
postfix	postfix/mailname	string	$NODE_FQDN
postfix	postfix/relayhost	string	$SMTP_RELAY
postfix	postfix/root_address	string	$ADMIN_EMAIL
EOF

# bare necessities
PACKAGES=(
    #
    git

    #
    atop
    ntp

    #
    apt-utils
    bash-completion
    byobu
    coreutils
    cron
    curl
    dnsutils
    git
    htop
    info
    iptables
    iptables-persistent
    iputils-ping
    iputils-tracepath
    jq
    less
    logrotate
    lsof
    man-db
    manpages
    nano
    netcat-openbsd
    psmisc
    pv
    rsync
    tcpdump
    telnet
    time
    tzdata
    vim
    wget

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
if [ "$REJECT_OUTPUT" != "N" ]; then
    APT_SOURCE_HOSTS=($(grep -Eo "^[^#]+${S}https?://[^/[:space:]]+" "/etc/apt/sources.list" |
        sed -E 's/^.*:\/\///' | sort | uniq)) || lk_die "no active package sources in /etc/apt/sources.list"
    if [[ ",$NODE_SERVICES," =~ .*,wp-cli,.* ]]; then
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
${ACCEPT_OUTPUT_HOSTS:+    ${ACCEPT_OUTPUT_HOSTS//,/$'\n'    }
})"
    . /dev/stdin <<<"$ACCEPT_OUTPUT_HOSTS_SH"
    if [[ " ${ACCEPT_OUTPUT_HOSTS[*]} " =~ .*" api.github.com ".* ]]; then
        lk_keep_trying eval "GITHUB_META=\"\$(curl --fail \"https://api.github.com/meta\")\""
        GITHUB_IPS=($(jq -r ".web[]" <<<"$GITHUB_META"))
    fi
    OUTPUT_ALLOW=(
        "${APT_SOURCE_HOSTS[@]}"
        "${ACCEPT_OUTPUT_HOSTS[@]}"
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
    lk_keep_trying eval "IPV4_IPS=\"\$(dig +short ${OUTPUT_ALLOW[*]/%/ A})\""
    lk_keep_trying eval "IPV6_IPS=\"\$(dig +short ${OUTPUT_ALLOW[*]/%/ AAAA})\""
    OUTPUT_ALLOW_IPV4+=($(echo "$IPV4_IPS" | sed -E '/\.$/d' | sort | uniq))
    OUTPUT_ALLOW_IPV6+=($(echo "$IPV6_IPS" | sed -E '/\.$/d' | sort | uniq))
fi
P="${PATH_PREFIX_ALPHA}_"
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
-A ${P}check -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ${P}check -m conntrack --ctstate INVALID -j DROP
-A ${P}check -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j REJECT --reject-with tcp-reset
-A ${P}check -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
-A ${P}input -p tcp -m tcp --dport 22 -j ${P}trusted
-A ${P}reject -p udp -m udp -j REJECT --reject-with icmp-port-unreachable
-A ${P}reject -p tcp -m tcp -j REJECT --reject-with tcp-reset
-A ${P}reject -j REJECT --reject-with icmp-proto-unreachable
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
-A OUTPUT -p udp -m udp --dport 67 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
-A OUTPUT -p udp -m udp --dport 123 -j ACCEPT
-A OUTPUT -j ${P}output
-A OUTPUT -m limit --limit 12/min -j LOG --log-prefix "outgoing packet blocked: "
-A OUTPUT -j ${P}reject
-A ${P}check -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ${P}check -m conntrack --ctstate INVALID -j DROP
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
EOF
if [ "$REJECT_OUTPUT" = "N" ]; then
    iptables -A "${P}output" -j ACCEPT
else
    for IPV4 in "${OUTPUT_ALLOW_IPV4[@]}"; do
        command iptables -A "${P}output" -d "$IPV4" -j ACCEPT
    done
    for IPV6 in "${OUTPUT_ALLOW_IPV6[@]}"; do
        command ip6tables -A "${P}output" -d "$IPV6" -j ACCEPT
    done
fi
if [ "$SSH_TRUSTED_ONLY" = "N" ] || [ -z "$TRUSTED_IP_ADDRESSES" ]; then
    iptables -A "${P}trusted" -j ACCEPT
else
    for IP in ${TRUSTED_IP_ADDRESSES[*]//,/ }; do
        if is_ipv4 "$IP"; then
            command iptables -A "${P}trusted" -s "$IP" -j ACCEPT
        elif is_ipv6 "$IP"; then
            command ip6tables -A "${P}trusted" -s "$IP" -j ACCEPT
        fi
    done
fi

lk_console_message "Configuring logrotate"
edit_file "/etc/logrotate.conf" "^#?su( .*)?\$" "su root adm" "su root adm"

lk_console_message "Setting system timezone to '$NODE_TIMEZONE'"
timedatectl set-timezone "$NODE_TIMEZONE"

lk_console_message "Configuring apt-listchanges"
lk_keep_original "/etc/apt/listchanges.conf"
cat <<EOF >"/etc/apt/listchanges.conf"
[apt]
frontend=pager
which=both
email_address=root
email_format=html
confirm=false
headers=true
reverse=false
save_seen=/var/lib/apt/listchanges.db
EOF
lk_console_file "/etc/apt/listchanges.conf"

FILE="/boot/config-$(uname -r)"
if [ -f "$FILE" ] && ! grep -Fxq "CONFIG_BSD_PROCESS_ACCT=y" "$FILE"; then
    lk_console_message "Disabling atopacct.service (process accounting not available)"
    systemctl disable atopacct.service
fi

install -v -d -m 2775 -o "$FIRST_ADMIN" -g "adm" "$LK_BASE"
if [ -z "$(ls -A "$LK_BASE")" ]; then
    lk_console_message "Cloning 'https://github.com/lkrms/lk-platform.git' to '$LK_BASE'"
    lk_keep_trying sudo -Hu "$FIRST_ADMIN" \
        git clone -b "${LK_PLATFORM_BRANCH:-master}" \
        "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
    sudo -Hu "$FIRST_ADMIN" bash -c "\
cd \"\$1\" &&
    git config core.sharedRepository 0664 &&
    git config merge.ff only &&
    git config pull.ff only" bash "$LK_BASE"
fi
install -v -d -m 2775 -o "$FIRST_ADMIN" -g "adm" "$LK_BASE/etc"
install -v -m 0664 -o "$FIRST_ADMIN" -g "adm" /dev/null "$LK_BASE/etc/packages.conf"
printf '%s=(\n%s\n)\n' \
    "IMAGE_BASE_PACKAGES" "$(
        printf '    %q\n' "${IMAGE_BASE_PACKAGES[@]}"
    )" >"$LK_BASE/etc/packages.conf"
install -v -m 0660 -o "$FIRST_ADMIN" -g "adm" /dev/null "$LK_BASE/etc/firewall.conf"
[ "$REJECT_OUTPUT" = "N" ] ||
    echo "\
$ACCEPT_OUTPUT_HOSTS_SH
$(printf '%s=%q\n' \
        "ACCEPT_OUTPUT_CHAIN" "${P}output")" >"$LK_BASE/etc/firewall.conf"
printf '%s=%q\n' \
    "LK_BASE" "$LK_BASE" \
    "LK_PATH_PREFIX" "$PATH_PREFIX" \
    "LK_PATH_PREFIX_ALPHA" "$PATH_PREFIX_ALPHA" \
    "LK_NODE_HOSTNAME" "$NODE_HOSTNAME" \
    "LK_NODE_FQDN" "$NODE_FQDN" \
    "LK_NODE_TIMEZONE" "$NODE_TIMEZONE" \
    "LK_NODE_SERVICES" "$NODE_SERVICES" \
    "LK_NODE_PACKAGES" "$NODE_PACKAGES" \
    "LK_ADMIN_EMAIL" "$ADMIN_EMAIL" \
    "LK_TRUSTED_IP_ADDRESSES" "$TRUSTED_IP_ADDRESSES" \
    "LK_SSH_TRUSTED_ONLY" "$SSH_TRUSTED_ONLY" \
    "LK_REJECT_OUTPUT" "$REJECT_OUTPUT" \
    "LK_ACCEPT_OUTPUT_HOSTS" "$ACCEPT_OUTPUT_HOSTS" \
    "LK_INNODB_BUFFER_SIZE" "$INNODB_BUFFER_SIZE" \
    "LK_OPCACHE_MEMORY_CONSUMPTION" "$OPCACHE_MEMORY_CONSUMPTION" \
    "LK_PHP_SETTINGS" "$PHP_SETTINGS" \
    "LK_PHP_ADMIN_SETTINGS" "$PHP_ADMIN_SETTINGS" \
    "LK_MEMCACHED_MEMORY_LIMIT" "$MEMCACHED_MEMORY_LIMIT" \
    "LK_SMTP_RELAY" "$SMTP_RELAY" \
    "LK_EMAIL_BLACKHOLE" "$EMAIL_BLACKHOLE" \
    "LK_AUTO_REBOOT" "$AUTO_REBOOT" \
    "LK_AUTO_REBOOT_TIME" "$AUTO_REBOOT_TIME" \
    "LK_SCRIPT_DEBUG" "$SCRIPT_DEBUG" \
    "LK_PLATFORM_BRANCH" "$LK_PLATFORM_BRANCH" \
    >"/etc/default/lk-platform"
"$LK_BASE/bin/lk-platform-install.sh" --no-log

# TODO: verify downloads
lk_console_message "Installing pip, ps_mem, Glances, awscli"
lk_keep_trying curl --fail --output /root/get-pip.py "https://bootstrap.pypa.io/get-pip.py"
python3 /root/get-pip.py
lk_keep_trying pip install ps_mem glances awscli

lk_console_message "Configuring Glances"
install -v -d -m 0755 "/etc/glances"
cat <<EOF >"/etc/glances/glances.conf"
# Created by ${0##*/} at $(lk_date_log)

[global]
check_update=false

[ip]
disable=true
EOF

lk_console_message "Creating virtual host base directory at /srv/www"
install -v -d -m 0751 -g "adm" "/srv/www"

PACKAGES=(
    postfix
    certbot
)
case ",$NODE_SERVICES," in
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

PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | sort | uniq))
[ "${#EXCLUDE_PACKAGES[@]}" -eq 0 ] ||
    PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | grep -Fxv "$(printf '%s\n' "${EXCLUDE_PACKAGES[@]}")"))

if [ "${#REPOS[@]}" -gt 0 ]; then
    lk_console_item "Adding APT repositories:" "$(printf '%s\n' "${REPOS[@]}")"
    for REPO in "${REPOS[@]}"; do
        lk_keep_trying add-apt-repository "${ADD_APT_REPOSITORY_ARGS[@]}" "$REPO"
    done
fi

lk_console_item "Installing APT packages:" "${PACKAGES[*]}"
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -q update
# new repos may include updates for pre-installed packages
[ "${#REPOS[@]}" -eq 0 ] || lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq upgrade
lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq install "${PACKAGES[@]}"

if [ -n "$HOST_DOMAIN" ]; then
    COPY_SKEL=0
    PHP_FPM_POOL_USER="www-data"
    id "$HOST_ACCOUNT" >/dev/null 2>&1 || {
        lk_console_message "Creating user account '$HOST_ACCOUNT'"
        useradd --no-create-home --home-dir "/srv/www/$HOST_ACCOUNT" --shell "/bin/bash" "$HOST_ACCOUNT"
        COPY_SKEL=1
        PHP_FPM_POOL_USER="$HOST_ACCOUNT"
        APACHE_MODS=(
            qos
            unique_id # used by "qos"
        )
    }
    HOST_ACCOUNT_GROUP="$(id -gn "$HOST_ACCOUNT")"
    install -v -d -m 0750 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT"
    install -v -d -m 0750 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT/public_html"
    install -v -d -m 0750 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT/ssl"
    install -v -d -m 0750 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT/.cache"
    install -v -d -m 2750 -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT/log"
    [ "$COPY_SKEL" -eq 0 ] || {
        sudo -Hu "$HOST_ACCOUNT" cp -nRTv "/etc/skel.$PATH_PREFIX_ALPHA" "/srv/www/$HOST_ACCOUNT" &&
            chmod -Rc -077 "/srv/www/$HOST_ACCOUNT/.ssh" || exit
    }
    ! lk_dpkg_installed apache2 || {
        lk_console_message "Adding user 'www-data' to group '$HOST_ACCOUNT_GROUP'"
        usermod --append --groups "$HOST_ACCOUNT_GROUP" "www-data"
    }
fi

if [ -n "$NODE_PACKAGES" ]; then
    lk_console_message "Installing additional packages"
    lk_keep_trying apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq install ${NODE_PACKAGES//,/ }
fi

if lk_dpkg_installed fail2ban; then
    # TODO: configure jails other than sshd
    lk_console_message "Configuring Fail2Ban"
    FILE="/etc/fail2ban/jail.conf"
    EDIT_FILE_LOG=N edit_file "$FILE" \
        "^#?backend$S*=($S*(pyinotify|gamin|polling|systemd|auto))?($S*; .*)?\$" \
        "backend = systemd\3"
    [ -z "$TRUSTED_IP_ADDRESSES" ] ||
        EDIT_FILE_LOG=N edit_file "$FILE" \
            "^#?ignoreip$S*=($S*[^#]+)?($S*; .*)?\$" \
            "ignoreip = 127.0.0.1\\/8 ::1 ${TRUSTED_IP_ADDRESSES//\//\\\/}\2"
    lk_console_file "$FILE"
fi

if lk_dpkg_installed postfix; then
    lk_console_message "Binding Postfix to the loopback interface"
    postconf -e "inet_interfaces = loopback-only"
    if [ -n "$EMAIL_BLACKHOLE" ]; then
        lk_console_message "Configuring Postfix to map all recipient addresses to '$EMAIL_BLACKHOLE'"
        postconf -e "recipient_canonical_maps = static:blackhole"
        cat <<EOF >>"/etc/aliases"

# Added by ${0##*/} at $(lk_date_log)
blackhole:	$EMAIL_BLACKHOLE
EOF
        newaliases
    fi
    lk_console_file "/etc/postfix/main.cf"
    lk_console_file "/etc/aliases"
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
        rewrite
        socache_shmcb # dependency of "ssl"
        ssl

        #
        ${APACHE_MODS[@]+"${APACHE_MODS[@]}"}
    )
    APACHE_MODS_ENABLED="$(a2query -m | grep -Eo '^[^ ]+' | sort | uniq || :)"
    APACHE_DISABLE_MODS=($(comm -13 <(printf '%s\n' "${APACHE_MODS[@]}" | sort | uniq) <(echo "$APACHE_MODS_ENABLED")))
    APACHE_ENABLE_MODS=($(comm -23 <(printf '%s\n' "${APACHE_MODS[@]}" | sort | uniq) <(echo "$APACHE_MODS_ENABLED")))
    [ "${#APACHE_DISABLE_MODS[@]}" -eq 0 ] || {
        lk_console_item "Disabling Apache HTTPD modules:" "${APACHE_DISABLE_MODS[*]}"
        a2dismod --force "${APACHE_DISABLE_MODS[@]}"
    }
    [ "${#APACHE_ENABLE_MODS[@]}" -eq 0 ] || {
        lk_console_item "Enabling Apache HTTPD modules:" "${APACHE_ENABLE_MODS[*]}"
        a2enmod --force "${APACHE_ENABLE_MODS[@]}"
    }

    # TODO: make PHP-FPM setup conditional
    [ -e "/opt/opcache-gui" ] || {
        lk_console_message "Cloning 'https://github.com/lkrms/opcache-gui.git' to '/opt/opcache-gui'"
        install -v -d -m 2775 -o "$FIRST_ADMIN" -g "adm" "/opt/opcache-gui"
        lk_keep_trying sudo -Hu "$FIRST_ADMIN" \
            git clone "https://github.com/lkrms/opcache-gui.git" \
            "/opt/opcache-gui"
    }

    lk_console_message "Configuring Apache HTTPD to serve PHP-FPM virtual hosts"
    cat <<EOF >"/etc/apache2/sites-available/${PATH_PREFIX}default.conf"
<IfModule event.c>
    MaxRequestWorkers 300
    ThreadsPerChild 25
</IfModule>
<Macro RequireTrusted>
    Require local${TRUSTED_IP_ADDRESSES:+
    Require ip ${TRUSTED_IP_ADDRESSES//,/ }}
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
    ServerAdmin $ADMIN_EMAIL
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
    ServerAdmin $ADMIN_EMAIL
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
        RedirectMatch 404 .*/\.(git|svn|${PATH_PREFIX}settings)
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
    ln -s "../sites-available/${PATH_PREFIX}default.conf" "/etc/apache2/sites-enabled/000-${PATH_PREFIX}default.conf"
    lk_console_file "/etc/apache2/sites-available/${PATH_PREFIX}default.conf"

    lk_console_message "Disabling pre-installed PHP-FPM pools"
    lk_keep_original "/etc/php/$PHPVER/fpm/pool.d"
    rm -f "/etc/php/$PHPVER/fpm/pool.d"/*.conf

    if [ -n "$HOST_DOMAIN" ]; then
        lk_console_message "Adding site to Apache HTTPD: $HOST_DOMAIN"
        cat <<EOF >"/etc/apache2/sites-available/$HOST_ACCOUNT.conf"
<VirtualHost *:80>
    ServerName $HOST_DOMAIN
    ServerAlias www.$HOST_DOMAIN
    Use PhpFpmVirtualHost${PHPVER//./} $HOST_ACCOUNT
</VirtualHost>
<VirtualHost *:443>
    ServerName $HOST_DOMAIN
    ServerAlias www.$HOST_DOMAIN
    Use PhpFpmVirtualHostSsl${PHPVER//./} $HOST_ACCOUNT
    SSLEngine on
    SSLCertificateFile /srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.cert
    SSLCertificateKeyFile /srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.key
</VirtualHost>
# PhpFpmProxy${PHPVER//./} %sitename% %timeout%
#   %timeout% should correlate with \`request_terminate_timeout\`
#   in /etc/php/$PHPVER/fpm/pool.d/$HOST_ACCOUNT.conf
Use PhpFpmProxy${PHPVER//./} $HOST_ACCOUNT 300
EOF
        install -v -m 0640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/log/error.log"
        install -v -m 0640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/log/access.log"
        install -v -m 0640 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.cert"
        install -v -m 0640 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.key"

        lk_console_message "Creating a self-signed SSL certificate for '$HOST_DOMAIN'"
        openssl genrsa \
            -out "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.key" \
            2048
        openssl req -new \
            -key "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.key" \
            -subj "/C=AU/CN=$HOST_DOMAIN" \
            -addext "subjectAltName = DNS:www.$HOST_DOMAIN" \
            -out "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.csr"
        openssl x509 -req -days 365 \
            -in "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.csr" \
            -signkey "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.key" \
            -out "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.cert"
        rm -f "/srv/www/$HOST_ACCOUNT/ssl/$HOST_DOMAIN.csr"

        [ "$HOST_SITE_ENABLE" = "N" ] ||
            ln -s "../sites-available/$HOST_ACCOUNT.conf" "/etc/apache2/sites-enabled/$HOST_ACCOUNT.conf"
        lk_console_file "/etc/apache2/sites-available/$HOST_ACCOUNT.conf"

        lk_console_message "Configuring PHP-FPM umask for group-writable files"
        FILE="/etc/systemd/system/php$PHPVER-fpm.service.d/override.conf"
        install -v -d -m 0755 "$(dirname "$FILE")"
        cat <<EOF >"$FILE"
[Service]
UMask=0002
EOF
        systemctl daemon-reload
        lk_console_file "$FILE"

        lk_console_message "Adding pool to PHP-FPM: $HOST_ACCOUNT"
        cat <<EOF >"/etc/php/$PHPVER/fpm/pool.d/$HOST_ACCOUNT.conf"
; Values in /etc/apache2/sites-available/$HOST_ACCOUNT.conf and/or
; /etc/mysql/mariadb.conf.d/90-${PATH_PREFIX}defaults.cnf should be updated
; if \`request_terminate_timeout\` or \`pm.max_children\` are changed here
[$HOST_ACCOUNT]
user = $PHP_FPM_POOL_USER
listen = /run/php/php$PHPVER-fpm-\$pool.sock
listen.owner = www-data
listen.group = www-data
; ondemand can't handle sudden bursts: https://github.com/php/php-src/pull/1308
pm = static
; tune based on memory consumed per process under load
pm.max_children = 50
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
catch_workers_output = yes${OPCACHE_MEMORY_CONSUMPTION:+
; tune based on system resources
php_admin_value[opcache.memory_consumption] = $OPCACHE_MEMORY_CONSUMPTION}
php_admin_value[opcache.file_cache] = "/srv/www/\$pool/.cache/opcache"
php_admin_flag[opcache.validate_permission] = On
php_admin_value[error_log] = "/srv/www/\$pool/log/php$PHPVER-fpm.error.log"
php_admin_flag[log_errors] = On
php_flag[display_errors] = Off
php_flag[display_startup_errors] = Off
php_value[upload_max_filesize] = 24M
php_value[post_max_size] = 50M

; do not uncomment the following in production (also, install php-xdebug first)
;php_admin_flag[opcache.enable] = Off
;php_admin_flag[xdebug.remote_enable] = On
;php_admin_flag[xdebug.remote_autostart] = On
;php_admin_flag[xdebug.remote_connect_back] = On
;php_admin_value[xdebug.remote_log] = "/srv/www/\$pool/log/php$PHPVER-fpm.xdebug.log"
EOF
        install -v -m 0640 -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/log/php$PHPVER-fpm.access.log"
        install -v -m 0640 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/log/php$PHPVER-fpm.error.log"
        install -v -m 0640 -o "$PHP_FPM_POOL_USER" -g "$HOST_ACCOUNT_GROUP" /dev/null "/srv/www/$HOST_ACCOUNT/log/php$PHPVER-fpm.xdebug.log"
        install -v -d -m 0700 -o "$HOST_ACCOUNT" -g "$HOST_ACCOUNT_GROUP" "/srv/www/$HOST_ACCOUNT/.cache/opcache"
        lk_console_file "/etc/php/$PHPVER/fpm/pool.d/$HOST_ACCOUNT.conf"
    fi

    lk_console_message "Adding virtual host log files to logrotate.d"
    mv -v "/etc/logrotate.d/apache2" "/etc/logrotate.d/apache2.disabled"
    mv -v "/etc/logrotate.d/php$PHPVER-fpm" "/etc/logrotate.d/php$PHPVER-fpm.disabled"
    cat <<EOF >"/etc/logrotate.d/${PATH_PREFIX}log"
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
        ! invoke-rc.d apache2 status >/dev/null 2>&1 || invoke-rc.d apache2 reload >/dev/null 2>&1
    endscript
}
EOF

    lk_console_message "Adding iptables rules for Apache HTTPD"
    iptables -A "${P}input" -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A "${P}input" -p tcp -m tcp --dport 443 -j ACCEPT
fi

if lk_dpkg_installed mariadb-server; then
    FILE="/etc/mysql/mariadb.conf.d/90-${PATH_PREFIX}defaults.cnf"
    cat <<EOF >"$FILE"
[mysqld]
# must exceed the sum of pm.max_children across all PHP-FPM pools
max_connections = 301${INNODB_BUFFER_SIZE:+

innodb_buffer_pool_size = $INNODB_BUFFER_SIZE
innodb_buffer_pool_instances = $(((${INNODB_BUFFER_SIZE%M} - 1) / 1024 + 1))
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1}
EOF
    lk_console_file "$FILE"
    lk_console_message "Starting mysql.service (MariaDB)"
    systemctl start mysql.service
    if [ -n "$MYSQL_USERNAME" ]; then
        MYSQL_PASSWORD="${MYSQL_PASSWORD//\\/\\\\}"
        MYSQL_PASSWORD="${MYSQL_PASSWORD//\'/\\\'}"
        lk_console_message "Creating MySQL administrator '$MYSQL_USERNAME'"
        echo "\
GRANT ALL PRIVILEGES ON *.* \
TO '$MYSQL_USERNAME'@'localhost' \
IDENTIFIED BY '$MYSQL_PASSWORD' \
WITH GRANT OPTION" | mysql -uroot
    fi

    lk_console_message "Configuring MySQL account self-service"
    install -v -m 0440 /dev/null "/etc/sudoers.d/${PATH_PREFIX}mysql-self-service"
    cat <<EOF >"/etc/sudoers.d/${PATH_PREFIX}mysql-self-service"
ALL ALL=(root) NOPASSWD:$LK_BASE/bin/lk-mysql-grant.sh
EOF
    lk_console_file "/etc/sudoers.d/${PATH_PREFIX}mysql-self-service"

    # TODO: create $HOST_ACCOUNT database
fi

if lk_dpkg_installed memcached; then
    lk_console_message "Configuring Memcached"
    FILE="/etc/memcached.conf"
    edit_file "$FILE" \
        "^#?(-m$S+|--memory-limit(=|$S+))[0-9]+$S*\$" \
        "\1$MEMCACHED_MEMORY_LIMIT" \
        "-m $MEMCACHED_MEMORY_LIMIT"
fi

lk_console_message "Saving iptables rules"
iptables-save >"/etc/iptables/rules.v4"
ip6tables-save >"/etc/iptables/rules.v6"
lk_console_file "/etc/iptables/rules.v4"
lk_console_file "/etc/iptables/rules.v6"

lk_console_message "Running apt-get autoremove"
apt-get ${APT_GET_ARGS[@]+"${APT_GET_ARGS[@]}"} -yq autoremove

lk_console_message "Provisioning complete"
lk_console_detail "Running:" "shutdown --$SHUTDOWN_ACTION +$SHUTDOWN_DELAY"
shutdown --"$SHUTDOWN_ACTION" +"$SHUTDOWN_DELAY"

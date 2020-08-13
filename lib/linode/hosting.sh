#!/bin/bash
# shellcheck disable=SC1091,SC2001,SC2206,SC2207
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
# <UDF name="SSH_TRUSTED_ONLY" label="Block SSH access from untrusted IP addresses (ignored if no trusted IP addresses are specified)" oneof="Y,N" default="N" />
# <UDF name="REJECT_OUTPUT" label="Reject outgoing traffic by default" oneof="Y,N" default="N" />
# <UDF name="ACCEPT_OUTPUT_HOSTS" label="Accept outgoing traffic to hosts (comma-delimited)" example="192.168.128.0/17,ip-ranges.amazonaws.com" default="" />
# <UDF name="MYSQL_USERNAME" label="MySQL admin username" example="dbadmin" default="" />
# <UDF name="MYSQL_PASSWORD" label="MySQL password (admin user not created if blank)" default="" />
# <UDF name="INNODB_BUFFER_SIZE" label="InnoDB buffer size (~80% of RAM for MySQL-only servers)" oneof="128M,256M,512M,768M,1024M,1536M,2048M,2560M,3072M,4096M,5120M,6144M,7168M,8192M" default="256M" />
# <UDF name="OPCACHE_MEMORY_CONSUMPTION" label="PHP OPcache size" oneof="128,256,512,768,1024" default="256" />
# <UDF name="MEMCACHED_MEMORY_LIMIT" label="Memcached size" oneof="64,128,256,512,768,1024" default="256" />
# <UDF name="SMTP_RELAY" label="SMTP relay (system-wide)" example="[mail.clientname.com.au]:587" default="" />
# <UDF name="EMAIL_BLACKHOLE" label="Email black hole (system-wide, STAGING ONLY)" example="/dev/null" default="" />
# <UDF name="AUTO_REBOOT" label="Reboot automatically after unattended upgrades" oneof="Y,N" />
# <UDF name="AUTO_REBOOT_TIME" label="Preferred automatic reboot time" oneof="02:00,03:00,04:00,05:00,06:00,07:00,08:00,09:00,10:00,11:00,12:00,13:00,14:00,15:00,16:00,17:00,18:00,19:00,20:00,21:00,22:00,23:00,00:00,01:00,now" default="02:00" />
# <UDF name="PATH_PREFIX" label="Prefix for files installed by this script" default="lk-" />
# <UDF name="SCRIPT_DEBUG" label="Enable debugging" oneof="Y,N" default="N" />
# <UDF name="SHUTDOWN_ACTION" label="Reboot or power down after provisioning" oneof="reboot,poweroff" default="reboot" />
# <UDF name="SHUTDOWN_DELAY" label="Delay before shutdown/reboot after provisioning (in minutes)" default="0" />
# <UDF name="LK_PLATFORM_BRANCH" label="lk-platform tracking branch" oneof="master,develop" default="master" />

function is_installed() {
    local STATUS
    STATUS="$(dpkg-query --show --showformat '${db:Status-Status}' "$1" 2>/dev/null)" &&
        [ "$STATUS" = "installed" ]
}

function now() {
    date +'%Y-%m-%d %H:%M:%S %z'
}

function write_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(now)" "$LINE"
    done
}

function log() {
    local IFS=$'\n' LINE
    LINE="$*"
    echo "${LOG_PREFIX-==> }${LINE//$'\n'/$'\n  '}" >&3
}

function log_header() {
    LOG_PREFIX="====> " log "$@"
}

function die() {
    local EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -ne "0" ] || EXIT_STATUS="1"
    log_header "${0##*/}: $1" "${@:2}"
    exit "$EXIT_STATUS"
}

function keep_original() {
    [ ! -e "$1" ] ||
        cp -nav "$1" "$1.orig"
}

# edit_file FILE SEARCH_PATTERN REPLACE_PATTERN [ADD_TEXT]
function edit_file() {
    local SED_SCRIPT="0,/$2/{s/$2/$3/}" BEFORE AFTER
    [ -f "$1" ] || [ -n "${4:-}" ] || die "file not found: $1"
    [ "${MATCH_MANY:-N}" = "N" ] || SED_SCRIPT="s/$2/$3/"
    if grep -Eq -e "$2" "$1" 2>/dev/null; then
        keep_original "$1"
        BEFORE="$(cat "$1")"
        AFTER="$(sed -E "$SED_SCRIPT" "$1")"
        [ "$BEFORE" = "$AFTER" ] || {
            sed -Ei "$SED_SCRIPT" "$1"
        }
    elif [ -n "${4:-}" ]; then
        echo "$4" >>"$1"
    else
        die "no line matching $2 in $1"
    fi
    [ "${EDIT_FILE_LOG:-Y}" = "N" ] || log_file "$1"
}

function esc() {
    echo "$1" | sed -Ee 's/\\/\\\\/g' -e 's/[$`"]/\\&/g'
}

function log_file() {
    log "$1:" \
        "<<<<" \
        "$(
            if [ -f "$1.orig" ]; then
                ! diff "$1.orig" "$1" || echo "<unchanged>"
            else
                cat "$1"
            fi
        )" \
        ">>>>"
}

function nc() (
    exec 3<>"/dev/tcp/$1/$2"
    cat >&3
    cat <&3
    exec 3>&-
)

function keep_trying() {
    local ATTEMPT=1 MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}" WAIT=5 LAST_WAIT=3 NEW_WAIT EXIT_STATUS
    if ! "$@"; then
        while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
            log "Command failed:" "$*"
            log "Waiting $WAIT seconds"
            sleep "$WAIT"
            ((NEW_WAIT = WAIT + LAST_WAIT))
            LAST_WAIT="$WAIT"
            WAIT="$NEW_WAIT"
            log "Retrying (attempt $((++ATTEMPT))/$MAX_ATTEMPTS)"
            if "$@"; then
                return
            else
                EXIT_STATUS="$?"
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

function exit_trap() {
    local EXIT_STATUS="$?"
    # TODO: replace with an HTTP-based notification mechanism
    if [ -n "${CALL_HOME_MX:-}" ]; then
        if [ "$EXIT_STATUS" -eq "0" ]; then
            SUBJECT="$NODE_FQDN deployed successfully"
        else
            SUBJECT="$NODE_FQDN failed to deploy"
        fi
        nc "$CALL_HOME_MX" 25 <<EOF || true
HELO $NODE_FQDN
MAIL FROM:<root@$NODE_FQDN>
RCPT TO:<$ADMIN_EMAIL>
DATA
From: ${0##*/} <root@$NODE_FQDN>
To: $NODE_HOSTNAME admin <$ADMIN_EMAIL>
Date: $(date -R)
Subject: $SUBJECT

Hi

The host at $NODE_HOSTNAME ($NODE_FQDN) is now live.
${EMAIL_INFO:+
$EMAIL_INFO
}
Install log:

<<<$LOG_FILE
$(cat "$LOG_FILE" 2>&1 || :)
>>>

Full output: $NODE_HOSTNAME:$OUT_FILE

.
QUIT
EOF
    fi
}

set -euo pipefail
shopt -s nullglob

if [ "${SCRIPT_DEBUG:-N}" = "Y" ]; then
    set -x
fi

PATH_PREFIX="${PATH_PREFIX:-lk-}"
LOCK_FILE="/tmp/${PATH_PREFIX}install.lock"
LOG_FILE="/var/log/${PATH_PREFIX}install.log"
OUT_FILE="/var/log/${PATH_PREFIX}install.out"

install -v -m 0640 -g "adm" "/dev/null" "$LOG_FILE"
install -v -m 0640 -g "adm" "/dev/null" "$OUT_FILE"

trap 'exit_trap' EXIT

exec 9>"$LOCK_FILE"
flock -n 9 || die "unable to acquire a lock on $LOCK_FILE"

exec > >(tee >(write_log >>"$OUT_FILE")) 2>&1
exec 3> >(tee >(write_log >>"$LOG_FILE") >&1)

# TODO: more validation here
FIELD_ERRORS=()
PATH_PREFIX_ALPHA="$(sed 's/[^a-zA-Z0-9]//g' <<<"$PATH_PREFIX")"
[ -n "$PATH_PREFIX_ALPHA" ] || FIELD_ERRORS+=("PATH_PREFIX must contain at least one letter or number")
[ -n "${NODE_HOSTNAME:-}" ] || FIELD_ERRORS+=("NODE_HOSTNAME not set")
[ -n "${NODE_FQDN:-}" ] || FIELD_ERRORS+=("NODE_FQDN not set")
[ -n "${ADMIN_EMAIL:-}" ] || FIELD_ERRORS+=("ADMIN_EMAIL not set")
[ -n "${AUTO_REBOOT:-}" ] || FIELD_ERRORS+=("AUTO_REBOOT not set")
[ "${#FIELD_ERRORS[@]}" -eq "0" ] ||
    die "invalid field values" \
        "${FIELD_ERRORS[@]}"

NODE_TIMEZONE="${NODE_TIMEZONE:-Australia/Sydney}"
NODE_SERVICES="${NODE_SERVICES:-}"
NODE_PACKAGES="${NODE_PACKAGES:-}"
HOST_DOMAIN="${HOST_DOMAIN:-}"
HOST_DOMAIN="${HOST_DOMAIN#www.}"
HOST_ACCOUNT="${HOST_ACCOUNT:-${HOST_DOMAIN%%.*}}"
HOST_SITE_ENABLE="${HOST_SITE_ENABLE:-N}"
ADMIN_USERS="${ADMIN_USERS:-linac}"
TRUSTED_IP_ADDRESSES="${TRUSTED_IP_ADDRESSES:-}"
SSH_TRUSTED_ONLY="${SSH_TRUSTED_ONLY:-N}"
REJECT_OUTPUT="${REJECT_OUTPUT:-N}"
ACCEPT_OUTPUT_HOSTS="${ACCEPT_OUTPUT_HOSTS:-}"
MYSQL_USERNAME="${MYSQL_USERNAME:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
INNODB_BUFFER_SIZE="${INNODB_BUFFER_SIZE:-256M}"
OPCACHE_MEMORY_CONSUMPTION="${OPCACHE_MEMORY_CONSUMPTION:-256}"
MEMCACHED_MEMORY_LIMIT="${MEMCACHED_MEMORY_LIMIT:-256}"
SMTP_RELAY="${SMTP_RELAY:-}"
EMAIL_BLACKHOLE="${EMAIL_BLACKHOLE:-}"
AUTO_REBOOT_TIME="${AUTO_REBOOT_TIME:-02:00}"
SHUTDOWN_ACTION="${SHUTDOWN_ACTION:-reboot}"
SHUTDOWN_DELAY="${SHUTDOWN_DELAY:-0}"

S="[[:space:]]"

[ -s "/root/.ssh/authorized_keys" ] ||
    die "at least one SSH key must be added to hosts deployed with this script"

ADMIN_USER_KEYS="$([ -z "$ADMIN_USERS" ] || grep -E "$S(${ADMIN_USERS//,/|})\$" "/root/.ssh/authorized_keys" || :)"
HOST_KEYS="$([ -z "$ADMIN_USERS" ] && cat "/root/.ssh/authorized_keys" || grep -Ev "$S(${ADMIN_USERS//,/|})\$" "/root/.ssh/authorized_keys" || :)"

log_header "${0##*/}: preparing system"
log "Environment:" \
    "$(printenv | grep -v '^LS_COLORS=' | sort)"

# don't propagate field values to the environment of other commands
export -n \
    HOST_DOMAIN HOST_ACCOUNT HOST_SITE_ENABLE \
    ADMIN_USERS TRUSTED_IP_ADDRESSES SSH_TRUSTED_ONLY \
    MYSQL_USERNAME MYSQL_PASSWORD \
    INNODB_BUFFER_SIZE OPCACHE_MEMORY_CONSUMPTION \
    SMTP_RELAY EMAIL_BLACKHOLE \
    AUTO_REBOOT AUTO_REBOOT_TIME \
    SCRIPT_DEBUG SHUTDOWN_ACTION SHUTDOWN_DELAY

IMAGE_BASE_PACKAGES=($(apt-mark showmanual))
log "Pre-installed packages:" \
    "${IMAGE_BASE_PACKAGES[@]}"

. /etc/lsb-release

EXCLUDE_PACKAGES=()
case "$DISTRIB_RELEASE" in
*)
    # "-n" disables add-apt-repository's automatic package cache update
    ADD_APT_REPOSITORY_ARGS=(-yn)
    CERTBOT_REPO="ppa:certbot/certbot"
    PHPVER=7.2
    ;;&
16.04)
    # in 16.04, the package cache isn't automatically updated by default
    ADD_APT_REPOSITORY_ARGS=(-y)
    PHPVER=7.0
    ;;
20.04)
    unset CERTBOT_REPO
    PHPVER=7.4
    EXCLUDE_PACKAGES+=(php-gettext)
    ;;
esac

export LK_BASE="/opt/${PATH_PREFIX}platform" \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    PIP_NO_INPUT=1

IPV4_ADDRESS="$(
    for REGEX in \
        '^(127|10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.' \
        '^127\.'; do
        ip a |
            awk '/inet / { print $2 }' |
            grep -Ev "$REGEX" |
            head -n1 |
            sed -E 's/\/[0-9]+$//' && break
    done
)" || IPV4_ADDRESS=
log "IPv4 address: ${IPV4_ADDRESS:-<none>}"

IPV6_ADDRESS="$(
    for REGEX in \
        '^(::1/128|fe80::|f[cd])' \
        '^::1/128'; do
        ip a |
            awk '/inet6 / { print $2 }' |
            grep -Eiv "$REGEX" |
            head -n1 |
            sed -E 's/\/[0-9]+$//' && break
    done
)" || IPV6_ADDRESS=
log "IPv6 address: ${IPV6_ADDRESS:-<none>}"

log "Enabling persistent journald storage"
edit_file "/etc/systemd/journald.conf" "^#?Storage=.*\$" "Storage=persistent"
systemctl restart systemd-journald.service

log "Setting system hostname to '$NODE_HOSTNAME'"
hostnamectl set-hostname "$NODE_HOSTNAME"

FILE="/etc/hosts"
# Apache won't resolve a name-based <VirtualHost> correctly if ServerName
# resolves to a loopback address, so if the host's FQDN is also the initial
# hosting domain, don't associate it with 127.0.1.1
[ "${NODE_FQDN#www.}" = "$HOST_DOMAIN" ] || HOSTS_NODE_FQDN="$NODE_FQDN"
log "Adding entries to $FILE"
cat <<EOF >>"$FILE"

# Added by ${0##*/} at $(now)
127.0.1.1 ${HOSTS_NODE_FQDN:+$HOSTS_NODE_FQDN }$NODE_HOSTNAME${HOSTS_NODE_FQDN:+${IPV4_ADDRESS:+
$IPV4_ADDRESS $NODE_FQDN}${IPV6_ADDRESS:+
$IPV6_ADDRESS $NODE_FQDN}}
EOF
log_file "$FILE"

log "Configuring unattended APT upgrades and disabling optional dependencies"
APT_CONF_FILE="/etc/apt/apt.conf.d/90${PATH_PREFIX}defaults"
[ "$AUTO_REBOOT" = "Y" ] || REBOOT_COMMENT="//"
cat <<EOF >"$APT_CONF_FILE"
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
${REBOOT_COMMENT:-}Unattended-Upgrade::Automatic-Reboot "true";
${REBOOT_COMMENT:-}Unattended-Upgrade::Automatic-Reboot-Time "$AUTO_REBOOT_TIME";
EOF
log_file "$APT_CONF_FILE"

# see `man invoke-rc.d` for more information
log "Disabling automatic \"systemctl start\" when new services are installed"
cat <<EOF >"/usr/sbin/policy-rc.d"
#!/bin/bash
# Created by ${0##*/} at $(now)
$(declare -f now)
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
printf '%s %s\n%s\n' "\$(now)" "\${LOG[0]}" "\$(
    LOG=("\${LOG[@]:1}")
    printf '  %s\n' "\${LOG[@]//\$'\n'/\$'\n' }"
)" >>"/var/log/${PATH_PREFIX}policy-rc.log"
exit "\$EXIT_STATUS"
EOF
chmod a+x "/usr/sbin/policy-rc.d"
log_file "/usr/sbin/policy-rc.d"

REMOVE_PACKAGES=(
    mlocate # waste of CPU
    rsyslog # waste of space (assuming journald storage is persistent)

    # Canonical cruft
    landscape-common
    snapd
    ubuntu-advantage-tools
)
for i in "${!REMOVE_PACKAGES[@]}"; do
    is_installed "${REMOVE_PACKAGES[$i]}" ||
        unset "REMOVE_PACKAGES[$i]"
done
if [ "${#REMOVE_PACKAGES[@]}" -gt "0" ]; then
    log "Removing APT packages:" "${REMOVE_PACKAGES[*]}"
    apt-get -yq purge "${REMOVE_PACKAGES[@]}"
fi

log "Disabling unnecessary motd scripts"
for FILE in 10-help-text 50-motd-news 91-release-upgrade 98-fsck-at-reboot; do
    [ ! -x "/etc/update-motd.d/$FILE" ] || chmod -c a-x "/etc/update-motd.d/$FILE"
done

log "Configuring kernel parameters"
FILE="/etc/sysctl.d/90-${PATH_PREFIX}defaults.conf"
cat <<EOF >"$FILE"
# Avoid paging and swapping if at all possible
vm.swappiness = 1

# Apache and PHP-FPM both default to listen.backlog = 511, but the
# default value of SOMAXCONN is only 128
net.core.somaxconn = 1024
EOF
log_file "$FILE"
sysctl --system

log "Sourcing $LK_BASE/lib/bash/rc.sh in ~/.bashrc for all users"
RC_ESCAPED="$(printf '%q' "$LK_BASE/lib/bash/rc.sh")"
BASH_SKEL="
# Added by ${0##*/} at $(now)
if [ -f $RC_ESCAPED ]; then
    . $RC_ESCAPED
fi"
echo "$BASH_SKEL" >>"/etc/skel/.bashrc"
if [ -f "/root/.bashrc" ]; then
    echo "$BASH_SKEL" >>"/root/.bashrc"
else
    cp "/etc/skel/.bashrc" "/root/.bashrc"
fi

log "Sourcing Byobu in ~/.profile by default"
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
[ ! -e "$DIR" ] || die "already exists: $DIR"
log "Creating $DIR (for hosting accounts)"
cp -av "/etc/skel" "$DIR"
install -v -d -m 0755 "$DIR/.ssh"
install -v -m 0644 /dev/null "$DIR/.ssh/authorized_keys"
[ -z "$HOST_KEYS" ] || echo "$HOST_KEYS" >>"$DIR/.ssh/authorized_keys"

for USERNAME in ${ADMIN_USERS//,/ }; do
    FIRST_ADMIN="${FIRST_ADMIN:-$USERNAME}"
    log "Creating superuser '$USERNAME'"
    # HOME_DIR may already exist, e.g. if filesystems have been mounted in it
    useradd --no-create-home --groups "adm,sudo" --shell "/bin/bash" "$USERNAME"
    USER_GROUP="$(id -gn "$USERNAME")"
    USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
    install -v -d -m 0750 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME"
    sudo -Hu "$USERNAME" cp -nRTv "/etc/skel" "$USER_HOME"
    if [ -z "$ADMIN_USER_KEYS" ]; then
        [ ! -e "/root/.ssh" ] || {
            log "Moving /root/.ssh to /home/$USERNAME/.ssh"
            mv "/root/.ssh" "/home/$USERNAME/" &&
                chown -R "$USERNAME": "/home/$USERNAME/.ssh" || exit
        }
    else
        install -v -d -m 0700 -o "$USERNAME" -g "$USER_GROUP" "$USER_HOME/.ssh"
        install -v -m 0600 -o "$USERNAME" -g "$USER_GROUP" /dev/null "$USER_HOME/.ssh/authorized_keys"
        grep -E "$S$USERNAME\$" <<<"$ADMIN_USER_KEYS" >>"$USER_HOME/.ssh/authorized_keys" || :
    fi
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/nopasswd-$USERNAME"
done

log "Disabling root password"
passwd -l root

# TODO: configure chroot jail
log "Disabling clear text passwords when authenticating with SSH"
MATCH_MANY=Y edit_file "/etc/ssh/sshd_config" \
    "^#?(PasswordAuthentication${FIRST_ADMIN+|PermitRootLogin})\b.*\$" \
    "\1 no"

systemctl restart sshd.service
FIRST_ADMIN="${FIRST_ADMIN:-root}"

log "Configuring sudoers"
cat <<EOF >"/etc/sudoers.d/${PATH_PREFIX}defaults"
Defaults !mail_no_user
Defaults !mail_badpass
Defaults env_keep += "LK_*"
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$LK_BASE/bin"
EOF
log_file "/etc/sudoers.d/${PATH_PREFIX}defaults"

log "Upgrading pre-installed packages"
keep_trying apt-get -q update
keep_trying apt-get -yq dist-upgrade

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
    unattended-upgrades

    #
    build-essential
    python3
    python3-dev
)

# if service installations have been requested, add-apt-repository
# will need to be available
[ -z "$NODE_SERVICES" ] ||
    PACKAGES+=(software-properties-common)

log "Installing APT packages:" "${PACKAGES[*]}"
keep_trying apt-get -yq install "${PACKAGES[@]}"

log "Configuring iptables"
if [ "$REJECT_OUTPUT" != "N" ]; then
    APT_SOURCE_HOSTS=($(grep -Eo "^[^#]+${S}https?://[^/[:space:]]+" "/etc/apt/sources.list" |
        sed -E 's/^.*:\/\///' | sort | uniq)) || die "no active package sources in /etc/apt/sources.list"
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
        keep_trying eval "GITHUB_META=\"\$(curl \"https://api.github.com/meta\")\""
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
    keep_trying eval "IPV4_IPS=\"\$(dig +short ${OUTPUT_ALLOW[*]/%/ A})\""
    keep_trying eval "IPV6_IPS=\"\$(dig +short ${OUTPUT_ALLOW[*]/%/ AAAA})\""
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

log "Configuring logrotate"
edit_file "/etc/logrotate.conf" "^#?su( .*)?\$" "su root adm" "su root adm"

log "Setting system timezone to '$NODE_TIMEZONE'"
timedatectl set-timezone "$NODE_TIMEZONE"

log "Configuring apt-listchanges"
keep_original "/etc/apt/listchanges.conf"
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
log_file "/etc/apt/listchanges.conf"

FILE="/boot/config-$(uname -r)"
if [ -f "$FILE" ] && ! grep -Fxq "CONFIG_BSD_PROCESS_ACCT=y" "$FILE"; then
    log "Disabling atopacct.service (process accounting not available)"
    systemctl disable atopacct.service
fi

install -v -d -m 2775 -o "$FIRST_ADMIN" -g "adm" "$LK_BASE"
if [ -z "$(ls -A "$LK_BASE")" ]; then
    log "Cloning 'https://github.com/lkrms/lk-platform.git' to '$LK_BASE'"
    keep_trying sudo -Hu "$FIRST_ADMIN" \
        git clone -b "${LK_PLATFORM_BRANCH:-master}" \
        "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
    sudo -Hu "$FIRST_ADMIN" bash -c "\
cd \"$(esc "$LK_BASE")\" &&
    git config core.sharedRepository 0664 &&
    git config merge.ff only &&
    git config pull.ff only"
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
    "LK_DEFAULT_OPCACHE_MEMORY_CONSUMPTION" "$OPCACHE_MEMORY_CONSUMPTION" \
    "LK_MEMCACHED_MEMORY_LIMIT" "$MEMCACHED_MEMORY_LIMIT" \
    "LK_SMTP_RELAY" "$SMTP_RELAY" \
    "LK_EMAIL_BLACKHOLE" "$EMAIL_BLACKHOLE" \
    "LK_AUTO_REBOOT" "$AUTO_REBOOT" \
    "LK_AUTO_REBOOT_TIME" "$AUTO_REBOOT_TIME" \
    "LK_PLATFORM_BRANCH" "$LK_PLATFORM_BRANCH" \
    >"/etc/default/lk-platform"
"$LK_BASE/bin/lk-platform-install.sh"

# TODO: verify downloads
log "Installing pip, ps_mem, Glances, awscli"
keep_trying curl --output /root/get-pip.py "https://bootstrap.pypa.io/get-pip.py"
python3 /root/get-pip.py
keep_trying pip install ps_mem glances awscli

log "Configuring Glances"
install -v -d -m 0755 "/etc/glances"
cat <<EOF >"/etc/glances/glances.conf"
# Created by ${0##*/} at $(now)

[global]
check_update=false

[ip]
disable=true
EOF

log "Creating virtual host base directory at /srv/www"
install -v -d -m 0751 -g "adm" "/srv/www"

case ",$NODE_SERVICES," in
,,) ;;

*)
    REPOS=(
        ${CERTBOT_REPO+"$CERTBOT_REPO"}
    )
    grep -Eq \
        "^deb$S+http://\w+(\.\w+)*(:[0-9]+)?(/ubuntu)?/?$S+(\w+$S+)*$DISTRIB_CODENAME$S+(\w+$S+)*universe($S|\$)" \
        /etc/apt/sources.list ||
        REPOS+=(universe)

    PACKAGES=(
        #
        postfix
        certbot

        #
        git
    )
    ;;&

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
    log "Downloading wp-cli to /usr/local/bin"
    keep_trying curl --output "/usr/local/bin/wp" "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    chmod a+x "/usr/local/bin/wp"
    ;;&

*)
    PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | sort | uniq))
    [ "${#EXCLUDE_PACKAGES[@]}" -eq "0" ] ||
        PACKAGES=($(printf '%s\n' "${PACKAGES[@]}" | grep -Fxv "$(printf '%s\n' "${EXCLUDE_PACKAGES[@]}")"))

    if [ "${#REPOS[@]}" -gt "0" ]; then
        log "Adding APT repositories:" "${REPOS[@]}"
        for REPO in "${REPOS[@]}"; do
            keep_trying add-apt-repository "${ADD_APT_REPOSITORY_ARGS[@]}" "$REPO"
        done
    fi

    log "Installing APT packages:" "${PACKAGES[*]}"
    keep_trying apt-get -q update
    # new repos may include updates for pre-installed packages
    [ "${#REPOS[@]}" -eq "0" ] || keep_trying apt-get -yq upgrade
    keep_trying apt-get -yq install "${PACKAGES[@]}"

    if [ -n "$HOST_DOMAIN" ]; then
        COPY_SKEL=0
        PHP_FPM_POOL_USER="www-data"
        id "$HOST_ACCOUNT" >/dev/null 2>&1 || {
            log "Creating user account '$HOST_ACCOUNT'"
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
        [ "$COPY_SKEL" -eq "0" ] || {
            sudo -Hu "$HOST_ACCOUNT" cp -nRTv "/etc/skel.$PATH_PREFIX_ALPHA" "/srv/www/$HOST_ACCOUNT" &&
                chmod -Rc -077 "/srv/www/$HOST_ACCOUNT/.ssh" || exit
        }
        ! is_installed apache2 || {
            log "Adding user 'www-data' to group '$HOST_ACCOUNT_GROUP'"
            usermod --append --groups "$HOST_ACCOUNT_GROUP" "www-data"
        }
    fi
    ;;

esac

if [ -n "$NODE_PACKAGES" ]; then
    log "Installing additional packages"
    keep_trying apt-get -yq install ${NODE_PACKAGES//,/ }
fi

if is_installed fail2ban; then
    # TODO: configure jails other than sshd
    log "Configuring Fail2Ban"
    FILE="/etc/fail2ban/jail.conf"
    EDIT_FILE_LOG=N edit_file "$FILE" \
        "^#?backend$S*=($S*(pyinotify|gamin|polling|systemd|auto))?($S*; .*)?\$" \
        "backend = systemd\3"
    [ -z "$TRUSTED_IP_ADDRESSES" ] ||
        EDIT_FILE_LOG=N edit_file "$FILE" \
            "^#?ignoreip$S*=($S*[^#]+)?($S*; .*)?\$" \
            "ignoreip = 127.0.0.1\\/8 ::1 ${TRUSTED_IP_ADDRESSES//\//\\\/}\2"
    log_file "$FILE"
fi

if is_installed postfix; then
    log "Binding Postfix to the loopback interface"
    postconf -e "inet_interfaces = loopback-only"
    if [ -n "$EMAIL_BLACKHOLE" ]; then
        log "Configuring Postfix to map all recipient addresses to '$EMAIL_BLACKHOLE'"
        postconf -e "recipient_canonical_maps = static:blackhole"
        cat <<EOF >>"/etc/aliases"

# Added by ${0##*/} at $(now)
blackhole:	$EMAIL_BLACKHOLE
EOF
        newaliases
    fi
    log_file "/etc/postfix/main.cf"
    log_file "/etc/aliases"
fi

if is_installed apache2; then
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
    [ "${#APACHE_DISABLE_MODS[@]}" -eq "0" ] || {
        log "Disabling Apache HTTPD modules:" "${APACHE_DISABLE_MODS[*]}"
        a2dismod --force "${APACHE_DISABLE_MODS[@]}"
    }
    [ "${#APACHE_ENABLE_MODS[@]}" -eq "0" ] || {
        log "Enabling Apache HTTPD modules:" "${APACHE_ENABLE_MODS[*]}"
        a2enmod --force "${APACHE_ENABLE_MODS[@]}"
    }

    # TODO: make PHP-FPM setup conditional
    [ -e "/opt/opcache-gui" ] || {
        log "Cloning 'https://github.com/lkrms/opcache-gui.git' to '/opt/opcache-gui'"
        install -v -d -m 2775 -o "$FIRST_ADMIN" -g "adm" "/opt/opcache-gui"
        keep_trying sudo -Hu "$FIRST_ADMIN" \
            git clone "https://github.com/lkrms/opcache-gui.git" \
            "/opt/opcache-gui"
    }

    log "Configuring Apache HTTPD to serve PHP-FPM virtual hosts"
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
    log_file "/etc/apache2/sites-available/${PATH_PREFIX}default.conf"

    log "Disabling pre-installed PHP-FPM pools"
    keep_original "/etc/php/$PHPVER/fpm/pool.d"
    rm -f "/etc/php/$PHPVER/fpm/pool.d"/*.conf

    if [ -n "$HOST_DOMAIN" ]; then
        log "Adding site to Apache HTTPD: $HOST_DOMAIN"
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

        log "Creating a self-signed SSL certificate for '$HOST_DOMAIN'"
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
        log_file "/etc/apache2/sites-available/$HOST_ACCOUNT.conf"

        log "Configuring PHP-FPM umask for group-writable files"
        FILE="/etc/systemd/system/php$PHPVER-fpm.service.d/override.conf"
        install -v -d -m 0755 "$(dirname "$FILE")"
        cat <<EOF >"$FILE"
[Service]
UMask=0002
EOF
        systemctl daemon-reload
        log_file "$FILE"

        log "Adding pool to PHP-FPM: $HOST_ACCOUNT"
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
catch_workers_output = yes
; tune based on system resources
php_admin_value[opcache.memory_consumption] = $OPCACHE_MEMORY_CONSUMPTION
php_admin_value[opcache.file_cache] = "/srv/www/\$pool/.cache/opcache"
php_admin_flag[opcache.validate_permission] = On
php_admin_value[error_log] = "/srv/www/\$pool/log/php$PHPVER-fpm.error.log"
php_admin_flag[log_errors] = On
php_flag[display_errors] = Off
php_flag[display_startup_errors] = Off

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
        log_file "/etc/php/$PHPVER/fpm/pool.d/$HOST_ACCOUNT.conf"
    fi

    log "Adding virtual host log files to logrotate.d"
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

    log "Adding iptables rules for Apache HTTPD"
    iptables -A "${P}input" -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A "${P}input" -p tcp -m tcp --dport 443 -j ACCEPT
fi

if is_installed mariadb-server; then
    FILE="/etc/mysql/mariadb.conf.d/90-${PATH_PREFIX}defaults.cnf"
    cat <<EOF >"$FILE"
[mysqld]
# must exceed the sum of pm.max_children across all PHP-FPM pools
max_connections = 301

innodb_buffer_pool_size = $INNODB_BUFFER_SIZE
innodb_buffer_pool_instances = $(((${INNODB_BUFFER_SIZE%M} - 1) / 1024 + 1))
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_load_at_startup = 1
EOF
    log_file "$FILE"
    log "Starting mysql.service (MariaDB)"
    systemctl start mysql.service
    if [ -n "$MYSQL_PASSWORD" ]; then
        MYSQL_USERNAME="${MYSQL_USERNAME:-dbadmin}"
        MYSQL_PASSWORD="${MYSQL_PASSWORD//\\/\\\\}"
        MYSQL_PASSWORD="${MYSQL_PASSWORD//\'/\\\'}"
        log "Creating MySQL administrator '$MYSQL_USERNAME'"
        echo "\
GRANT ALL PRIVILEGES ON *.* \
TO '$MYSQL_USERNAME'@'localhost' \
IDENTIFIED BY '$MYSQL_PASSWORD' \
WITH GRANT OPTION" | mysql -uroot
    fi

    log "Configuring MySQL account self-service"
    cat <<EOF >"/etc/sudoers.d/${PATH_PREFIX}mysql-self-service"
ALL ALL=(root) NOPASSWD:$LK_BASE/bin/lk-mysql-grant.sh
EOF
    log_file "/etc/sudoers.d/${PATH_PREFIX}mysql-self-service"

    # TODO: create $HOST_ACCOUNT database
fi

if is_installed memcached; then
    log "Configuring Memcached"
    FILE="/etc/memcached.conf"
    edit_file "$FILE" \
        "^#?(-m$S+|--memory-limit(=|$S+))[0-9]+$S*\$" \
        "\1$MEMCACHED_MEMORY_LIMIT" \
        "-m $MEMCACHED_MEMORY_LIMIT"
fi

log "Saving iptables rules"
iptables-save >"/etc/iptables/rules.v4"
ip6tables-save >"/etc/iptables/rules.v6"
log_file "/etc/iptables/rules.v4"
log_file "/etc/iptables/rules.v6"

log "Running apt-get autoremove"
apt-get -yq autoremove

log_header "${0##*/}: deployment complete"
log "Running shutdown with '--$SHUTDOWN_ACTION +${SHUTDOWN_DELAY:-0}'"
shutdown "--$SHUTDOWN_ACTION" +"${SHUTDOWN_DELAY:-0}"

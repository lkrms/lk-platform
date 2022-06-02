#!/bin/bash

function lk_is_bootstrap() {
    [ -n "${_LK_BOOTSTRAP-}" ]
}

function lk_is_desktop() {
    lk_node_service_enabled desktop
}

# lk_node_service_enabled SERVICE
#
# Return true if SERVICE or an equivalent appears in LK_NODE_SERVICES.
function lk_node_service_enabled() {
    [ -n "${LK_NODE_SERVICES-}" ] || return
    [[ ,$LK_NODE_SERVICES, == *,$1,* ]] ||
        [[ ,$(lk_node_expand_services), == *,$1,* ]]
}

function _lk_node_expand_service() {
    local SERVICE REVERSE=1
    [ "${1-}" != -n ] || { REVERSE= && shift; }
    if [[ ,$SERVICES, == *,$1,* ]]; then
        SERVICES=$SERVICES$(printf ',%s' "${@:2}")
    elif lk_is_true REVERSE; then
        for SERVICE in "${@:2}"; do
            [[ ,$SERVICES, == *,$SERVICE,* ]] || return 0
        done
        SERVICES=$SERVICES,$1
    fi
}

# lk_node_expand_services [SERVICE,...]
#
# Add alternative names to the service list (all enabled services by default).
function lk_node_expand_services() {
    local IFS=, SERVICES=${1-${LK_NODE_SERVICES-}}
    _lk_node_expand_service apache+php apache2 php-fpm
    _lk_node_expand_service mysql mariadb
    _lk_node_expand_service -n xfce4 desktop
    lk_echo_args $SERVICES | sort -u | lk_implode_input ","
}

function lk_list_user_homes() {
    if ! lk_is_macos; then
        getent passwd | awk -F: -v OFS=$'\t' '{print $1, $6}'
    else
        dscl . list /Users NFSHomeDirectory | awk -v OFS=$'\t' '{print $1, $2}'
    fi
}

function lk_list_group_ids() {
    if ! lk_is_macos; then
        getent group | awk -F: -v OFS=$'\t' '{print $1, $3}'
    else
        dscl . list /Groups PrimaryGroupID | awk -v OFS=$'\t' '{print $1, $2}'
    fi
}

function lk_group_exists() {
    lk_list_group_ids | cut -f1 | grep -Fx "$1" >/dev/null
}

# lk_user_add_sftp_only USERNAME [SOURCE_DIR TARGET_DIR]...
#
# Provision a user account with chroot-jailed SFTP access to its home directory,
# then bind mount each SOURCE_DIR to TARGET_DIR.
#
# A leading underscore will be added to USERNAME unless it matches an existing
# user or already starts with an underscore. If TARGET_DIR is not an absolute
# path, it will be taken as relative to the user's home directory.
function lk_user_add_sftp_only() {
    local IFS=$' \t\n' LK_SUDO=1 FILE REGEX MATCH CONFIG _HOME DIR GROUP TEMP \
        LK_FILE_REPLACE_NO_CHANGE SFTP_ONLY=${LK_SFTP_ONLY_GROUP:-sftp-only}
    [[ -n ${1-} ]] || lk_usage "\
Usage: $FUNCNAME USERNAME [SOURCE_DIR TARGET_DIR]...

Provision a user account with chroot-jailed SFTP access to its home directory,
then bind mount each SOURCE_DIR to TARGET_DIR.

Example:

  $FUNCNAME _consultant \\
    /srv/www/clientname/public_html public_html \\
    /srv/www/clientname/log log \\
    /srv/www/clientname/ssl ssl \\
    /srv/backup/snapshot/clientname backup \\
    /srv/backup/archive/clientname backup-archive" || return
    lk_group_exists "$SFTP_ONLY" || {
        lk_tty_print "Creating group:" "$SFTP_ONLY"
        lk_tty_run_detail -1 lk_elevate groupadd "$SFTP_ONLY" || return
    }
    lk_tty_print "Checking SSH server"
    FILE=/etc/ssh/sshd_config
    REGEX=("[mM][aA][tT][cC][hH]" "[gG][rR][oO][uU][pP]")
    MATCH="^($S*#)?$S*($REGEX|\"$REGEX\")($S+|$S*=$S*)"
    CONFIG="\
Match Group $SFTP_ONLY
ForceCommand internal-sftp
ChrootDirectory %h"
    lk_file_keep_original "$FILE"
    lk_file_replace "$FILE" < <(awk \
        -v "BLOCK=$CONFIG" \
        -v "FIRST=$MATCH(${REGEX[1]}|\"${REGEX[1]}\")$S+(${SFTP_ONLY}|\"${SFTP_ONLY}\")$S*$" \
        -v "BREAK=$MATCH" \
        -f "$LK_BASE/lib/awk/block-replace.awk" "$FILE")
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        lk_tty_run_detail -1 lk_elevate systemctl restart ssh.service
    [[ $1 == _* ]] || lk_user_exists "$1" || set -- "_$1" "${@:2}"
    if lk_user_exists "$1"; then
        lk_confirm "Configure existing user '$1' for SFTP-only access?" Y &&
            lk_tty_run_detail -1 lk_elevate \
                usermod --shell /bin/false --groups "$SFTP_ONLY" --append "$1"
    else
        lk_tty_print "Creating user:" "$1"
        lk_tty_run_detail -1 lk_elevate \
            useradd --create-home --shell /bin/false --groups "$SFTP_ONLY" "$1"
    fi || return
    _HOME=$(lk_user_home "$1") && lk_elevate -f test -d "$_HOME" ||
        lk_warn "invalid home directory: $_HOME" || return
    [ $# -lt 3 ] ||
        _LK_USER_HOME=$_HOME lk_user_bind_dir "$@" || return
    DIR=$_HOME/.ssh
    FILE=$DIR/authorized_keys
    GROUP=$(id -gn "$1") &&
        lk_install -d -m 00755 -o root -g root "$_HOME" &&
        lk_install -d -m 00700 -o "$1" -g "$GROUP" "$DIR" &&
        lk_install -m 00600 -o "$1" -g "$GROUP" "$FILE" || return
    lk_elevate test -s "$FILE" || {
        lk_tty_print "Generating SSH key for user '$1'"
        TEMP=/tmp/$FUNCNAME-$1-id_rsa
        ssh-keygen -t ed25519 -N "" -q -C "$1@$(lk_hostname)" -f "$TEMP" &&
            lk_elevate cp "$TEMP.pub" "$FILE" &&
            lk_tty_file "$TEMP" || return
        lk_tty_warning "${LK_BOLD}WARNING:$LK_RESET \
this private key ${LK_BOLD}WILL NOT BE DISPLAYED AGAIN$LK_RESET"
    }
}

function lk_user_bind_dir() {
    local LK_SUDO=1 _USER=${1-} _HOME=${_LK_USER_HOME-} TEMP TEMP2 \
        SOURCE TARGET FSROOT TARGETS=() STATUS=0
    # Skip these checks if _LK_USER_HOME is set
    [ -n "$_HOME" ] || {
        lk_user_exists "$_USER" || lk_warn "user not found: $_USER" || return
        _HOME=$(lk_user_home "$1") && lk_elevate -f test -d "$_HOME" ||
            lk_warn "invalid home directory: $_HOME" || return
    }
    shift
    lk_tty_print "Checking bind mounts for user '$1'"
    lk_command_exists findmnt || lk_warn "command not found: findmnt" || return
    TEMP=$(lk_mktemp_file) && TEMP2=$(lk_mktemp_file) &&
        lk_delete_on_exit "$TEMP" "$TEMP2" || return
    lk_elevate -f cp /etc/fstab "$TEMP"
    while [ $# -ge 2 ]; do
        SOURCE=$1
        TARGET=$2
        shift 2
        [[ $TARGET == /* ]] || TARGET=$_HOME/$TARGET
        [[ $TARGET == $_HOME/* ]] ||
            lk_warn "target not in $_HOME: $TARGET" || return
        lk_elevate -f test -d "$SOURCE" ||
            lk_warn "source directory not found: $SOURCE" || return
        while :; do
            FSROOT=$(lk_elevate findmnt -no FSROOT -M "$TARGET") ||
                { FSROOT= && break; }
            lk_elevate test ! "$FSROOT" -ef "$SOURCE" || break
            lk_tty_warning "Already mounted at $TARGET:" \
                "$(lk_elevate findmnt -no SOURCE -M "$TARGET")"
            lk_confirm "OK to unmount?" Y &&
                lk_tty_run_detail -1 lk_elevate umount "$TARGET" || return
        done
        [ -n "$FSROOT" ] || {
            lk_install -d -m 00755 -o root -g root "$TARGET" || return
            TARGETS[${#TARGETS[@]}]=$TARGET
        }
        awk -v "source=$SOURCE" -v "target=$TARGET" -v OFS=$'\t' '
function maybe_print() { if (source) {
    print source, target, "none", "bind", 0, 0; source = ""
} }
{ sub(/^[[:blank:]]*/, "") }
/^[^#]/ && $2 == target { maybe_print(); next }
{ print }
END { maybe_print() }' "$TEMP" >"$TEMP2" && cp "$TEMP2" "$TEMP" || return
    done
    lk_elevate findmnt -F "$TEMP" --verify &>"$TEMP2" ||
        lk_pass cat "$TEMP2" >&2 ||
        lk_pass lk_delete_on_exit_withdraw "$TEMP" ||
        lk_warn "invalid fstab: $TEMP" || return
    lk_file_replace -m -f "$TEMP" /etc/fstab
    for TARGET in ${TARGETS+"${TARGETS[@]}"}; do
        lk_tty_run_detail -1 lk_elevate mount --target "$TARGET" || STATUS=$?
    done
}

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

function _lk_settings_list_known() {
    printf '%s\n' \
        LK_BASE \
        LK_PATH_PREFIX \
        LK_NODE_HOSTNAME LK_NODE_FQDN \
        LK_IPV4_ADDRESS LK_IPV4_GATEWAY LK_DNS_SERVERS LK_DNS_SEARCH \
        LK_BRIDGE_INTERFACE \
        LK_WIFI_REGDOM \
        LK_NODE_TIMEZONE \
        LK_NODE_SERVICES LK_NODE_PACKAGES \
        LK_NODE_LOCALES LK_NODE_LANGUAGE \
        LK_SAMBA_WORKGROUP \
        LK_GRUB_CMDLINE \
        LK_NTP_SERVER \
        LK_ADMIN_EMAIL \
        LK_TRUSTED_IP_ADDRESSES \
        LK_SSH_TRUSTED_ONLY LK_SSH_TRUSTED_PORT \
        LK_SSH_JUMP_HOST LK_SSH_JUMP_USER LK_SSH_JUMP_KEY \
        LK_REJECT_OUTPUT LK_ACCEPT_OUTPUT_HOSTS \
        LK_INNODB_BUFFER_SIZE \
        LK_OPCACHE_MEMORY_CONSUMPTION \
        LK_PHP_VERSIONS LK_PHP_DEFAULT_VERSION \
        LK_PHP_SETTINGS LK_PHP_ADMIN_SETTINGS \
        LK_MEMCACHED_MEMORY_LIMIT \
        LK_SMTP_RELAY LK_SMTP_CREDENTIALS LK_SMTP_SENDERS \
        LK_EMAIL_DESTINATION \
        LK_UPGRADE_EMAIL \
        LK_AUTO_REBOOT LK_AUTO_REBOOT_TIME \
        LK_AUTO_BACKUP_SCHEDULE \
        LK_SNAPSHOT_{HOURLY,DAILY,WEEKLY,FAILED}_MAX_AGE \
        LK_LAUNCHPAD_PPA_MIRROR \
        LK_SITE_ENABLE LK_SITE_DISABLE_WWW LK_SITE_DISABLE_HTTPS \
        LK_SITE_ENABLE_STAGING \
        LK_ARCH_MIRROR \
        LK_ARCH_REPOS \
        LK_DEBUG \
        LK_PLATFORM_BRANCH \
        LK_PACKAGES_FILE
}

# _lk_settings_list_legacy
#
# Print the names of settings that are no longer used.
function _lk_settings_list_legacy() {
    printf '%s\n' \
        LK_PATH_PREFIX_ALPHA \
        LK_SCRIPT_DEBUG \
        LK_EMAIL_BLACKHOLE
}

function _lk_settings_writable_files() {
    local FILE OLD_FILE DIR_MODE FILE_MODE ARGS
    if lk_will_elevate && [[ $LK_BASE/ != ~/* ]]; then
        FILE=$LK_BASE/etc/lk-platform/lk-platform.conf
        OLD_FILE=/etc/default/lk-platform
        DIR_MODE=0755
        FILE_MODE=0644
        [ ! -g "$LK_BASE" ] || {
            DIR_MODE=2775
            FILE_MODE=0664
            ARGS=(-g "$(lk_file_group "$LK_BASE")") || return
        }
        lk_install -d -m "$DIR_MODE" ${ARGS+"${ARGS[@]}"} \
            "$LK_BASE"/etc{,/lk-platform} &&
            lk_install -m "$FILE_MODE" ${ARGS+"${ARGS[@]}"} "$FILE" || return
        echo "$FILE"
    else
        local XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-~/.config} \
            LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
        FILE=$XDG_CONFIG_HOME/lk-platform/lk-platform.conf
        OLD_FILE=~/".${LK_PATH_PREFIX}settings"
        [ -e "$FILE" ] || {
            mkdir -p "${FILE%/*}" &&
                touch "$FILE" || return
        }
        echo "$FILE"
    fi
    [ ! -f "$OLD_FILE" ] || {
        echo "$OLD_FILE"
        [ -s "$FILE" ] || [ ! -s "$OLD_FILE" ] ||
            LK_VERBOSE= LK_FILE_BACKUP_TAKE= \
                lk_file_replace -f "$OLD_FILE" "$FILE" || return
    }
}

# _lk_settings_migrate SETTING OLD_SETTING...
function _lk_settings_migrate() {
    printf '%s=%s\n' "$1" "$(
        SH=
        while [ $# -gt 0 ]; do
            printf '${%s-' "$1"
            SH+="}"
            shift
        done
        echo "$SH"
    )"
    shift
    UNSET+=("$@")
}

# lk_settings_getopt [ARG...]
#
# Output Bash commands that
# - migrate legacy settings to their new names
# - apply any --set, --add, --remove, or --unset arguments to the running shell
# - set _LK_SHIFT to the number of arguments consumed
function lk_settings_getopt() {
    local IFS=$' \t\n' s o SHIFT=0 _SHIFT \
        UNSET=() REGEX='^(LK_[a-zA-Z0-9_]*[a-zA-Z0-9])(=(.*))?$'
    _lk_settings_migrate LK_DEBUG {LK_,}SCRIPT_DEBUG
    _lk_settings_migrate LK_EMAIL_DESTINATION {LK_,}EMAIL_BLACKHOLE
    for s in $(_lk_settings_list_known | grep -Fxv LK_BASE); do
        o=()
        [[ $s == LK_NODE_* ]] || {
            o[${#o[@]}]=LK_NODE_${s#LK_}
            o[${#o[@]}]=LK_DEFAULT_${s#LK_}
        }
        o[${#o[@]}]=${s#LK_}
        _lk_settings_migrate "$s" "${o[@]}"
    done
    echo "unset$(printf ' %s' $(printf '%s\n' "${UNSET[@]}" | sed '/^LK_/!d'))"
    while [[ ${1-} =~ ^(-[saru]|--(set|add|remove|unset))$ ]]; do
        [[ ${2-} =~ $REGEX ]] ||
            lk_warn "$1: invalid argument: ${2-}" || return
        # "--set LK_SETTING=value" -> "--set LK_SETTING value"
        [ -z "${BASH_REMATCH[2]-}" ] || {
            set -- "$1" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "${@:3}"
            ((SHIFT--)) || true
        }
        _SHIFT=3
        case "$1" in
        -s | --set)
            printf '%s=%q\n' "$2" "${3-}"
            ;;
        -a | --add)
            printf '%s=$(unset IFS && IFS=, lk_string_sort -u "${%s-},"%q)\n' \
                "$2" "$2" "${3-}"
            ;;
        -r | --remove)
            printf '%s=$(unset IFS && IFS=, lk_string_remove "${%s-}" %q)\n' \
                "$2" "$2" "${3-}"
            ;;
        -u | --unset)
            # Reject "--unset LK_SETTING=value"
            [ -z "${BASH_REMATCH[2]-}" ] ||
                lk_warn "$1: invalid argument: ${BASH_REMATCH[0]}" || return
            echo "unset $2"
            ((_SHIFT--))
            ;;
        *)
            break
            ;;
        esac
        [ $# -ge "$_SHIFT" ] || lk_warn "$1: invalid arguments" || return
        ((SHIFT += _SHIFT))
        shift "$_SHIFT"
    done
    printf '%s=%q\n' _LK_SHIFT "$SHIFT"
}

# lk_settings_persist COMMANDS [FILE...]
#
# Source each FILE, execute COMMANDS (e.g. lk_settings_getopt output), and
# replace the first FILE with shell variable assignments for all declared LK_*
# variables.
#
# If FILE is not specified:
# - update system settings if running as root
# - if not running as root, update the current user's settings
# - delete old config files
function lk_settings_persist() {
    local IFS FILES DELETE=() _FILE
    [ $# -ge 1 ] || lk_warn "invalid arguments" || return
    [ $# -ge 2 ] || {
        IFS=$'\n'
        FILES=($(_lk_settings_writable_files)) || return
        set -- "$1" "${FILES[@]}"
        DELETE=("${@:3}")
    }
    unset IFS
    lk_mktemp_with _FILE
    (
        unset "${!LK_@}"
        for ((i = $#; i > 1; i--)); do
            [ ! -f "${!i}" ] || . "${!i}" || return
        done
        CONFIGURED=("${!LK_@}")
        eval "$1" || return
        # Exclude empty variables unless they have been explicitly configured
        unset $(comm -13 \
            <(printf '%s\n' "${CONFIGURED[@]}" | sort -u) \
            <(for s in "${!LK_@}"; do
                [ -n "${!s:+1}" ] || echo "$s"
            done | sort -u))
        VARS=($(_lk_settings_list_known &&
            comm -23 \
                <(printf '%s\n' "${!LK_@}" | sort -u) \
                <({ _lk_settings_list_known &&
                    _lk_settings_list_legacy; } | sort -u)))
        lk_var_sh "${VARS[@]}"
    ) >"$_FILE" || return
    lk_file_replace -m -f "$_FILE" "$2" &&
        lk_file_backup -m ${DELETE+"${DELETE[@]}"} &&
        lk_maybe_sudo rm -f -- ${DELETE+"${DELETE[@]}"}
}

function lk_node_is_router() {
    [ "${LK_IPV4_ADDRESS:+1}${LK_IPV4_GATEWAY:+2}" = 1 ] ||
        lk_node_service_enabled router
}

# lk_dns_get_records [-TYPE[,TYPE...]] [+FIELD[,FIELD...]] NAME...
#
# For each NAME, look up DNS resource records of the given TYPE (default: `A`)
# and if any matching records are found, print whitespace-delimited values for
# each requested FIELD (default: `NAME,TTL,CLASS,TYPE,RDATA`).
#
# Field names (not case-sensitive):
# - `NAME`
# - `TTL`
# - `CLASS`
# - `TYPE`
# - `RDATA`
# - `VALUE` (alias for `RDATA`)
#
# Returns false only if an error occurs.
function lk_dns_get_records() {
    local IFS=$' \t\n' FIELDS TYPES TYPE NAME QUERY=()
    while [[ ${1-} == [+-]* ]]; do
        [[ ${1-} != -* ]] || {
            TYPES=($(IFS=, && lk_upper ${1:1} | sort -u)) || return
        }
        [[ ${1-} != +* ]] || {
            FIELDS=$(IFS=, && lk_upper ${1:1} |
                awk -v caller="$FUNCNAME" '
function toexpr(var) { expr = expr (expr ? ", " : "") var; next }
/^NAME$/ { toexpr("$1") }
/^TTL$/ { toexpr("$2") }
/^CLASS$/ { toexpr("$3") }
/^TYPE$/ { toexpr("$4") }
/^(RDATA|VALUE)$/ { toexpr("rdata()") }
{ print caller ": invalid field: " $0 > "/dev/stderr"; status = 1 }
END { if (status) { exit status } print expr }') || return
        }
        shift
    done
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    for TYPE in "${TYPES[@]-}"; do
        for NAME in "$@"; do
            QUERY[${#QUERY[@]}]=$NAME
            [[ -z $TYPE ]] ||
                QUERY[${#QUERY[@]}]=$TYPE
        done
    done
    dig +noall +answer \
        ${_LK_DIG_ARGS+"${_LK_DIG_ARGS[@]}"} \
        ${_LK_DNS_SERVER:+@"$_LK_DNS_SERVER"} \
        "${QUERY[@]}" |
        awk -v S="$S" \
            -v NS="$NS" \
            -v types=${TYPES+"^$(lk_ere_implode_arr -e TYPES)\$"} "
function printexpr() { print ${FIELDS-} }"'
function rdata(r, i) {
  r = $0
  for (i = 0; i < 4; i++) { sub("^" S "*" NS "+" S "+", "", r) }
  return r
}
!types || $4 ~ types { printexpr() }'
}

# lk_dns_get_records_first_parent [-TYPE[,TYPE...]] [+FIELD[,FIELD...]] NAME
#
# Same as `lk_dns_get_records`, but if no matching records are found, replace
# NAME with its parent domain and retry, continuing until matching records are
# found or there are no more parent domains to try.
#
# Returns false if no matching records are found.
function lk_dns_get_records_first_parent() {
    local IFS=$' \t\n' NAME=${*:$#} DOMAIN
    lk_is_fqdn "$NAME" || lk_warn "invalid domain: $NAME" || return
    DOMAIN=$NAME
    set -- "${@:1:$#-1}"
    while :; do
        lk_dns_get_records "$@" "$NAME" | grep . && break ||
            [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == 01 ]] || return
        NAME=${NAME#*.}
        lk_is_fqdn "$NAME" || lk_warn "lookup failed: $DOMAIN" || return
    done
}

# lk_dns_resolve_name_from_ns NAME
#
# Look up IP addresses for NAME from its primary nameserver and print them if
# found, otherwise return false.
function lk_dns_resolve_name_from_ns() {
    local IFS=$' \t\n' NAMESERVER IP CNAME _LK_DIG_ARGS _LK_DNS_SERVER
    NAMESERVER=$(lk_dns_get_records_first_parent -SOA "$1" |
        awk 'NR == 1 { sub(/\.$/, "", $5); print $5 }') || return
    _LK_DIG_ARGS=(+norecurse)
    _LK_DNS_SERVER=$NAMESERVER
    ! lk_verbose 2 || {
        lk_tty_detail "Using name server:" "$NAMESERVER"
        lk_tty_detail "Looking up A and AAAA records for:" "$1"
    }
    IP=($(lk_dns_get_records +VALUE -A,AAAA "$1")) || return
    if [[ ${#IP[@]} -eq 0 ]]; then
        ! lk_verbose 2 || {
            lk_tty_detail "No A or AAAA records returned"
            lk_tty_detail "Looking up CNAME record for:" "$1"
        }
        CNAME=($(lk_dns_get_records +VALUE -CNAME "$1")) || return
        if [[ ${#CNAME[@]} -eq 1 ]]; then
            ! lk_verbose 2 ||
                lk_tty_detail "CNAME value from $NAMESERVER for $1:" "$CNAME"
            unset _LK_DIG_ARGS _LK_DNS_SERVER
            IP=($(lk_dns_get_records +VALUE -A,AAAA "${CNAME%.}")) || return
        fi
    fi
    [[ ${#IP[@]} -gt 0 ]] ||
        lk_warn "could not resolve $1${_LK_DNS_SERVER+: $NAMESERVER}" || return
    ! lk_verbose 2 ||
        lk_tty_detail \
            "A and AAAA values${_LK_DNS_SERVER+ from $NAMESERVER} for $1:" \
            "$(lk_arr IP)"
    lk_arr IP
}

# lk_dns_resolve_names [-d] FQDN...
#
# Print one or more "ADDRESS HOST" lines for each FQDN. If -d is set, use DNS
# instead of host lookups.
function lk_dns_resolve_names() {
    local USE_DNS
    unset USE_DNS
    [ "${1-}" != -d ] || { USE_DNS= && shift; }
    case "${USE_DNS-$(lk_first_command getent dscacheutil)}" in
    getent)
        { getent ahosts "$@" || [ $# -eq 2 ]; } | awk '
$3          { host = $3 }
!a[$1,host] { print $1, host; a[$1,host] = 1 }'
        ;;
    dscacheutil)
        printf '%s\n' "$@" | xargs -n1 \
            dscacheutil -q host -a name | awk '
/^name:/                            { host = $2 }
/^ip(v6)?_address:/ && !a[$2,host]  { print $2, host; a[$2,host] = 1 }'
        ;;
    *)
        lk_dns_get_records +NAME,VALUE -A,AAAA "$@" |
            awk '{ sub("\\.$", "", $1); print $2, $1 }'
        ;;
    esac
}

# lk_dns_resolve_hosts [-d] HOST...
#
# Resolve each HOST to one or more IP addresses, where HOST is an IP address,
# CIDR, FQDN or URL|JQ_FILTER, printing each IP and CIDR as-is and ignoring each
# invalid host. If -d is set, use DNS instead of host lookups.
function lk_dns_resolve_hosts() { {
    local USE_DNS HOSTS=()
    [ "${1-}" != -d ] || { USE_DNS=1 && shift; }
    while [ $# -gt 0 ]; do
        if lk_is_cidr "$1"; then
            echo "$1"
        elif lk_is_fqdn "$1"; then
            HOSTS[${#HOSTS[@]}]=$1
        elif [[ $1 == *\|* ]]; then
            lk_curl "${1%%|*}" | jq -r "${1#*|}" || return
        fi
        shift
    done
    [ -z "${HOSTS+1}" ] ||
        lk_dns_resolve_names ${USE_DNS:+-d} "${HOSTS[@]}" | awk '{print $1}'
} | sort -u; }

# lk_postconf_get PARAM
function lk_postconf_get() {
    # `postconf -nh` prints a newline if the parameter has an empty value, and
    # nothing at all if the parameter is not set in main.cf
    (($(postconf -nh "$1" | wc -c))) && postconf -nh "$1"
}

# lk_postconf_set PARAM VALUE
function lk_postconf_set() {
    lk_postconf_get "$1" | grep -Fx "$2" >/dev/null ||
        { lk_elevate postconf -e "$1 = $2" &&
            lk_mark_dirty "postfix.service"; }
}

# lk_postconf_unset PARAM
function lk_postconf_unset() {
    ! lk_postconf_get "$1" >/dev/null ||
        { lk_elevate postconf -X "$1" &&
            lk_mark_dirty "postfix.service"; }
}

# lk_postmap SOURCE_PATH DB_PATH [FILE_MODE]
#
# Safely install or update the Postfix database at DB_PATH with the content of
# SOURCE_PATH.
function lk_postmap() {
    local LK_SUDO=1 FILE=$2.in
    lk_install -m "${3:-00644}" "$FILE" &&
        lk_elevate cp "$1" "$FILE" &&
        lk_elevate postmap "$FILE" || return
    if ! lk_elevate diff -qN "$2" "$FILE" >/dev/null ||
        ! diff -qN \
            <(lk_elevate postmap -s "$2" | sort) \
            <(lk_elevate postmap -s "$FILE" | sort) >/dev/null; then
        lk_elevate mv -f "$FILE.db" "$2.db" &&
            lk_elevate mv -f "$FILE" "$2" &&
            lk_mark_dirty "postfix.service"
    else
        lk_elevate rm -f "$FILE"{,.db}
    fi
}

function _lk_openssl_verify() { (
    # Disable xtrace if its output would break the test below
    [[ $- != *x* ]] ||
        { lk_bash_at_least 4 1 && [ "${BASH_XTRACEFD:-2}" -gt 2 ]; } ||
        set +x
    # In case openssl is too old to exit non-zero when `verify` fails, return
    # false if there are multiple lines of output (NB: some versions send errors
    # to stderr)
    lk_sudo openssl verify "$@" 2>&1 |
        awk '{print} END {exit NR > 1 ? 1 : 0}'
); }

# lk_ssl_is_cert_self_signed CERT_FILE
function lk_ssl_is_cert_self_signed() {
    lk_mktemp_dir_with -r _LK_EMPTY_DIR || return
    # "-CApath /empty/dir" is more portable than "-no-CApath"
    _lk_openssl_verify -CApath "$_LK_EMPTY_DIR" -CAfile "$1" "$1" >/dev/null
}

# lk_ssl_verify_cert [-s] CERT_FILE [KEY_FILE [CA_FILE]]
#
# If -s is set, return true if the certificate is trusted, even if it is
# self-signed.
function lk_ssl_verify_cert() {
    local SS_OK
    [ "${1-}" != -s ] || { SS_OK=1 && shift; }
    lk_files_exist "$@" || lk_usage "\
Usage: $FUNCNAME [-s] CERT_FILE [KEY_FILE [CA_FILE]]" || return
    local CERT=$1 KEY=${2-} CA=${3-} CERT_MODULUS KEY_MODULUS
    # If no CA file has been provided but CERT contains multiple certificates,
    # copy the first to a temp CERT file and the others to a temp CA file
    [ -n "$CA" ] || [ "$(grep -Ec "^-+BEGIN$S" "$CERT")" -le 1 ] ||
        { lk_mktemp_with CA \
            lk_sudo awk "/^-+BEGIN$S/ {c++} c > 1 {print}" "$CERT" &&
            lk_mktemp_with CERT \
                lk_sudo awk "/^-+BEGIN$S/ {c++} c <= 1 {print}" "$CERT" ||
            return; }
    if [ -n "$CA" ]; then
        _lk_openssl_verify "$CA" &&
            _lk_openssl_verify -untrusted "$CA" "$CERT"
    else
        _lk_openssl_verify "$CERT"
    fi >/dev/null ||
        lk_warn "invalid certificate chain" || return
    [ -z "$KEY" ] || {
        CERT_MODULUS=$(lk_sudo openssl x509 -noout -modulus -in "$CERT") &&
            KEY_MODULUS=$(lk_sudo openssl rsa -noout -modulus -in "$KEY") &&
            [ "$CERT_MODULUS" = "$KEY_MODULUS" ] ||
            lk_warn "certificate and private key do not match" || return
    }
    [ -n "${SS_OK-}" ] || ! lk_ssl_is_cert_self_signed "$CERT" ||
        lk_warn "certificate is self-signed" || return
}

# lk_ssl_create_self_signed_cert DOMAIN...
function lk_ssl_create_self_signed_cert() {
    [ $# -gt 0 ] || lk_usage "Usage: $FUNCNAME DOMAIN..." || return
    lk_test_many lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    lk_tty_print "Creating a self-signed TLS certificate for:" \
        $'\n'"$(printf '%s\n' "$@")"
    local CA_FILE=${LK_SSL_CA:+$1-${LK_SSL_CA##*/}}
    lk_no_input || {
        local FILES=("$1".{key,csr,cert} ${CA_FILE:+"$CA_FILE"})
        lk_remove_missing_or_empty FILES || return
        [ ${#FILES[@]} -eq 0 ] || {
            lk_tty_detail "Files to overwrite:" \
                $'\n'"$(printf '%s\n' "${FILES[@]}")"
            lk_confirm "Proceed?" Y || return
        }
    }
    local CONF
    lk_mktemp_with CONF cat /etc/ssl/openssl.cnf &&
        printf "\n[ %s ]\n%s = %s" san subjectAltName \
            "$(lk_implode_args ", " "${@/#/DNS:}")" >>"$CONF" || return
    lk_install -m 00644 "$1.cert" ${CA_FILE:+"$CA_FILE"} &&
        lk_install -m 00640 "$1".{key,csr} || return
    local ARGS=(-signkey "$1.key")
    [ -z "$CA_FILE" ] || {
        local ARGS=(-CA "$LK_SSL_CA" -CAcreateserial)
        [ -z "${LK_SSL_CA_KEY:+1}" ] ||
            ARGS+=(-CAkey "$LK_SSL_CA_KEY")
    }
    lk_sudo openssl req -new \
        -newkey rsa:2048 \
        -nodes \
        -keyout "$1.key" \
        -subj "/OU=lk-platform/CN=$1" \
        -reqexts san \
        -config "$CONF" \
        -out "$1.csr" &&
        lk_sudo openssl x509 -req \
            -days 365 \
            -in "$1.csr" \
            -extensions san \
            -extfile "$CONF" \
            -out "$1.cert" \
            "${ARGS[@]}" &&
        lk_sudo rm -f "$1.csr" || return
    [ -z "$CA_FILE" ] || {
        lk_sudo openssl x509 -in "$LK_SSL_CA" -out "$CA_FILE" &&
            LK_VERBOSE= lk_file_replace \
                "$1.cert" < <(lk_sudo cat "$1.cert" "$CA_FILE")
    }
}

# lk_ssl_install_ca_certificate CERT_FILE
function lk_ssl_install_ca_certificate() {
    local DIR COMMAND CERT FILE \
        _LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE-}
    unset LK_FILE_REPLACE_NO_CHANGE
    DIR=$(lk_first_file \
        /usr/local/share/ca-certificates/ \
        /etc/ca-certificates/trust-source/anchors/) &&
        COMMAND=$(LK_SUDO= && lk_first_command \
            update-ca-certificates \
            update-ca-trust) ||
        lk_warn "CA certificate store not found" || return
    lk_mktemp_with CERT \
        lk_sudo openssl x509 -in "$1" || return
    FILE=$DIR${1##*/}
    FILE=${FILE%.*}.crt
    local LK_SUDO=1
    lk_install -m 00644 "$FILE" &&
        LK_FILE_NO_DIFF=1 \
            lk_file_replace -mf "$1" "$FILE" || return
    if lk_is_false LK_FILE_REPLACE_NO_CHANGE; then
        lk_elevate "$COMMAND"
    else
        LK_FILE_REPLACE_NO_CHANGE=$_LK_FILE_REPLACE_NO_CHANGE
    fi
}

# lk_certbot_list [DOMAIN...]
#
# Parse `certbot certificates` output to tab-separated fields as follows:
# 1. Certificate name
# 2. Domains (format: <name>[,www.<name>][,<other_domain>...])
# 3. Expiry date (format: %Y-%m-%d %H:%M:%S%z)
# 4. Certificate path
# 5. Private key path
function lk_certbot_list() {
    local ARGS IFS=,
    [ $# -eq 0 ] ||
        ARGS=(--domains "$*")
    lk_elevate certbot certificates ${ARGS[@]+"${ARGS[@]}"} |
        awk -f "$LK_BASE/lib/awk/certbot-parse-certificates.awk"
}

# lk_certbot_install [-w WEBROOT_PATH] DOMAIN... [-- CERTBOT_ARG...]
function lk_certbot_install() {
    local WEBROOT WEBROOT_PATH ERRORS=0 \
        EMAIL=${LK_LETSENCRYPT_EMAIL-${LK_ADMIN_EMAIL-}} DOMAIN DOMAINS=()
    unset WEBROOT
    [ "${1-}" != -w ] || { WEBROOT= && WEBROOT_PATH=$2 && shift 2; }
    while [ $# -gt 0 ]; do
        [ "$1" != -- ] || {
            shift
            break
        }
        DOMAINS+=("$1")
        shift
    done
    [ ${#DOMAINS[@]} -gt 0 ] ||
        lk_usage "$FUNCNAME [-w WEBROOT_PATH] DOMAIN... [-- CERTBOT_ARG...]" ||
        return
    lk_is_fqdn "${DOMAINS[@]}" || lk_warn "invalid arguments" || return
    [ -z "${WEBROOT+1}" ] || lk_elevate test -d "$WEBROOT_PATH" ||
        lk_warn "directory not found: $WEBROOT_PATH" || return
    [ -n "$EMAIL" ] || lk_warn "email address not set" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    [ -n "${_LK_LETSENCRYPT_IGNORE_DNS-}" ] || {
        local IFS=' '
        lk_tty_print "Checking DNS"
        lk_tty_detail "Resolving $(lk_plural DOMAINS domain):" "${DOMAINS[*]}"
        for DOMAIN in "${DOMAINS[@]}"; do
            lk_node_is_host "$DOMAIN" ||
                lk_tty_error -r "System address not matched:" "$DOMAIN" ||
                ((++ERRORS))
        done
        ((!ERRORS)) || lk_confirm "Ignore DNS errors?" N || return
    }
    local IFS=,
    lk_tty_run lk_elevate certbot \
        ${WEBROOT-run} \
        ${WEBROOT+certonly} \
        --non-interactive \
        --keep-until-expiring \
        --expand \
        --agree-tos \
        --email "$EMAIL" \
        --no-eff-email \
        ${WEBROOT---no-redirect} \
        ${WEBROOT---"${_LK_CERTBOT_PLUGIN:-apache}"} \
        ${WEBROOT+--webroot} \
        ${WEBROOT+--webroot-path "$WEBROOT_PATH"} \
        --domains "${DOMAINS[*]}" \
        ${LK_CERTBOT_OPTIONS[@]:+"${LK_CERTBOT_OPTIONS[@]}"} \
        "$@"
}

# lk_certbot_install_asap DOMAIN...
function lk_certbot_install_asap() {
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    local IFS=' ' RESOLVED FAILED CHANGED DOMAIN DOTS=0 LAST_RESOLVED=() i=0
    lk_tty_print "Preparing Let's Encrypt request"
    lk_tty_detail "Checking $(lk_plural $# domain):" "$*"
    while :; do
        RESOLVED=()
        FAILED=()
        CHANGED=0
        for DOMAIN in "$@"; do
            ! lk_node_is_host "$DOMAIN" || {
                RESOLVED+=("$DOMAIN")
                continue
            }
            FAILED+=("$DOMAIN")
        done
        [ "${RESOLVED[*]-}" = "${LAST_RESOLVED[*]-}" ] || {
            ((!DOTS)) || echo >&2
            ((DOTS = 0, CHANGED = 1))
            ((!i)) || lk_tty_log "Change detected at" "$(lk_date_log)"
            LAST_RESOLVED=(${RESOLVED+"${RESOLVED[@]}"})
        }
        [ -n "${FAILED+1}" ] || break
        ((i && !CHANGED)) ||
            lk_tty_error "System address not matched:" "${FAILED[*]}"
        ((i)) || lk_tty_detail "Checking DNS every 60 seconds"
        [ ! -t 2 ] || {
            echo -n . >&2
            ((++DOTS))
        }
        sleep 60
        ((++i))
    done
    _LK_LETSENCRYPT_IGNORE_DNS=1 lk_certbot_install "$@"
}

# lk_composer_install [INSTALL_PATH]
function lk_composer_install() {
    local DEST=${1-} URL SHA FILE BASE_URL=https://getcomposer.org
    [ -n "$DEST" ] ||
        { lk_sudo test -w /usr/local/bin &&
            DEST=/usr/local/bin/composer || DEST=.; }
    [ ! -d "$DEST" ] || DEST=${DEST%/}/composer.phar
    lk_tty_print "Installing composer"
    URL=$BASE_URL$(lk_curl "$BASE_URL/versions" | jq -r '.stable[0].path') &&
        SHA=$(lk_curl "$URL.sha256sum" | awk '{print $1}') || return
    lk_tty_detail "Downloading" "$URL"
    lk_mktemp_with FILE lk_curl "$URL" || return
    lk_tty_detail "Verifying download"
    sha256sum "$FILE" | awk '{print $1}' | grep -Fxq "$SHA" ||
        lk_warn "invalid sha256sum: $FILE" || return
    lk_tty_detail "Installing to" "$DEST"
    lk_sudo install -m 00755 "$FILE" "$DEST"
}

# _lk_cpanel_get_url SERVER MODULE FUNC [PARAMETER=VALUE...]
function _lk_cpanel_get_url() {
    [ $# -ge 3 ] || lk_warn "invalid arguments" || return
    local PARAMS
    printf 'https://%s:%s/%s/%s' \
        "$1" \
        "${_LK_CPANEL_PORT:-2083}" \
        "${_LK_CPANEL_ROOT:-execute}" \
        "$2${3:+/$3}"
    shift 3
    PARAMS=$(lk_uri_encode "$@") || return
    [ -z "${PARAMS:+1}" ] || printf "?%s" "$PARAMS"
    echo
}

# _lk_cpanel_via_whm_get_url SERVER USER MODULE FUNC [PARAMETER=VALUE...]
function _lk_cpanel_via_whm_get_url() {
    [[ $# -ge 4 ]] || lk_warn "invalid arguments" || return
    local _USER=$2 MODULE=$3 FUNC=$4 PARAMS
    printf 'https://%s:%s/json-api/cpanel' "$1" 2087
    shift 4
    PARAMS=$(lk_uri_encode \
        "api.version=1" \
        "cpanel_jsonapi_user=$_USER" \
        "cpanel_jsonapi_module=$MODULE" \
        "cpanel_jsonapi_func=$FUNC" \
        "cpanel_jsonapi_apiversion=3" \
        "$@") || return
    printf "?%s\n" "$PARAMS"
}

# _lk_cpanel_token_generate_name PREFIX
function _lk_cpanel_token_generate_name() {
    local HOSTNAME=${HOSTNAME-} NAME
    HOSTNAME=${HOSTNAME:-$(lk_hostname)} &&
        NAME=$1-${LK_PATH_PREFIX:-lk-}$USER@$HOSTNAME-$(lk_timestamp) &&
        NAME=$(printf '%s' "$NAME" | tr -Cs '[:alnum:]-_' '-') &&
        echo "$NAME"
}

# lk_cpanel_server_set SERVER [USER]
function lk_cpanel_server_set() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME SERVER [USER]" || return
    unset "${!_LK_CPANEL_@}"
    _LK_CPANEL_SERVER=$1
    if lk_ssh_host_exists "$1"; then
        _LK_CPANEL_METHOD=ssh
        [ $# -eq 1 ] || _LK_CPANEL_SERVER=$2@$1
    else
        _LK_CPANEL_METHOD=curl
        [ $# -ge 2 ] || lk_warn "username required for curl access" || return
    fi
    local FILE
    lk_check_user_config FILE \
        token "cpanel-${_LK_CPANEL_METHOD}-${2+$2@}$1" 00600 00700 &&
        . "$FILE" || return
    [ -s "$FILE" ] ||
        case "$_LK_CPANEL_METHOD" in
        curl)
            local NAME URL
            NAME=$(_lk_cpanel_token_generate_name "$2") &&
                URL=$(_lk_cpanel_get_url "$1" Tokens create_full_access \
                    "name=$NAME") || return
            _LK_CPANEL_TOKEN=$2:$(curl -fsSL --insecure --user "$2" "$URL" |
                jq -r '.data.token') ||
                lk_warn "unable to create API token" || return
            ;;
        esac
    lk_file_replace "$FILE" < <(lk_var_sh "${!_LK_CPANEL_@}") &&
        lk_symlink "${FILE##*/}" "${FILE%/*}/cpanel-current"
}

# _lk_cpanel_server_do_check METHOD_VAR SERVER_VAR TOKEN_VAR PREFIX
function _lk_cpanel_server_do_check() {
    local i=0 FILE _LK_STACK_DEPTH=2
    while :; do
        case "${!1-}" in
        ssh)
            [ "${!2:+1}" != 1 ] ||
                return 0
            ;;
        curl)
            [ "${!2:+1}${!3:+1}" != 11 ] ||
                return 0
            ;;
        esac
        ! ((i++)) &&
            lk_check_user_config -n FILE token "$4-current" &&
            [ -f "$FILE" ] &&
            . "$FILE" || break
    done
    lk_warn "lk_$4_server_set must be called first"
    false
}

function _lk_cpanel_server_check() {
    _lk_cpanel_server_do_check \
        _LK_CPANEL_METHOD _LK_CPANEL_SERVER _LK_CPANEL_TOKEN cpanel
}

# lk_cpanel_get MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_get() {
    [[ $# -ge 2 ]] || lk_usage "\
Usage: $FUNCNAME MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_cpanel_server_check || return
    local IFS
    unset IFS
    case "$_LK_CPANEL_METHOD" in
    ssh)
        # {"result":{"data":{}}}
        ssh "$_LK_CPANEL_SERVER" \
            uapi --output=json "$1" "$2" "${@:3}" |
            jq -cM '.result'
        ;;
    curl)
        # {"data":{}}
        local URL
        URL=$(_lk_cpanel_get_url "$_LK_CPANEL_SERVER" "$1" "$2" "${@:3}") &&
            curl -fsSL --insecure \
                -H "Authorization: cpanel $_LK_CPANEL_TOKEN" \
                "$URL"
        ;;
    esac
}

# lk_cpanel_post MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_post() {
    [[ $# -ge 2 ]] || lk_usage "\
Usage: $FUNCNAME MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_cpanel_server_check || return
    [[ $_LK_CPANEL_METHOD == curl ]] || {
        lk_cpanel_get "$@"
        return
    }
    local IFS URL ARGS
    unset IFS
    URL=$(_lk_cpanel_get_url "$_LK_CPANEL_SERVER" "$1" "$2") &&
        lk_curl_get_form_args ARGS "${@:3}" &&
        curl -fsS --insecure "${ARGS[@]}" \
            -H "Authorization: cpanel $_LK_CPANEL_TOKEN" \
            "$URL"
}

# _lk_whm_get_url SERVER FUNC [PARAMETER=VALUE...]
function _lk_whm_get_url() {
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    local SERVER=$1 FUNC=$2 \
        _LK_CPANEL_PORT=2087 _LK_CPANEL_ROOT=json-api
    shift 2
    _lk_cpanel_get_url "$SERVER" "$FUNC" "" "api.version=1" "$@"
}

# lk_whm_server_set SERVER [USER]
function lk_whm_server_set() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME SERVER [USER]" || return
    unset "${!_LK_WHM_@}"
    _LK_WHM_SERVER=$1
    if lk_ssh_host_exists "$1"; then
        _LK_WHM_METHOD=ssh
        [ $# -eq 1 ] || _LK_WHM_SERVER=$2@$1
    else
        _LK_WHM_METHOD=curl
        [ $# -ge 2 ] || lk_warn "username required for curl access" || return
    fi
    local FILE
    lk_check_user_config FILE \
        token "whm-${_LK_WHM_METHOD}-${2+$2@}$1" 00600 00700 &&
        . "$FILE" || return
    [ -s "$FILE" ] ||
        case "$_LK_WHM_METHOD" in
        curl)
            local NAME URL
            NAME=$(_lk_cpanel_token_generate_name "whm-$2") &&
                URL=$(_lk_whm_get_url "$1" api_token_create \
                    "token_name=$NAME") || return
            _LK_WHM_TOKEN=$2:$(curl -fsSL --insecure --user "$2" "$URL" |
                jq -r '.data.token') ||
                lk_warn "unable to create API token" || return
            ;;
        esac
    lk_file_replace "$FILE" < <(lk_var_sh "${!_LK_WHM_@}") &&
        lk_symlink "${FILE##*/}" "${FILE%/*}/whm-current"
}

function _lk_whm_server_check() {
    _lk_cpanel_server_do_check \
        _LK_WHM_METHOD _LK_WHM_SERVER _LK_WHM_TOKEN whm
}

# lk_whm_get FUNC [PARAMETER=VALUE...]
function lk_whm_get() {
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    local IFS
    unset IFS
    case "$_LK_WHM_METHOD" in
    ssh)
        # {"data":{}}
        ssh "$_LK_WHM_SERVER" \
            whmapi1 --output=json "$1" "${@:2}"
        ;;
    curl)
        # {"data":{}}
        local URL
        URL=$(_lk_whm_get_url "$_LK_WHM_SERVER" "$1" "${@:2}") &&
            curl -fsSL --insecure \
                -H "Authorization: whm $_LK_WHM_TOKEN" \
                "$URL"
        ;;
    esac
}

# lk_whm_post FUNC [PARAMETER=VALUE...]
function lk_whm_post() {
    [[ $# -ge 1 ]] || lk_usage "\
Usage: $FUNCNAME FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    [[ $_LK_WHM_METHOD == curl ]] || {
        lk_whm_get "$@"
        return
    }
    local IFS URL ARGS
    unset IFS
    URL=$(_lk_whm_get_url "$_LK_WHM_SERVER" "$1")
    lk_curl_get_form_args ARGS "${@:2}" &&
        curl -fsS --insecure "${ARGS[@]}" \
            -H "Authorization: whm $_LK_WHM_TOKEN" \
            "$URL"
}

# lk_cpanel_get_via_whm USER MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_get_via_whm() {
    [[ $# -ge 3 ]] || lk_usage "\
Usage: $FUNCNAME USER MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    local IFS
    unset IFS
    case "$_LK_WHM_METHOD" in
    ssh)
        # Output schema TBC
        ssh "$_LK_WHM_SERVER" \
            whmapi1 --output=json \
            uapi_cpanel \
            cpanel.user="$1" \
            cpanel.module="$2" \
            cpanel.function="$3" \
            "${@:4}"
        ;;
    curl)
        # {"result":{"data":{}}}
        local URL
        URL=$(_lk_cpanel_via_whm_get_url "$_LK_WHM_SERVER" "$1" "$2" "$3" "${@:4}") &&
            curl -fsSL --insecure \
                -H "Authorization: whm $_LK_WHM_TOKEN" \
                "$URL" |
            jq -cM '.result'
        ;;
    esac
}

# lk_cpanel_domain_list
function lk_cpanel_domain_list() {
    _lk_cpanel_server_check || return
    lk_cpanel_get DomainInfo domains_data format=list |
        jq -r '.data[] | (.domain, .serveralias) | select(. != null)' |
        tr -s '[:space:]' '\n' |
        sort -u
}

function _lk_cpanel_domain_tsv() {
    lk_jq -r 'include "core";
[ (.data.payload? // .data? // cpanel_error)[] |
    select(.type == "record" and (.record_type | in_arr(["SOA", "NS", "CAA"]) | not)) |
    .name = (.dname_b64 | @base64d) ] |
  sort_by(.record_type, .name)[] |
  [.data_b64[] | @base64d] as $data |
  if   .record_type == "MX"  then . += {"priority": $data[0], "target": $data[1]}
  elif .record_type == "SRV" then . += {"priority": $data[0], "weight": $data[1], "port": $data[2], "target": $data[3]}
  else $data[] as $data | .target = $data end |
  [.line_index, .name, .ttl, .record_type, .priority, .weight, .port, .target] | @tsv'
}

# lk_cpanel_domain_tsv DOMAIN
#
# Print tab-separated values for DNS records in the given cPanel DOMAIN:
# 1. line_index
# 2. name
# 3. ttl
# 4. record_type
# 5. priority
# 6. weight
# 7. port
# 8. target
function lk_cpanel_domain_tsv() {
    _lk_cpanel_server_check &&
        lk_cpanel_post DNS parse_zone zone="$1" | _lk_cpanel_domain_tsv
}

# lk_whm_domain_tsv DOMAIN
#
# Print tab-separated values for DNS records in the given WHM DOMAIN:
# 1. line_index
# 2. name
# 3. ttl
# 4. record_type
# 5. priority
# 6. weight
# 7. port
# 8. target
function lk_whm_domain_tsv() {
    _lk_whm_server_check &&
        lk_whm_get parse_dns_zone zone="$1" | _lk_cpanel_domain_tsv
}

# lk_cpanel_ssl_get_for_domain DOMAIN [TARGET_DIR]
function lk_cpanel_ssl_get_for_domain() {
    lk_is_fqdn "${1-}" && { [ $# -lt 2 ] || [ -d "$2" ]; } ||
        lk_usage "Usage: $FUNCNAME DOMAIN [DIR]" || return
    _lk_cpanel_server_check || return
    local DIR=${2-$PWD} JSON CERT CA KEY
    [ -w "$DIR" ] || lk_warn "directory not writable: $DIR" || return
    lk_tty_print "Retrieving TLS certificate for" "$1"
    lk_tty_detail "cPanel server:" "$_LK_CPANEL_SERVER"
    lk_mktemp_with JSON lk_cpanel_get SSL fetch_best_for_domain domain="$1" &&
        lk_mktemp_with CERT jq -r '.data.crt' "$JSON" &&
        lk_mktemp_with CA jq -r '.data.cab' "$JSON" &&
        lk_mktemp_with KEY jq -r '.data.key' "$JSON" ||
        lk_warn "unable to retrieve TLS certificate" || return
    lk_tty_print "Verifying certificate"
    lk_ssl_verify_cert "$CERT" "$KEY" "$CA" || return
    lk_tty_print "Writing certificate files"
    lk_tty_detail "Certificate and CA bundle:" "$(lk_tty_path "$DIR/$1.cert")"
    lk_tty_detail "Private key:" "$(lk_tty_path "$DIR/$1.key")"
    lk_install -m 00644 "$DIR/$1.cert" &&
        lk_install -m 00640 "$DIR/$1.key" &&
        lk_file_replace -b "$DIR/$1.cert" < <(cat "$CERT" "$CA") &&
        lk_file_replace -bf "$KEY" "$DIR/$1.key"
}

function _lk_dirty_check() {
    local DIR=$LK_BASE/var/lib/lk-platform/dirty
    [[ -d $DIR ]] && [[ -w $DIR ]] ||
        lk_warn "not a writable directory: $DIR"
}

function _lk_dirty_check_scope() {
    [[ $1 =~ ^[^/]+$ ]] ||
        lk_warn "invalid scope: $1" || return
    FILE=$LK_BASE/var/lib/lk-platform/dirty/$1
}

# lk_is_dirty SCOPE...
#
# Return true if any SCOPE has been marked dirty.
function lk_is_dirty() {
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" || return
        shift
        [[ -f $FILE ]] || continue
        return
    done
    false
}

# lk_mark_dirty SCOPE...
#
# Mark each SCOPE as dirty.
function lk_mark_dirty() {
    _lk_dirty_check || return
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" &&
            ({ [[ ! -g ${FILE%/*} ]] || umask 002; } && touch "$FILE") ||
            lk_warn "unable to mark dirty: $1" || return
        shift
    done
}

# lk_mark_clean SCOPE...
#
# Mark each SCOPE as clean.
function lk_mark_clean() {
    _lk_dirty_check || return
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" &&
            rm -f "$FILE" ||
            lk_warn "unable to mark clean: $1" || return
        shift
    done
}

# lk_symlink_bin TARGET [ALIAS]
function lk_symlink_bin() {
    local TARGET LINK EXIT_STATUS vv='' \
        BIN_PATH=${LK_BIN_PATH:-/usr/local/bin} _PATH=:$PATH:
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME TARGET [ALIAS]"
    ! lk_verbose 2 || vv=v
    set -- "$1" "${2:-${1##*/}}"
    TARGET=$1
    LINK=${BIN_PATH%/}/$2
    # Don't search in BIN_PATH if the target and symlink have the same basename
    [ "${TARGET##*/}" != "${LINK##*/}" ] ||
        _PATH=${_PATH//":$BIN_PATH:"/:}
    # Don't search in ~ unless BIN_PATH is in ~
    [ "${BIN_PATH#~}" != "$BIN_PATH" ] ||
        _PATH=$(sed -E "s/:$(lk_escape_ere ~)[^:]*:/:/g" <<<"$_PATH")
    _PATH=${_PATH:1:${#_PATH}-2}
    { [[ $TARGET == /* ]] ||
        TARGET=$(PATH=$_PATH type -P "$TARGET"); } &&
        lk_symlink "$TARGET" "$LINK" &&
        return 0 || EXIT_STATUS=$?
    [ ! -L "$LINK" ] || [ -x "$LINK" ] ||
        lk_maybe_sudo rm -f"$vv" -- "$LINK" || true
    return "$EXIT_STATUS"
}

function lk_configure_locales() {
    local IFS LK_SUDO=1 LOCALES _LOCALES FILE _FILE
    unset IFS
    lk_is_linux || lk_warn "platform not supported" || return
    LOCALES=(${LK_NODE_LOCALES-} en_US.UTF-8)
    _LOCALES=$(lk_arr LOCALES |
        lk_escape_ere |
        lk_implode_input "|")
    [ ${#LOCALES[@]} -lt 2 ] || _LOCALES="($_LOCALES)"
    FILE=${_LK_PROVISION_ROOT-}/etc/locale.gen
    # 1. Comment all locales out
    # 2. Uncomment configured locales
    _FILE=$(sed -E \
        -e "s/^$S*#?/#/" \
        -e "s/^#($_LOCALES.*)/\\1/" \
        "$FILE") || return
    unset LK_FILE_REPLACE_NO_CHANGE
    lk_file_keep_original "$FILE" &&
        lk_file_replace -i "^$S*(#|\$)" "$FILE" "$_FILE" || return
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        [ -n "${_LK_PROVISION_ROOT-}" ] ||
        lk_elevate locale-gen || return

    FILE=${_LK_PROVISION_ROOT-}/etc/locale.conf
    lk_install -m 00644 "$FILE"
    lk_file_replace -i "^(#|$S*\$)" "$FILE" "\
LANG=${LOCALES[0]}${LK_NODE_LANGUAGE:+
LANGUAGE=$LK_NODE_LANGUAGE}"
}

# lk_dir_set_modes DIR REGEX DIR_MODE FILE_MODE [REGEX DIR_MODE FILE_MODE]...
function lk_dir_set_modes() {
    local DIR REGEX LOG_FILE i TYPE MODE ARGS CHANGES _CHANGES TOTAL=0 \
        _PRUNE _EXCLUDE MATCH=() DIR_MODE=() FILE_MODE=() PRUNE=() LK_USAGE
    LK_USAGE="\
Usage: $FUNCNAME DIR REGEX DIR_MODE FILE_MODE [REGEX DIR_MODE FILE_MODE]..."
    [ $# -ge 4 ] && ! ((($# - 1) % 3)) || lk_usage || return
    lk_maybe_sudo test -d "$1" || lk_warn "not a directory: $1" || return
    DIR=$(lk_realpath "$1") || return
    shift
    while [ $# -gt 0 ]; do
        [[ $2 =~ ^(\+?[0-7]+)?$ ]] || lk_warn "invalid mode: $2" || return
        [[ $3 =~ ^(\+?[0-7]+)?$ ]] || lk_warn "invalid mode: $3" || return
        REGEX=${1%/}
        [ -n "$REGEX" ] || REGEX=".*"
        [ "$REGEX" != "$1" ] || [ "${REGEX%.\*}" != "$1" ] ||
            REGEX="$REGEX(/.*)?"
        MATCH+=("$REGEX")
        DIR_MODE+=("$2")
        FILE_MODE+=("$3")
        PRUNE+=("${1%/}")
        shift 3
    done
    LOG_FILE=$(lk_mktemp_file) || return
    ! lk_verbose || lk_tty_print \
        "Updating file modes in $(lk_tty_path "$DIR")"
    for i in "${!MATCH[@]}"; do
        [ -n "${DIR_MODE[$i]:+1}${FILE_MODE[$i]:+1}" ] || continue
        ! lk_verbose 2 || lk_tty_print "Checking:" "${MATCH[$i]}"
        CHANGES=0
        for TYPE in DIR_MODE FILE_MODE; do
            MODE=${TYPE}"[$i]"
            MODE=${!MODE}
            [ -n "$MODE" ] || continue
            ! lk_verbose 2 || lk_tty_detail "$([ "$TYPE" = DIR_MODE ] &&
                echo Directory ||
                echo File) mode:" "$MODE"
            ARGS=(-regextype posix-egrep)
            _PRUNE=(
                "${PRUNE[@]:$((i + 1)):$((${#PRUNE[@]} - (i + 1)))}"
            )
            [ ${#_PRUNE[@]} -eq 0 ] ||
                ARGS+=(! \(
                    -type d
                    -regex "$(lk_regex_implode "${_PRUNE[@]}")"
                    -prune \))
            ARGS+=(-type "$(lk_lower "${TYPE:0:1}")")
            [ "$TYPE" = DIR_MODE ] || {
                _EXCLUDE=(
                    "${MATCH[@]:$((i + 1)):$((${#MATCH[@]} - (i + 1)))}"
                )
                [ ${#_EXCLUDE[@]} -eq 0 ] ||
                    ARGS+=(
                        ! -regex "$(lk_regex_implode "${_EXCLUDE[@]}")"
                    )
            }
            ARGS+=(! -perm "${MODE//+/-}" -regex "${MATCH[$i]}" -print0)
            _CHANGES=$(bash -c 'cd "$1" &&
    gnu_find . "${@:3}" |
    gnu_xargs -0r gnu_chmod -c "$2"' bash "$DIR" "$MODE" "${ARGS[@]}" |
                tee -a "$LOG_FILE" | wc -l) || return
            ((CHANGES += _CHANGES)) || true
        done
        ! lk_verbose 2 || lk_tty_detail "Changes:" "$LK_BOLD$CHANGES"
        ((TOTAL += CHANGES)) || true
    done
    ! lk_verbose && ! ((TOTAL)) ||
        $(lk_verbose &&
            echo "lk_tty_print" ||
            echo "lk_tty_detail") \
            "$TOTAL file $(lk_plural \
                "$TOTAL" mode modes) updated$(lk_verbose ||
                    echo " in $(lk_tty_path "$DIR")")"
    ! ((TOTAL)) &&
        lk_delete_on_exit "$LOG_FILE" ||
        lk_tty_detail "Changes logged to:" "$LOG_FILE"
}

# lk_ssh_set_option OPTION VALUE [FILE]
function lk_ssh_set_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1 $2" \
        "^$S*$OPTION($S+|$S*=$S*)$VALUE$S*\$" \
        "^$S*$OPTION($S+|$S*=).*" \
        "^$S*#"{,"$S","$S*"}"$OPTION($S+|$S*=).*"
}

function lk_ssh_list_hosts() {
    local IFS FILES=(~/.ssh/config) COUNT=0 HOST
    while [ "$COUNT" -lt ${#FILES[@]} ]; do
        COUNT=${#FILES[@]}
        IFS=$'\n'
        FILES=(
            "${FILES[@]}"
            $(INCLUDE="[iI][nN][cC][lL][uU][dD][eE]" &&
                grep -Eh \
                    "^$S*$INCLUDE($S+(\"[^\"]*\"|[^\"]+))+$S*\$" \
                    "${FILES[@]}" 2>/dev/null |
                sed -E \
                    -e "s/^$S*$INCLUDE$S+(.+)$S*\$/\\1/" \
                    -e "s/$S+/\n/g" |
                    sed -E 's/^("?)([^~/])/\1~\/.ssh\/\2/')
        ) || true
        unset IFS
        lk_expand_paths FILES &&
            lk_remove_missing FILES &&
            lk_resolve_files FILES || return
    done
    [ ${#FILES[@]} -eq 0 ] || {
        HOST="[hH][oO][sS][tT]"
        grep -Eh \
            "^$S*$HOST($S+(\"[^\"]*\"|[^\"]+))+$S*\$" \
            "${FILES[@]}" 2>/dev/null |
            sed -E \
                -e "s/^$S*$HOST$S+(.+)$S*\$/\\1/" \
                -e "s/$S+/\n/g" |
            sed -E \
                -e 's/"(.+)"/\1/g' \
                -e "/[*?]/d" |
            sort -u
    }
}

function lk_ssh_host_exists() {
    [ -n "${1-}" ] &&
        lk_ssh_list_hosts | grep -Fx "$1" >/dev/null
}

function lk_ssh_get_host_key_files() {
    local KEY_FILE
    [ -n "${1-}" ] || lk_warn "no ssh host" || return
    lk_ssh_host_exists "$1" || lk_warn "ssh host not found: $1" || return
    KEY_FILE=$(ssh -G "$1" |
        awk '/^identityfile / { print $2 }' |
        lk_expand_path |
        lk_filter 'test -f') &&
        [ -n "$KEY_FILE" ] &&
        echo "$KEY_FILE"
}

# lk_ssh_get_public_key [KEY_FILE]
#
# Read a private or public OpenSSH key from KEY_FILE or input and output an
# OpenSSH public key.
function lk_ssh_get_public_key() {
    local KEY KEY_FILE EXIT_STATUS=0
    if [ $# -eq 0 ]; then
        KEY=$(cat) || return
    elif [ "$1" = "${1%.pub}" ] &&
        [ -f "$1.pub" ] &&
        KEY=$(lk_ssh_get_public_key "$1.pub" 2>/dev/null); then
        echo "$KEY"
        return 0
    else
        [ -f "$1" ] || lk_warn "file not found: $1" || return
        KEY=$(cat <"$1") || return
    fi
    if ssh-keygen -l -f <(cat <<<"$KEY") &>/dev/null; then
        echo "$KEY"
    else
        # ssh-keygen doesn't allow fingerprinting from a file descriptor
        KEY_FILE=$(lk_mktemp_file) &&
            lk_delete_on_exit "$KEY_FILE" &&
            cat <<<"$KEY" >"$KEY_FILE" || return
        ssh-keygen -y -f "$KEY_FILE" || EXIT_STATUS=$?
        rm -f "$KEY_FILE" || true
        return "$EXIT_STATUS"
    fi
}

# lk_ssh_add_host [-t] NAME HOST[:PORT] USER [KEY_FILE [JUMP_HOST_NAME]]
#
# Configure access to the given SSH host by creating or updating
# ~/.ssh/{PREFIX}config.d/60-NAME. If -t is set, test reachability first.
#
# Notes:
# - KEY_FILE can be relative to ~/.ssh or ~/.ssh/{PREFIX}keys
# - If KEY_FILE is -, the key will be read from standard input and written to
#   ~/.ssh/{PREFIX}keys/NAME
# - LK_SSH_PREFIX is removed from the start of NAME and JUMP_HOST_NAME to ensure
#   it's not added twice
function lk_ssh_add_host() {
    local NAME HOST SSH_USER KEY_FILE JUMP_HOST_NAME PORT='' \
        h=${LK_SSH_HOME:-~} SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX} \
        LK_FILE_BACKUP_TAKE='' LK_VERBOSE=0 \
        KEY JUMP_ARGS JUMP_PORT CONF CONF_FILE TEST=
    [ "${1-}" != -t ] || { TEST=1 && shift; }
    NAME=$1
    HOST=$2
    SSH_USER=$3
    KEY_FILE=${4-}
    JUMP_HOST_NAME=${5-}
    [ $# -ge 3 ] || lk_usage "\
Usage: $FUNCNAME [-t] NAME HOST[:PORT] USER [KEY_FILE [JUMP_HOST_NAME]]" ||
        return
    NAME=${NAME#"$SSH_PREFIX"}
    [ "${KEY_FILE:--}" = - ] ||
        [ -f "$KEY_FILE" ] ||
        [ -f "$h/.ssh/$KEY_FILE" ] ||
        { [ -f "$h/.ssh/${SSH_PREFIX}keys/$KEY_FILE" ] &&
            KEY_FILE=$h/.ssh/${SSH_PREFIX}keys/$KEY_FILE; } ||
        # If KEY_FILE doesn't exist but matches the regex below, check
        # ~/.ssh/authorized_keys for exactly one public key with the comment
        # field set to KEY_FILE
        { [[ $KEY_FILE =~ ^[-a-zA-Z0-9_]+$ ]] && { KEY=$(grep -E \
            "$S$KEY_FILE\$" "$h/.ssh/authorized_keys" 2>/dev/null) &&
            [ "$(wc -l <<<"$KEY")" -eq 1 ] &&
            KEY_FILE=- || KEY_FILE=; }; } ||
        lk_warn "$KEY_FILE: file not found" || return
    [ ! "$KEY_FILE" = - ] || {
        KEY=${KEY:-$(cat)}
        KEY_FILE=$h/.ssh/${SSH_PREFIX}keys/$NAME
        lk_install -m 00600 "$KEY_FILE" &&
            lk_file_replace "$KEY_FILE" "$KEY" || return
        ssh-keygen -l -f "$KEY_FILE" &>/dev/null || {
            # `ssh-keygen -l -f FILE` exits without error if FILE contains an
            # OpenSSH public key
            lk_tty_log "Reading $KEY_FILE to create public key file"
            KEY=$(unset DISPLAY && ssh-keygen -y -f "$KEY_FILE") &&
                lk_install -m 00600 "$KEY_FILE.pub" &&
                lk_file_replace "$KEY_FILE.pub" "$KEY" || return
        }
    }
    [[ ! $HOST =~ (.*):([0-9]+)$ ]] || {
        HOST=${BASH_REMATCH[1]}
        PORT=${BASH_REMATCH[2]}
    }
    JUMP_HOST_NAME=${JUMP_HOST_NAME:+$SSH_PREFIX${JUMP_HOST_NAME#"$SSH_PREFIX"}}
    ! lk_is_true TEST || {
        if [ -z "$JUMP_HOST_NAME" ]; then
            lk_ssh_is_reachable "$HOST" "${PORT:-22}"
        else
            JUMP_ARGS=(
                -o ConnectTimeout=5
                -o ControlMaster=auto
                -o ControlPath="/tmp/.${FUNCNAME}_%C-%u"
                -o ControlPersist=120
            )
            ssh -O check "${JUMP_ARGS[@]}" "$JUMP_HOST_NAME" 2>/dev/null ||
                ssh -fN "${JUMP_ARGS[@]}" "$JUMP_HOST_NAME" ||
                lk_warn "could not connect to jump host: $JUMP_HOST_NAME" ||
                return
            JUMP_PORT=9999
            while :; do
                JUMP_PORT=$(lk_tcp_next_port $((JUMP_PORT + 1))) || return
                [ "$JUMP_PORT" -le 10999 ] ||
                    lk_warn "could not establish tunnel to $HOST:${PORT:-22}" ||
                    return
                ! ssh -O forward -L "$JUMP_PORT:$HOST:${PORT:-22}" \
                    "${JUMP_ARGS[@]}" "$JUMP_HOST_NAME" &>/dev/null ||
                    break
            done
            lk_ssh_is_reachable localhost "$JUMP_PORT"
        fi || lk_warn "host not reachable: $HOST:${PORT:-22}" || return
    }
    CONF=$(
        h=${h//\//\\\/}
        KEY_FILE=${KEY_FILE//$h/"~"}
        cat <<EOF
Host            $SSH_PREFIX$NAME
HostName        $HOST${PORT:+
Port            $PORT}${SSH_USER:+
User            $SSH_USER}${KEY_FILE:+
IdentityFile    "$KEY_FILE"}${JUMP_HOST_NAME:+
ProxyJump       $SSH_PREFIX${JUMP_HOST_NAME#"$SSH_PREFIX"}}
EOF
    )
    CONF_FILE=$h/.ssh/${SSH_PREFIX}config.d/${LK_SSH_PRIORITY:-60}-$NAME
    lk_install -m 00600 "$CONF_FILE" &&
        lk_file_replace "$CONF_FILE" "$CONF" || return
}

# lk_ssh_is_reachable HOST PORT [TIMEOUT_SECONDS]
function lk_ssh_is_reachable() {
    { echo QUIT | nc -w "${3:-5}" "$1" "$2" | head -n1 |
        grep -E "^SSH-[^[:blank:]-]+-[^[:blank:]-]+" >/dev/null; } \
        2>/dev/null
}

# lk_ssh_configure [JUMP_HOST[:JUMP_PORT] JUMP_USER [JUMP_KEY_FILE]]
function lk_ssh_configure() {
    local JUMP_HOST=${1-} JUMP_USER=${2-} JUMP_KEY_FILE=${3-} \
        SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX} \
        LK_FILE_BACKUP_TAKE='' LK_VERBOSE=0 \
        KEY PATTERN CONF AWK OWNER GROUP TEMP_HOMES \
        HOMES=(${_LK_HOMES[@]+"${_LK_HOMES[@]}"}) h
    unset KEY
    [ $# -eq 0 ] || [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    [ ${#HOMES[@]} -gt 0 ] || HOMES=(~)
    [ ${#HOMES[@]} -le 1 ] ||
        [ ! "$JUMP_KEY_FILE" = - ] ||
        KEY=$(cat)

    # Prepare awk command that adds "Include ~/.ssh/lk-config.d/*" to
    # ~/.ssh/config, or replaces an equivalent entry
    PATTERN="(~/\\.ssh/)?${SSH_PREFIX}config\\.d/\\*"
    PATTERN="(\"$PATTERN\"|$PATTERN)"
    PATTERN="^$S*[iI][nN][cC][lL][uU][dD][eE]$S+$PATTERN$S*\$"
    PATTERN=${PATTERN//\\/\\\\}
    CONF="Include ~/.ssh/${SSH_PREFIX}config.d/*"
    AWK=(awk
        -f "$LK_BASE/lib/awk/update-ssh-config.awk"
        -v "SSH_PATTERN=$PATTERN"
        -v "SSH_CONFIG=$CONF")

    for h in "${HOMES[@]}"; do
        [ ! -e "$h/.${LK_PATH_PREFIX}ignore" ] &&
            [ ! -e "$h/.ssh/.${LK_PATH_PREFIX}ignore" ] || continue
        if [[ $h == ~ ]]; then
            OWNER=$USER
        elif [[ $h =~ ^/etc/skel(\.${LK_PATH_PREFIX%-})?$ ]]; then
            OWNER=root
        else
            [ -n "${TEMP_HOMES-}" ] ||
                lk_mktemp_with TEMP_HOMES lk_list_user_homes || return
            OWNER=$(lk_require_output \
                awk -v "h=$h" '$2 == h {print $1; exit}' "$TEMP_HOMES") ||
                lk_warn "invalid home directory: $h" || continue
        fi
        GROUP=$(id -gn "$OWNER") || return
        # Create directories in ~/.ssh, or reset modes and ownership of existing
        # directories
        install -d -m 00700 -o "$OWNER" -g "$GROUP" \
            "$h/.ssh"{,"/$SSH_PREFIX"{config.d,keys}} ||
            return
        # Add "Include ~/.ssh/lk-config.d/*" to ~/.ssh/config, or replace an
        # equivalent entry
        [ -e "$h/.ssh/config" ] ||
            install -m 00600 -o "$OWNER" -g "$GROUP" \
                /dev/null "$h/.ssh/config" ||
            return
        lk_file_replace -l "$h/.ssh/config" "$("${AWK[@]}" "$h/.ssh/config")"
        # Add defaults for all lk-* hosts to ~/.ssh/lk-config.d/90-defaults
        CONF=$(
            cat <<EOF
Host                    ${SSH_PREFIX}*
IdentitiesOnly          yes
ForwardAgent            yes
StrictHostKeyChecking   accept-new
ControlMaster           auto
ControlPath             /tmp/ssh_%C-%u
ControlPersist          120
SendEnv                 LC_BYOBU
ServerAliveInterval     30
EOF
        )
        lk_file_replace "$h/.ssh/${SSH_PREFIX}config.d/90-defaults" "$CONF"
        # Add jump proxy configuration
        [ $# -lt 2 ] ||
            LK_SSH_HOME=$h LK_SSH_PRIORITY=40 \
                lk_ssh_add_host \
                "jump" \
                "$JUMP_HOST" \
                "$JUMP_USER" \
                "$JUMP_KEY_FILE" ${KEY+<<<"$KEY"}
        (
            shopt -s nullglob
            chmod 00600 \
                "$h/.ssh/"{config,"$SSH_PREFIX"{config.d,keys}/*}
            ! lk_root ||
                chown "$OWNER:$GROUP" \
                    "$h/.ssh/"{config,"$SSH_PREFIX"{config.d,keys}/*}
        )
    done
}

function _lk_hosts_file_add() {
    lk_mktemp_with TEMP awk \
        -v replace="$REPLACE" \
        -v block="$BLOCK" \
        -v block_re="${BLOCK_RE//\\/\\\\}" '
BEGIN {
  S  = "[[:blank:]]"
  re = S "*##" S "*" block_re S "*##" S "*$"
}
replace && FILENAME != "-" && $0 ~ re {
  next
}
FILENAME == "-" || $0 ~ re {
  gsub("(^" S "+|" re ")", "")
  if (!$0) { next }
  gsub(S "+", " ")
  if (!seen[$0]++) {
    max_length  = length > max_length ? length : max_length
    blocks[i++] = $0
  }
  next
}
$0 ~ "^" S "*$" {
  last_blank = 1
  next
}
{
  if (last_blank && printed) { print "" }
  last_blank = 0
  print $0
  printed++
}
END {
  if (i) { print "" }
  for (i in blocks) {
    printf("%-" (max_length + 1) "s## %s ##\n", blocks[i], block)
  }
}' /etc/hosts -
}

# lk_hosts_file_add [-r] [-b <BLOCK>] [<IP> <NAME>...]
#
# Add '<IP> <NAME>... ## <BLOCK> ##' to `/etc/hosts`. If no host arguments are
# given, read entries from input, one per line. If -r is set, remove existing
# entries with a matching <BLOCK>, otherwise move matching entries to the end of
# the file and remove any duplicates.
#
# The default value of <BLOCK> is the caller's name.
function lk_hosts_file_add() {
    local REPLACE=0 BLOCK BLOCK_RE TEMP FILE=/etc/hosts
    while [[ ${1-} == -[br] ]]; do
        [[ $1 != -r ]] || { REPLACE=1 && shift; }
        [[ $1 != -b ]] || { BLOCK=$2 && shift 2; }
    done
    BLOCK=${BLOCK:-$(lk_caller_name)} &&
        BLOCK_RE=$(lk_ere_escape "$BLOCK") || return
    if (($#)); then
        _lk_hosts_file_add < <(echo "$@")
    else
        _lk_hosts_file_add
    fi || return
    if [[ -w $FILE ]]; then
        local LK_SUDO
    elif lk_can_sudo install; then
        local LK_SUDO=1
    else
        lk_tty_print "You do not have permission to edit" "$FILE"
        lk_tty_detail "Updated hosts file written to:" "$TEMP"
        lk_delete_on_exit_withdraw "$TEMP"
        return
    fi
    lk_file_replace -f "$TEMP" "$FILE"
}

function _lk_node_ip() {
    local i PRIVATE=("${@:2}") IP
    IP=$(if lk_command_exists ip; then
        ip address show
    else
        # See parse-ifconfig.awk for macOS output examples
        ifconfig |
            sed -E 's/ (prefixlen |netmask (0xf*[8ce]?0*( |$)))/\/\2/'
    fi | awk \
        -f "$LK_BASE/lib/awk/parse-ifconfig.awk" \
        -v "ADDRESS_FAMILY=$1" |
        sed -E 's/%[^/]+\//\//') || return
    {
        grep -Ev "^$(lk_regex_implode "${PRIVATE[@]}")" <<<"$IP" || true
        lk_is_true _LK_IP_PUBLIC_ONLY ||
            for i in "${PRIVATE[@]}"; do
                grep -E "^$i" <<<"$IP" || true
            done
    } | if lk_is_true _LK_IP_KEEP_PREFIX; then
        cat
    else
        sed -E 's/\/[0-9]+$//'
    fi
}

function lk_node_ipv4() {
    _lk_node_ip inet \
        '10\.' '172\.(1[6-9]|2[0-9]|3[01])\.' '192\.168\.' '127\.' |
        sed -E '/^169\.254\./d'
}

function lk_node_ipv6() {
    _lk_node_ip inet6 "f[cd]" "fe80::" "::1/128"
}

function lk_node_public_ipv4() {
    local IP
    {
        ! IP=$(dig +noall +answer +short @1.1.1.1 \
            whoami.cloudflare TXT CH | sed -E 's/^"(.*)"$/\1/') || echo "$IP"
        _LK_IP_PUBLIC_ONLY=1 lk_node_ipv4
    } | sort -u
}

function lk_node_public_ipv6() {
    local IP
    {
        ! IP=$(dig +noall +answer +short @2606:4700:4700::1111 \
            whoami.cloudflare TXT CH | sed -E 's/^"(.*)"$/\1/') || echo "$IP"
        _LK_IP_PUBLIC_ONLY=1 lk_node_ipv6
    } | sort -u
}

# lk_node_is_host DOMAIN
#
# Return true if at least one public IP address matches an authoritative A or
# AAAA record for DOMAIN.
function lk_node_is_host() {
    local IFS NODE_IP HOST_IP
    unset IFS
    lk_require_output -q lk_dns_resolve_hosts -d "$1" ||
        lk_warn "domain not found: $1" || return
    NODE_IP=($(lk_node_public_ipv4 && lk_node_public_ipv6)) &&
        [ ${#NODE_IP} -gt 0 ] ||
        lk_warn "public IP address not found" || return
    HOST_IP=($(lk_dns_resolve_name_from_ns "$1")) ||
        lk_warn "unable to retrieve authoritative DNS records for $1" || return
    lk_require_output -q comm -12 \
        <(lk_arr HOST_IP | sort -u) \
        <(lk_arr NODE_IP | sort -u)
}

if lk_is_macos; then
    function lk_tcp_listening_ports() {
        netstat -nap tcp |
            awk '$NF == "LISTEN" { sub(".*\\.", "", $4); print $4 }' |
            sort -nu
    }
else
    function lk_tcp_listening_ports() {
        ss -nH --listening --tcp |
            awk '{ sub(".*:", "", $4); print $4 }' |
            sort -nu
    }
fi

# lk_tcp_next_port [FIRST_PORT]
function lk_tcp_next_port() {
    lk_tcp_listening_ports |
        awk -v "p=${1:-10000}" \
            'p>$1{next} p==$1{p++;next} {exit} END{print p}'
}

# lk_tcp_is_reachable HOST PORT [TIMEOUT_SECONDS]
function lk_tcp_is_reachable() {
    nc -z -w "${3:-5}" "$1" "$2" &>/dev/null
}

function _lk_option_check() {
    { { [ $# -gt 0 ] &&
        echo -n "$1" ||
        lk_maybe_sudo cat "$FILE"; } |
        grep -E "$CHECK_REGEX"; } &>/dev/null
}

function _lk_option_do_replace() {
    [ -z "${SECTION-}" ] || { __FILE=$(awk \
        -v "SECTION=$SECTION" \
        -v "ENTRIES=$__FILE" \
        -f "$(lk_awk_dir)/section-replace.awk" \
        "$FILE" && printf .) && __FILE=${__FILE%.}; } || return
    lk_file_keep_original "$FILE" &&
        lk_file_replace -l "$FILE" "$__FILE"
}

# lk_option_set [-s SECTION] [-p] FILE SETTING CHECK_REGEX [REPLACE_REGEX...]
#
# If CHECK_REGEX doesn't match any lines in FILE, replace each REPLACE_REGEX
# match with SETTING until there's a match for CHECK_REGEX. If there is still no
# match, append SETTING to FILE.
#
# If -s is set, ignore lines before and after SECTION, where each section starts
# with the line "[SECTION_NAME]".
#
# If -p is set, pass each REPLACE_REGEX to sed as-is, otherwise escape SETTING
# and pass "0,/REPLACE_REGEX/{s/REGEX/SETTING/}".
function lk_option_set() {
    local OPTIND OPTARG OPT LK_USAGE FILE SETTING CHECK_REGEX REPLACE_WITH \
        PRESERVE SECTION _FILE __FILE
    unset PRESERVE __FILE
    LK_USAGE="\
Usage: $FUNCNAME [-s SECTION] [-p] FILE SETTING CHECK_REGEX [REPLACE_REGEX...]"
    while getopts ":s:p" OPT; do
        case "$OPT" in
        s)
            SECTION=$OPTARG
            ;;
        p)
            PRESERVE=
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -ge 3 ] || lk_usage || return
    FILE=$1
    SETTING=$2
    CHECK_REGEX=$3
    ! _lk_option_check || return 0
    lk_maybe_sudo test -e "$FILE" ||
        { lk_install -d -m 00755 "${FILE%/*}" &&
            lk_install -m 00644 "$FILE"; } || return
    lk_maybe_sudo test -f "$FILE" || lk_warn "file not found: $FILE" || return
    if [ -z "${SECTION-}" ]; then
        lk_file_get_text "$FILE" _FILE
    else
        _FILE=$(awk \
            -v "section=$SECTION" \
            -f "$(lk_awk_dir)/section-get.awk" \
            "$FILE")$'\n'
    fi || return
    [ "${PRESERVE+1}" = 1 ] ||
        REPLACE_WITH=$(lk_escape_ere_replace "$SETTING")
    shift 3
    for REGEX in "$@"; do
        __FILE=$(gnu_sed -E \
            ${PRESERVE+"$REGEX"} \
            ${PRESERVE-"0,/$REGEX/{s/$REGEX/$REPLACE_WITH/}"} \
            <<<"${__FILE-$_FILE}.") && __FILE=${__FILE%.} || return
        ! _lk_option_check "$__FILE" || {
            _lk_option_do_replace && return 0 || return
        }
    done
    # Use a clean copy of FILE in case of buggy regex, and add a newline to work
    # around slow expansion of ${CONTENT%$'\n'}
    __FILE=$_FILE$SETTING$'\n'
    _lk_option_do_replace
}

# lk_conf_set_option [-s SECTION] OPTION VALUE [FILE]
function lk_conf_set_option() {
    local SECTION OPTION VALUE DELIM FILE
    unset SECTION
    [ "${1-}" != -s ] || { SECTION=$2 && shift 2 || return; }
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    DELIM=$(lk_escape_ere "$(lk_trim <<<"${_LK_CONF_DELIM-=}")")
    DELIM=${DELIM:-$_LK_CONF_DELIM}
    FILE=${3:-$LK_CONF_OPTION_FILE}
    lk_option_set ${SECTION+-s "$SECTION"} \
        "$FILE" \
        "$1${_LK_CONF_DELIM-=}$2" \
        "^$S*$OPTION$S*$DELIM$S*$VALUE$S*\$" \
        "^$S*$OPTION$S*$DELIM.*" \
        "^$S*#"{,"$S","$S*"}"$OPTION$S*$DELIM.*"
}

# lk_conf_enable_row [-s SECTION] ROW [FILE]
function lk_conf_enable_row() {
    local SECTION ROW FILE
    unset SECTION
    [ "${1-}" != -s ] || { SECTION=$2 && shift 2 || return; }
    ROW=$(lk_regex_expand_whitespace "$(lk_escape_ere "$1")")
    FILE=${2:-$LK_CONF_OPTION_FILE}
    lk_option_set ${SECTION+-s "$SECTION"} \
        "$FILE" \
        "$1" \
        "^$ROW\$" \
        "^$S*$ROW$S*\$" \
        "^$S*#"{,"$S","$S*"}"$ROW$S*\$"
}

# lk_conf_remove_row [-s SECTION] ROW [FILE]
function lk_conf_remove_row() {
    local SECTION ROW FILE __FILE
    unset SECTION
    [ "${1-}" != -s ] || { SECTION=$2 && shift 2 || return; }
    ROW=$(lk_regex_expand_whitespace "$(lk_escape_ere "$1")")
    FILE=${2:-$LK_CONF_OPTION_FILE}
    if [ -z "${SECTION-}" ]; then
        lk_file_get_text "$FILE" __FILE
    else
        __FILE=$(awk \
            -v "section=$SECTION" \
            -f "$(lk_awk_dir)/section-get.awk" \
            "$FILE")$'\n'
    fi || return
    __FILE=$(sed -E "/^$S*$ROW$S*\$/d" <<<"$__FILE") &&
        _lk_option_do_replace
}

# lk_php_set_option OPTION VALUE [FILE]
function lk_php_set_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1=$2" \
        "^$S*$OPTION$S*=$S*$VALUE$S*\$" \
        "^$S*$OPTION$S*=.*" \
        "^$S*;"{,"$S","$S*"}"$OPTION$S*=.*"
}

# lk_php_enable_option OPTION VALUE [FILE]
function lk_php_enable_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1=$2" \
        "^$S*$OPTION$S*=$S*$VALUE$S*\$" \
        "^$S*;"{,"$S","$S*"}"$OPTION$S*=$S*$VALUE$S*\$"
}

# lk_httpd_set_option OPTION VALUE [FILE]
function lk_httpd_set_option() {
    local OPTION VALUE REPLACE_WITH FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    REPLACE_WITH=$(lk_escape_ere_replace "$1 $2")
    lk_option_set -p "$FILE" \
        "$1 $2" \
        "^$S*$OPTION$S+$VALUE$S*\$" \
        "0,/^$S*$OPTION$S+.*/{s/^($S*)$OPTION$S+.*/\\1$REPLACE_WITH/}" \
        "0,/^$S*#"{,"$S","$S*"}"$OPTION$S+.*/{s/^($S*)#$S*$OPTION$S+.*/\\1$REPLACE_WITH/}"
}

# lk_httpd_enable_option OPTION VALUE [FILE]
function lk_httpd_enable_option() {
    local OPTION VALUE REPLACE_WITH FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    REPLACE_WITH=$(lk_escape_ere_replace "$1 $2")
    lk_option_set -p "$FILE" \
        "$1 $2" \
        "^$S*$OPTION$S+$VALUE$S*\$" \
        "0,/^$S*#"{,"$S","$S*"}"$OPTION$S+$VALUE$S*\$/{s/^($S*)#$S*$OPTION$S+$VALUE$S*\$/\\1$REPLACE_WITH/}"
}

# lk_httpd_remove_option OPTION VALUE [FILE]
function lk_httpd_remove_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE} _FILE
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    _FILE=$(sed -E "/^$S*$OPTION$S+$VALUE$S*\$/d" "$FILE") &&
        lk_file_replace -l "$FILE" "$_FILE"
}

# lk_squid_set_option OPTION VALUE [FILE]
function lk_squid_set_option() {
    local OPTION VALUE REPLACE_WITH REGEX FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    REPLACE_WITH=$(lk_escape_ere_replace "$1 $2")
    REGEX="$OPTION($S+([^#[:space:]]|#$NS)$NS*)*($S+#$S+.*)?"
    lk_option_set -p "$FILE" \
        "$1 $2" \
        "^$S*$OPTION$S+$VALUE($S*\$|$S+#$S+)" \
        "0,/^$S*$REGEX\$/{s/^($S*)$REGEX\$/\\1$REPLACE_WITH\\4/}" \
        "0,/^$S*#"{,"$S","$S*"}"$REGEX\$/{s/^($S*)#$REGEX\$/\\1$REPLACE_WITH\\4/}"
}

# lk_check_user_config [-n] VAR DIR FILE [FILE_MODE [DIR_MODE]]
#
# Create or update permissions on a user-specific config file and assign its
# path to VAR in the caller's scope. If -n is set, don't create the file (useful
# for setting VAR only). DIR may be the empty string.
function lk_check_user_config() {
    local _INSTALL=1
    [ "${1-}" != -n ] || { _INSTALL= && shift; }
    local _FILE_MODE=${4-} _DIR_MODE=${5-}
    eval "$1=\${XDG_CONFIG_HOME:-~/.config}/lk-platform/${2:+\$2/}\$3"
    [ -z "$_INSTALL" ] ||
        { [ -z "$_FILE_MODE$_DIR_MODE" ] && [ -r "${!1}" ]; } ||
        { lk_install -d ${_DIR_MODE:+-m "$_DIR_MODE"} "${!1%/*}" &&
            lk_install ${_FILE_MODE:+-m "$_FILE_MODE"} "${!1}"; }
}

# _lk_crontab REMOVE_REGEX ADD_COMMAND
function _lk_crontab() {
    local REGEX="${1:+.*$1.*}" ADD_COMMAND=${2-} TYPE=${2:+a}${1:+r} \
        CRONTAB NEW= NEW_CRONTAB
    lk_command_exists crontab || lk_warn "command not found: crontab" || return
    CRONTAB=$(lk_maybe_sudo crontab -l 2>/dev/null) &&
        unset NEW ||
        CRONTAB=
    [ "$TYPE" != ar ] ||
        [[ $ADD_COMMAND =~ $REGEX ]] ||
        lk_warn "command does not match regex" || return
    case "$TYPE" in
    a | ar)
        REGEX=${REGEX:-"^$S*$(lk_regex_expand_whitespace \
            "$(lk_ere_escape "$ADD_COMMAND")")$S*\$"}
        # If the command is already present, replace the first occurrence and
        # delete any duplicates
        if grep -E "$REGEX" >/dev/null <<<"$CRONTAB"; then
            REGEX=${REGEX//\//\\\/}
            NEW_CRONTAB=$(gnu_sed -E "0,/$REGEX/{s/$REGEX/$(
                lk_sed_escape_replace "$ADD_COMMAND"
            )/};t;/$REGEX/d" <<<"$CRONTAB")
        else
            # Otherwise, add it to the end of the file
            NEW_CRONTAB=${CRONTAB:+$CRONTAB$'\n'}$ADD_COMMAND
        fi
        ;;
    r)
        NEW_CRONTAB=$(sed -E "/${REGEX//\//\\\/}/d" <<<"$CRONTAB")
        ;;
    *)
        false || lk_warn "invalid arguments"
        ;;
    esac || return
    if [ -z "$NEW_CRONTAB" ]; then
        [ -n "${NEW+1}" ] || {
            lk_tty_print "Removing empty crontab for user '$(lk_me)'"
            lk_maybe_sudo crontab -r
        }
    else
        [ "$NEW_CRONTAB" = "$CRONTAB" ] || {
            local VERB=
            lk_tty_diff \
                <([ -z "$CRONTAB" ] || cat <<<"$CRONTAB") \
                <(cat <<<"$NEW_CRONTAB") \
                "${NEW+Creating}${NEW-Updating} crontab for user '$(lk_me)'"
            lk_maybe_sudo crontab - <<<"$NEW_CRONTAB"
        }
    fi
}

# lk_crontab_add COMMAND
function lk_crontab_add() {
    _lk_crontab "" "${1-}"
}

# lk_crontab_remove REGEX
function lk_crontab_remove() {
    _lk_crontab "${1-}" ""
}

# lk_crontab_apply CHECK_REGEX COMMAND
function lk_crontab_apply() {
    _lk_crontab "${1-}" "${2-}"
}

# lk_crontab_remove_command COMMAND
function lk_crontab_remove_command() {
    [ -n "${1-}" ] || lk_warn "no command" || return
    _lk_crontab "^$S*[^#[:blank:]].*$S$(lk_regex_expand_whitespace \
        "$(lk_ere_escape "$1")")($S|\$)" ""
}

# lk_crontab_get REGEX
function lk_crontab_get() {
    lk_maybe_sudo crontab -l 2>/dev/null | grep -E "${1-}"
}

# lk_system_memory [POWER]
#
# Output total installed memory in units of 1024 ^ POWER bytes, where:
# - 0 = bytes
# - 1 = KiB
# - 2 = MiB
# - 3 = GiB (default)
function lk_system_memory() {
    local POWER=${1:-3}
    if lk_is_linux; then
        lk_require_output \
            awk -v "p=$((POWER - 1))" \
            '/^MemTotal\W/{print int($2/1024^p)}' \
            /proc/meminfo
    elif lk_is_macos; then
        sysctl -n hw.memsize |
            lk_require_output \
                awk -v "p=$POWER" '{print int($1/1024^p)}'
    else
        false
    fi
}

# lk_system_memory_free [POWER]
#
# Output available memory in units of 1024 ^ POWER bytes (see lk_system_memory).
function lk_system_memory_free() {
    local POWER=${1:-3}
    if lk_is_linux; then
        lk_require_output \
            awk -v "p=$((POWER - 1))" \
            '/^MemAvailable\W/{print int($2/1024^p)}' \
            /proc/meminfo
    elif lk_is_macos; then
        vm_stat |
            lk_require_output \
                awk -v "p=$POWER" \
                -F "[^0-9]+" \
                'NR==1{b=$2;FS=":"} /^Pages free\W/{print int(b*$2/1024^p)}'
    else
        false
    fi
}

#!/bin/bash

function _lk_settings_list_known() {
    printf '%s\n' \
        LK_BASE \
        LK_PATH_PREFIX \
        LK_NODE_HOSTNAME LK_NODE_FQDN \
        LK_IPV4_ADDRESS LK_IPV4_GATEWAY LK_DNS_SERVERS LK_DNS_SEARCH \
        LK_BRIDGE_INTERFACE \
        LK_WIFI_REGDOM \
        LK_NODE_TIMEZONE \
        LK_FEATURES LK_PACKAGES \
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
        LK_SMTP_TRANSPORT_MAPS \
        LK_EMAIL_DESTINATION \
        LK_UPGRADE_EMAIL \
        LK_AUTO_REBOOT LK_AUTO_REBOOT_TIME \
        LK_AUTO_BACKUP_SCHEDULE \
        LK_SNAPSHOT_{HOURLY,DAILY,WEEKLY,FAILED}_MAX_AGE \
        LK_LAUNCHPAD_PPA_MIRROR \
        LK_SITE_ENABLE LK_SITE_DISABLE_WWW LK_SITE_DISABLE_HTTPS \
        LK_SITE_ENABLE_STAGING \
        LK_SITE_PHP_FPM_MAX_CHILDREN LK_SITE_PHP_FPM_MEMORY_LIMIT \
        LK_ARCH_MIRROR \
        LK_ARCH_REPOS \
        LK_ARCH_AUR_REPO_NAME \
        LK_ARCH_AUR_CHROOT_DIR \
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
        LK_EMAIL_BLACKHOLE \
        LK_NODE_SERVICES \
        LK_NODE_PACKAGES
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
    _lk_settings_migrate LK_FEATURES {LK_,}NODE_SERVICES
    _lk_settings_migrate LK_PACKAGES {LK_,}NODE_PACKAGES
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
        lk_feature_enabled router
}

#### Reviewed: 2021-08-28

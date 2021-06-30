#!/bin/bash

function _lk_settings_list_known() {
    printf '%s\n' \
        LK_BASE \
        LK_PATH_PREFIX \
        LK_NODE_HOSTNAME LK_NODE_FQDN \
        LK_IPV4_ADDRESS LK_IPV4_GATEWAY LK_IPV4_DNS_SERVER LK_IPV4_DNS_SEARCH \
        LK_BRIDGE_INTERFACE \
        LK_NODE_TIMEZONE \
        LK_NODE_SERVICES LK_NODE_PACKAGES \
        LK_NODE_LOCALES LK_NODE_LANGUAGE \
        LK_SAMBA_WORKGROUP \
        LK_GRUB_CMDLINE \
        LK_NTP_SERVER \
        LK_ADMIN_EMAIL \
        LK_TRUSTED_IP_ADDRESSES \
        LK_SSH_TRUSTED_ONLY LK_SSH_JUMP_HOST LK_SSH_JUMP_USER LK_SSH_JUMP_KEY \
        LK_REJECT_OUTPUT LK_ACCEPT_OUTPUT_HOSTS \
        LK_INNODB_BUFFER_SIZE \
        LK_OPCACHE_MEMORY_CONSUMPTION \
        LK_PHP_SETTINGS LK_PHP_ADMIN_SETTINGS \
        LK_MEMCACHED_MEMORY_LIMIT \
        LK_SMTP_RELAY \
        LK_EMAIL_BLACKHOLE \
        LK_UPGRADE_EMAIL \
        LK_AUTO_REBOOT LK_AUTO_REBOOT_TIME \
        LK_AUTO_BACKUP_SCHEDULE \
        LK_SNAPSHOT_{HOURLY,DAILY,WEEKLY,FAILED}_MAX_AGE \
        LK_SITE_ENABLE LK_SITE_DISABLE_WWW LK_SITE_DISABLE_HTTPS \
        LK_SITE_ENABLE_STAGING \
        LK_ARCH_MIRROR \
        LK_ARCH_REPOS \
        LK_DEBUG \
        LK_PLATFORM_BRANCH \
        LK_PACKAGES_FILE
} #### Reviewed: 2021-05-09

# _lk_settings_list_legacy
#
# Print the name of each setting that is no longer used.
function _lk_settings_list_legacy() {
    printf '%s\n' \
        LK_PATH_PREFIX_ALPHA \
        LK_SCRIPT_DEBUG
} #### Reviewed: 2021-06-06

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
} #### Reviewed: 2021-06-30

# lk_settings_getopt [ARG...]
#
# Output Bash code to
# - apply any --set, --add, or --unset arguments to the running shell
# - assign the number of arguments consumed to _LK_SHIFT
function lk_settings_getopt() {
    local IFS SHIFT=0 _SHIFT REGEX='^(LK_[a-zA-Z0-9_]*[a-zA-Z0-9])(=(.*))?$'
    unset IFS
    while [[ ${1-} =~ ^(-[sau]|--(set|add|unset))$ ]]; do
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
            printf '%s=$(IFS=, && printf '\''%%s\\n'\'' ${%s-} %s | sort -u | lk_implode_input ",")\n' \
                "$2" "$2" "$(IFS=, && lk_quote_args ${3-})"
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
} #### Reviewed: 2021-06-30

# lk_settings_persist COMMANDS [FILE...]
#
# Source each FILE, execute COMMANDS, and replace the first FILE with shell
# variable assignments for all declared LK_* variables.
#
# If FILE is not specified:
# - update system settings if running as root
# - if not running as root, update the current user's settings
function lk_settings_persist() {
    local FILES _FILE
    [ $# -ge 1 ] || lk_warn "invalid arguments" || return
    [ $# -ge 2 ] || {
        local IFS=$'\n'
        FILES=($(_lk_settings_writable_files)) || return
        set -- "$1" "${FILES[@]}"
        unset IFS
    }
    _FILE=$(
        unset "${!LK_@}"
        for ((i = $#; i > 1; i--)); do
            [ ! -f "${!i}" ] || . "${!i}" || return
        done
        eval "$1" || return
        VARS=($(_lk_settings_list_known &&
            comm -23 \
                <(printf '%s\n' "${!LK_@}" | sort -u) \
                <({ _lk_settings_list_known &&
                    _lk_settings_list_legacy; } | sort -u)))
        lk_get_shell_var "${VARS[@]}"
    ) || return
    lk_file_replace -m "$2" "$_FILE"
} #### Reviewed: 2021-06-30

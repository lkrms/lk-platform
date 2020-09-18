#!/bin/bash

# shellcheck disable=SC2088,SC2207

# lk_dir_set_permissions DIR [WRITABLE_REGEX [OWNER][:[GROUP]]]
function lk_dir_set_permissions() {
    local DIR="${1:-}" WRITABLE_REGEX="${2:-}" OWNER="${3:-}" \
        LOG_DIR WRITABLE TYPE MODE ARGS \
        DIR_MODE="${LK_DIR_MODE:-0755}" \
        FILE_MODE="${LK_FILE_MODE:-0644}" \
        WRITABLE_DIR_MODE="${LK_WRITABLE_DIR_MODE:-0775}" \
        WRITABLE_FILE_MODE="${LK_WRITABLE_FILE_MODE:-0664}"
    [ -d "$DIR" ] || lk_warn "not a directory: $DIR" || return
    DIR="$(realpath "$DIR")" &&
        LOG_DIR="$(lk_mktemp_dir)" || return
    lk_console_item "Setting permissions on" "$DIR"
    lk_console_detail "Logging changes in" "$LOG_DIR" "$LK_RED"
    lk_console_detail "File modes:" "$DIR_MODE, $FILE_MODE"
    [ -z "$WRITABLE_REGEX" ] || {
        lk_console_detail "Writable file modes:" "$WRITABLE_DIR_MODE, $WRITABLE_FILE_MODE"
        lk_console_detail "Writable paths:" "$WRITABLE_REGEX"
    }
    [ -z "$OWNER" ] ||
        if lk_is_root || lk_is_true "$(lk_get_maybe_sudo)"; then
            lk_console_detail "Owner:" "$OWNER"
            lk_maybe_sudo chown -Rhc "$OWNER" "$DIR" >"$LOG_DIR/chown.log" || return
            lk_console_detail "File ownership changes:" "$(wc -l <"$LOG_DIR/chown.log")" "$LK_GREEN"
        else
            lk_console_warning0 "Unable to set owner (not running as root)"
        fi
    for WRITABLE in "" w; do
        [ -z "$WRITABLE" ] || [ -n "$WRITABLE_REGEX" ] || continue
        for TYPE in d f; do
            case "$WRITABLE$TYPE" in
            d)
                MODE="$DIR_MODE"
                ;;
            f)
                MODE="$FILE_MODE"
                ;;
            wd)
                MODE="$WRITABLE_DIR_MODE"
                ;;
            wf)
                MODE="$WRITABLE_FILE_MODE"
                ;;
            esac
            ARGS=(-type "$TYPE" ! -perm "$MODE")
            case "$WRITABLE$TYPE" in
            d | f)
                # exclude writable directories and their descendants
                ARGS=(! \( -type d -regex "$WRITABLE_REGEX" -prune \) "${ARGS[@]}")
                [ "$WRITABLE$TYPE" != f ] ||
                    # exclude writable files (i.e. not just files in writable directories)
                    ARGS+=(! -regex "$WRITABLE_REGEX")
                ;;
            w*)
                ARGS+=(-regex "$WRITABLE_REGEX(/.*)?")
                ;;
            esac
            find "$DIR" -regextype posix-egrep "${ARGS[@]}" -print0 |
                lk_maybe_sudo gnu_xargs -0r gnu_chmod -c "0$MODE" >>"$LOG_DIR/chmod.log" || return
        done
    done
    lk_console_detail "File mode changes:" "$(wc -l <"$LOG_DIR/chmod.log")" "$LK_GREEN"
}

# lk_sudo_offer_nopasswd
#   Invite the current user to add themselves to the system's sudoers policy
#   with unlimited access and no password prompts.
function lk_sudo_offer_nopasswd() {
    local FILE
    FILE="/etc/sudoers.d/nopasswd-$USER"
    ! lk_is_root || lk_warn "cannot run as root" || return
    sudo -n test -e "$FILE" 2>/dev/null || {
        lk_can_sudo install || return
        lk_confirm "Allow user '$USER' to run sudo without entering a password?" Y || return
        sudo install -m 440 /dev/null "$FILE" &&
            sudo tee "$FILE" >/dev/null <<<"$USER ALL=(ALL) NOPASSWD:ALL" &&
            lk_console_message "User '$USER' may now run any command as any user" || return
    }
}

# lk_ssh_add_host <NAME> <HOST[:PORT]> <USER> [<KEY_FILE> [<JUMP_HOST_NAME>]]
function lk_ssh_add_host() {
    local NAME=$1 HOST=$2 JUMP_USER=$3 KEY_FILE=${4:-} JUMP_HOST_NAME=${5:-} \
        h=${LK_SSH_HOME:-~} SSH_PREFIX=${LK_SSH_PREFIX:-$LK_PATH_PREFIX} \
        S="[[:space:]]" KEY CONF CONF_FILE
    [ "${KEY_FILE:--}" = - ] ||
        [ -f "$KEY_FILE" ] ||
        [ -f "$h/.ssh/$KEY_FILE" ] ||
        { [ -f "$h/.ssh/${SSH_PREFIX}keys/$KEY_FILE" ] &&
            KEY_FILE="~/.ssh/${SSH_PREFIX}keys/$KEY_FILE"; } ||
        # If <KEY_FILE> doesn't exist but matches the regex below, check
        # ~/.ssh/authorized_keys for exactly one public key with the comment
        # field set to <KEY_FILE>
        { [[ "$KEY_FILE" =~ ^[-a-zA-Z0-9_]+$ ]] && { KEY=$(grep -E \
            "$S$KEY_FILE\$" "$h/.ssh/authorized_keys" 2>/dev/null) &&
            [ "$(wc -l <<<"$KEY")" -eq 1 ] &&
            KEY_FILE=- || KEY_FILE=; }; } ||
        lk_warn "$KEY_FILE: file not found" || return
    [ ! "$KEY_FILE" = - ] || {
        KEY=${KEY:-$(cat)}
        KEY_FILE=$h/.ssh/${SSH_PREFIX}keys/$NAME
        LK_BACKUP_SUFFIX='' LK_VERBOSE=0 \
            lk_maybe_replace "$KEY_FILE" "$KEY" &&
            chmod "0${LK_SSH_FILE_MODE:-0600}" "$KEY_FILE" || return
        ssh-keygen -l -f "$KEY_FILE" >/dev/null 2>&1 || {
            # `ssh-keygen -l -f FILE` exits without error if FILE contains an
            # OpenSSH public key
            lk_console_log "Reading $KEY_FILE to create public key file"
            KEY=$(unset DISPLAY && ssh-keygen -y -f "$KEY_FILE") &&
                LK_BACKUP_SUFFIX='' LK_VERBOSE=0 \
                    lk_maybe_replace "$KEY_FILE.pub" "$KEY" &&
                chmod "0${LK_SSH_FILE_MODE:-0600}" "$KEY_FILE.pub" || return
        }
    }
    CONF=$(
        [[ ! $HOST =~ (.*):([0-9]+)$ ]] || {
            HOST=${BASH_REMATCH[1]}
            PORT=${BASH_REMATCH[2]}
        }
        KEY_FILE=${KEY_FILE//${h//\//\\\/}/"~"}
        cat <<EOF
Host                    $SSH_PREFIX${NAME#$SSH_PREFIX}
HostName                $HOST${PORT:+
Port                    $PORT}${JUMP_USER:+
User                    $JUMP_USER}${KEY_FILE:+
IdentityFile            "$KEY_FILE"}${JUMP_HOST_NAME:+
ProxyJump               $SSH_PREFIX${JUMP_HOST_NAME#$SSH_PREFIX}}
EOF
    )
    CONF_FILE=$h/.ssh/${SSH_PREFIX}config.d/${LK_SSH_PRIORITY:-60}-$NAME
    LK_BACKUP_SUFFIX='' \
        lk_maybe_replace "$CONF_FILE" "$CONF" &&
        chmod "0${LK_SSH_FILE_MODE:-0600}" "$CONF_FILE" || return
}

# lk_ssh_configure [<JUMP_HOST[:JUMP_PORT]> <JUMP_USER> [<JUMP_KEY_FILE>]]
function lk_ssh_configure() {
    local JUMP_HOST=${1:-} JUMP_USER=${2:-} JUMP_KEY_FILE=${3:-} \
        S="[[:space:]]" SSH_PREFIX=${LK_SSH_PREFIX:-$LK_PATH_PREFIX} \
        HOMES=(${LK_SSH_HOMES[@]+"${LK_SSH_HOMES[@]}"}) h OWNER GROUP CONF KEY \
        LK_SSH_DIR_MODE LK_SSH_FILE_MODE
    [ $# -eq 0 ] || [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    [ "${#HOMES[@]}" -gt 0 ] || HOMES=(~)
    [ "${#HOMES[@]}" -le 1 ] ||
        [ ! "$JUMP_KEY_FILE" = - ] ||
        KEY=$(cat)
    for h in "${HOMES[@]}"; do
        OWNER=$(lk_file_owner "$h") &&
            GROUP=$(id -gn "$OWNER") || return
        unset LK_SSH_DIR_MODE
        unset LK_SSH_FILE_MODE
        [[ ! $h =~ ^/etc/skel(\.$LK_PATH_PREFIX_ALPHA)?$ ]] || {
            LK_SSH_DIR_MODE=0755
            LK_SSH_FILE_MODE=0644
        }
        # Create directories in ~/.ssh, or reset modes and ownership of existing
        # directories
        install -d -m "${LK_SSH_DIR_MODE:-0700}" -o "$OWNER" -g "$GROUP" \
            "$h/.ssh"{,"/$SSH_PREFIX"{config.d,keys}} ||
            return
        # Add "Include ~/.ssh/lk-config.d/*" to ~/.ssh/config if not already
        # present
        if ! grep -Eq "^\
$S*[iI][nN][cC][lL][uU][dD][eE]$S*(\"?)(~/\\.ssh/)?\
${SSH_PREFIX}config\\.d/\\*\\1$S*\$" "$h/.ssh/config" 2>/dev/null; then
            CONF=$(printf "%s\n%s %s\n\n." \
                "# Added by $(lk_myself) at $(lk_now)" \
                "Include" "~/.ssh/${SSH_PREFIX}config.d/*")
            [ ! -e "$h/.ssh/config" ] ||
                CONF=${CONF%.}$(cat "$h/.ssh/config" && echo .) ||
                return
            echo -n "${CONF%.}" >"$h/.ssh/config" || return
            ! lk_verbose || lk_console_file "$h/.ssh/config"
        fi
        # Add defaults for all lk-* hosts to ~/.ssh/lk-config.d/90-defaults
        CONF=$(
            cat <<EOF
Host                    ${SSH_PREFIX}*
IdentitiesOnly          yes
ForwardAgent            yes
StrictHostKeyChecking   accept-new
ControlMaster           auto
ControlPath             /tmp/ssh_%h-%p-%r-%l
ControlPersist          120
SendEnv                 LANG LC_*
ServerAliveInterval     30
EOF
        )
        LK_BACKUP_SUFFIX='' \
            lk_maybe_replace "$h/.ssh/${SSH_PREFIX}config.d/90-defaults" "$CONF"
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
            chmod "0${LK_SSH_FILE_MODE:-0600}" \
                "$h/.ssh/"{config,"$SSH_PREFIX"{config.d,keys}/*}
            ! lk_is_root ||
                chown "$OWNER:$GROUP" \
                    "$h/.ssh/"{config,"$SSH_PREFIX"{config.d,keys}/*}
        )
    done
}

function lk_node_is_host() {
    local NODE_IP HOST_IP
    NODE_IP=($(lk_node_public_ipv4)) &&
        NODE_IP+=($(lk_node_public_ipv6)) &&
        [ ${#NODE_IP} -gt 0 ] ||
        lk_warn "public IP address not found" || return
    # shellcheck disable=SC2034
    HOST_IP=($(lk_host_ns_resolve "$1")) ||
        lk_warn "unable to retrieve authoritative DNS records for $1" || return
    # True if at least one node IP matches a host IP
    [ "$(comm -12 \
        <(lk_echo_array HOST_IP) \
        <(lk_echo_array NODE_IP) | wc -l)" -gt 0 ]
}

function lk_certbot_install() {
    local EMAIL=${LK_LETSENCRYPT_EMAIL-${LK_ADMIN_EMAIL:-}} DOMAIN DOMAINS_OK=1
    lk_test_many "lk_is_fqdn" "$@" || lk_warn "invalid domain(s): $*" || return
    [ -n "$EMAIL" ] || lk_warn "email address not set" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    for DOMAIN in "$@"; do
        lk_node_is_host "$DOMAIN" ||
            lk_warn "domain does not resolve to this system: $DOMAIN" ||
            DOMAINS_OK=0
    done
    lk_is_true "$DOMAINS_OK" ||
        lk_confirm "Proceed anyway?" N || return
    lk_elevate certbot run \
        --non-interactive \
        --keep-until-expiring \
        --expand \
        --agree-tos \
        --email "$EMAIL" \
        --no-eff-email \
        --"${LK_LETSENCRYPT_PLUGIN:-apache}" \
        ${LK_LETSENCRYPT_OPTIONS[@]:+"${LK_LETSENCRYPT_OPTIONS[@]}"} \
        --domains "$(lk_implode "," "$@")"
}

# lk_apply_setting <FILE> <SETTING> <VAL> [<DELIM>] [<COMMENT_CHARS>] [<SPACES>]
#
# Set value of SETTING to VAL in FILE.
#
# Notes:
# - DELIM defaults to "="
# - To uncomment an existing SETTING assignment first, use COMMENT_CHARS to
#   specify which characters can be removed from the beginning of lines
# - Use SPACES to specify whitespace characters considered legal before and
#   after SETTING, VAL and DELIMITER
function lk_apply_setting() {
    local FILE_PATH="$1" SETTING_NAME="$2" SETTING_VALUE="$3" DELIMITER="${4:-=}" \
        COMMENT_PATTERN SPACE_PATTERN NAME_ESCAPED VALUE_ESCAPED DELIMITER_ESCAPED CHECK_PATTERN SEARCH_PATTERN REPLACE REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    COMMENT_PATTERN="${5:+[$(lk_escape_ere "$5")]*}"
    SPACE_PATTERN="${6:+[$(lk_escape_ere "$6")]*}"
    NAME_ESCAPED="$(lk_escape_ere "$SETTING_NAME")"
    VALUE_ESCAPED="$(lk_escape_ere "$SETTING_VALUE")"
    DELIMITER_ESCAPED="$(sed -Ee "s/^$SPACE_PATTERN//" -e "s/$SPACE_PATTERN\$//" <<<"$DELIMITER")"
    [ -n "$DELIMITER_ESCAPED" ] || DELIMITER_ESCAPED="$DELIMITER"
    DELIMITER_ESCAPED="$(lk_escape_ere "$DELIMITER_ESCAPED")"
    CHECK_PATTERN="^$SPACE_PATTERN$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED$SPACE_PATTERN$VALUE_ESCAPED$SPACE_PATTERN\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        REPLACE="$SETTING_NAME$DELIMITER$SETTING_VALUE"
        # try to replace an uncommented value first
        SEARCH_PATTERN="^($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        # failing that, try for a commented one
        grep -Eq "$CHECK_PATTERN" <<<"$REPLACED" || {
            SEARCH_PATTERN="^($SPACE_PATTERN)$COMMENT_PATTERN($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
            REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1\\2$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        }
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$REPLACE"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}

# LK_EXPAND_WHITESPACE=<1|0|Y|N> \
#   lk_enable_entry <FILE> <ENTRY> [<COMMENT_CHARS>] [<TRAILING_PATTERN>]
#
# Add ENTRY to FILE if not already present.
#
# Notes:
# - To uncomment an existing ENTRY line first, use COMMENT_CHARS to specify
#   which characters can be removed from the beginning of lines
# - Use TRAILING_PATTERN to provide a regular expression matching existing text
#   to retain if it appears after ENTRY (default: keep whitespace and comments)
# - LK_EXPAND_WHITESPACE allows one or more whitespace characters in ENTRY to
#   match one or more whitespace characters in FILE (default: enabled)
# - If LK_EXPAND_WHITESPACE is enabled, escaped whitespace characters in ENTRY
#   are unescaped without expansion
function lk_enable_entry() {
    local FILE_PATH="$1" ENTRY="$2" OPTIONAL_COMMENT_PATTERN COMMENT_PATTERN TRAILING_PATTERN \
        ENTRY_ESCAPED SPACE_PATTERN CHECK_PATTERN SEARCH_PATTERN REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    OPTIONAL_COMMENT_PATTERN="${3:+[$(lk_escape_ere "$3")]*}"
    COMMENT_PATTERN="${3:+$(lk_trim "$3")}"
    COMMENT_PATTERN="${COMMENT_PATTERN:+[$(lk_escape_ere "$COMMENT_PATTERN")]+}"
    TRAILING_PATTERN="${4-\\s+${COMMENT_PATTERN:+(${COMMENT_PATTERN}.*)?}}"
    ENTRY_ESCAPED="$(lk_escape_ere "$ENTRY")"
    SPACE_PATTERN=
    lk_is_false "${LK_EXPAND_WHITESPACE:-1}" || {
        ENTRY_ESCAPED="$(sed -Ee 's/(^|[^\])\s+/\1\\s+/g' -e 's/\\\\(\s)/\1/g' <<<"$ENTRY_ESCAPED")"
        SPACE_PATTERN='\s*'
    }
    CHECK_PATTERN="^$SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?}\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        # try to replace a commented entry
        SEARCH_PATTERN="^($SPACE_PATTERN)$OPTIONAL_COMMENT_PATTERN($SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?})\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\1\2/}" "$FILE_PATH")" || return
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$ENTRY"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}

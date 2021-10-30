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
} #### Reviewed: 2021-03-27

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
} #### Reviewed: 2021-03-27

# lk_node_expand_services [SERVICE,...]
#
# Add alternative names to the service list (all enabled services by default).
function lk_node_expand_services() {
    local IFS=, SERVICES=${1-${LK_NODE_SERVICES-}}
    _lk_node_expand_service apache+php apache2 php-fpm
    _lk_node_expand_service mysql mariadb
    _lk_node_expand_service -n xfce4 desktop
    lk_echo_args $SERVICES | sort -u | lk_implode_input ","
} #### Reviewed: 2021-03-27

#### INCLUDE provision.sh.d

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
    _LOCALES=$(lk_echo_array LOCALES |
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
    DIR=$(_lk_realpath "$1") || return
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
    ! lk_verbose || lk_console_message \
        "Updating file modes in $(lk_tty_path "$DIR")"
    for i in "${!MATCH[@]}"; do
        [ -n "${DIR_MODE[$i]:+1}${FILE_MODE[$i]:+1}" ] || continue
        ! lk_verbose 2 || lk_console_item "Checking:" "${MATCH[$i]}"
        CHANGES=0
        for TYPE in DIR_MODE FILE_MODE; do
            MODE=${TYPE}"[$i]"
            MODE=${!MODE}
            [ -n "$MODE" ] || continue
            ! lk_verbose 2 || lk_console_detail "$([ "$TYPE" = DIR_MODE ] &&
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
        ! lk_verbose 2 || lk_console_detail "Changes:" "$LK_BOLD$CHANGES"
        ((TOTAL += CHANGES)) || true
    done
    ! lk_verbose && ! ((TOTAL)) ||
        $(lk_verbose &&
            echo "lk_console_message" ||
            echo "lk_console_detail") \
            "$TOTAL file $(lk_plural \
                "$TOTAL" mode modes) updated$(lk_verbose ||
                    echo " in $(lk_tty_path "$DIR")")"
    ! ((TOTAL)) &&
        lk_delete_on_exit "$LOG_FILE" ||
        lk_console_detail "Changes logged to:" "$LOG_FILE"
}

function lk_sudo_add_nopasswd() {
    local LK_SUDO=1 FILE
    [ -n "${1-}" ] || lk_warn "no user" || return
    lk_user_exists "$1" || lk_warn "user not found: $1" || return
    FILE=/etc/sudoers.d/nopasswd-$1
    lk_install -m 00440 "$FILE" &&
        lk_file_replace "$FILE" "$1 ALL=(ALL) NOPASSWD:ALL"
}

# lk_sudo_offer_nopasswd
#
# Invite the current user to add themselves to the system's sudoers policy with
# unlimited access and no password prompts.
function lk_sudo_offer_nopasswd() {
    local FILE
    ! lk_root || lk_warn "cannot run as root" || return
    FILE=/etc/sudoers.d/nopasswd-$USER
    sudo -n test -e "$FILE" 2>/dev/null || {
        lk_can_sudo install || return
        lk_confirm \
            "Allow '$USER' to run commands as root with no password?" N ||
            return 0
        lk_sudo_add_nopasswd "$USER" &&
            lk_console_message \
                "User '$USER' may now run any command as any user"
    }
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
                    sed -E "s/^(\"?)([^~/])/\\1~\\/.ssh\\/\\2/")
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
                -e "s/\"(.+)\"/\\1/g" \
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
    NAME=${NAME#$SSH_PREFIX}
    [ "${KEY_FILE:--}" = - ] ||
        [ -f "$KEY_FILE" ] ||
        [ -f "$h/.ssh/$KEY_FILE" ] ||
        { [ -f "$h/.ssh/${SSH_PREFIX}keys/$KEY_FILE" ] &&
            KEY_FILE=$h/.ssh/${SSH_PREFIX}keys/$KEY_FILE; } ||
        # If KEY_FILE doesn't exist but matches the regex below, check
        # ~/.ssh/authorized_keys for exactly one public key with the comment
        # field set to KEY_FILE
        { [[ "$KEY_FILE" =~ ^[-a-zA-Z0-9_]+$ ]] && { KEY=$(grep -E \
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
            lk_console_log "Reading $KEY_FILE to create public key file"
            KEY=$(unset DISPLAY && ssh-keygen -y -f "$KEY_FILE") &&
                lk_install -m 00600 "$KEY_FILE.pub" &&
                lk_file_replace "$KEY_FILE.pub" "$KEY" || return
        }
    }
    [[ ! $HOST =~ (.*):([0-9]+)$ ]] || {
        HOST=${BASH_REMATCH[1]}
        PORT=${BASH_REMATCH[2]}
    }
    JUMP_HOST_NAME=${JUMP_HOST_NAME:+$SSH_PREFIX${JUMP_HOST_NAME#$SSH_PREFIX}}
    ! lk_is_true TEST || {
        if [ -z "$JUMP_HOST_NAME" ]; then
            lk_ssh_is_reachable "$HOST" "${PORT:-22}"
        else
            JUMP_ARGS=(
                -o ConnectTimeout=5
                -o ControlMaster=auto
                -o ControlPath="/tmp/.${FUNCNAME}_%h-%p-%r-%u-%l"
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
ProxyJump       $SSH_PREFIX${JUMP_HOST_NAME#$SSH_PREFIX}}
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
        if [[ $h = ~ ]]; then
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
ControlPath             /tmp/ssh_%h-%p-%r-%u-%l
ControlPersist          120
SendEnv                 LANG LC_*
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

# lk_hosts_file_add IP NAME...
function lk_hosts_file_add() {
    local LK_SUDO=1 FILE=/etc/hosts BLOCK_ID SH REGEX HOSTS _FILE
    BLOCK_ID=$(lk_caller_name) &&
        SH=$(lk_get_regex IP_REGEX HOST_NAME_REGEX) &&
        eval "$SH" || return
    REGEX="^$S*(#$S*)?$IP_REGEX($S+$HOST_NAME_REGEX)+$S+##$S*$BLOCK_ID$S*##"
    _FILE=$(HOSTS=$({ sed -E "/$REGEX/!d" "$FILE" &&
        printf '%s %s\t## %s ##\n' "$1" "${*:2}" "$BLOCK_ID"; } |
        sort -u) &&
        awk \
            -v "BLOCK=$HOSTS" \
            -v "FIRST=##$S*$BLOCK_ID$S*##" \
            -f "$LK_BASE/lib/awk/block-replace.awk" \
            "$FILE") || return
    if lk_can_sudo install; then
        lk_file_keep_original "$FILE" &&
            lk_file_replace "$FILE" "$_FILE"
    else
        lk_console_item "You do not have permission to edit" "$FILE"
        FILE=$(lk_mktemp_file) &&
            echo "$_FILE" >"$FILE" &&
            lk_console_detail "Updated hosts file written to:" "$FILE"
    fi
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

function lk_host_soa() {
    local IFS ANSWER APEX NAMESERVERS NAMESERVER SOA
    unset IFS
    ANSWER=$(lk_dns_get_records_first_parent NS "$1") || return
    ! lk_verbose 2 ||
        lk_console_detail "Looking up SOA for domain:" "$1"
    APEX=$(awk '{sub("\\.$", "", $1); print $1}' <<<"$ANSWER" | sort -u)
    [ "$(wc -l <<<"$APEX")" -eq 1 ] ||
        lk_warn "invalid response to NS lookup" || return
    NAMESERVERS=($(awk '{sub("\\.$", "", $5); print $5}' <<<"$ANSWER" | sort))
    ! lk_verbose 2 || {
        lk_console_detail "Domain apex:" "$APEX"
        lk_console_detail "Name servers:" "$(lk_implode_arr ", " NAMESERVERS)"
    }
    for NAMESERVER in "${NAMESERVERS[@]}"; do
        if SOA=$(
            _LK_DNS_SERVER=$NAMESERVER
            _LK_DIG_OPTIONS=(+norecurse)
            lk_require_output lk_dns_get_records SOA "$APEX"
        ); then
            ! lk_verbose 2 ||
                lk_console_detail "SOA from $NAMESERVER for $APEX:" $'\n'"$SOA"
            echo "$SOA"
            break
        else
            unset SOA
        fi
    done
    [ -n "${SOA-}" ] || lk_warn "SOA lookup failed: $1"
} #### Reviewed: 2021-03-30

function lk_host_ns_resolve() {
    local IFS NAMESERVER IP CNAME _LK_DNS_SERVER _LK_DIG_OPTIONS \
        _LK_CNAME_DEPTH=${_LK_CNAME_DEPTH:-0}
    unset IFS
    [ "$_LK_CNAME_DEPTH" -lt 7 ] || lk_warn "too much recursion" || return
    ((++_LK_CNAME_DEPTH))
    NAMESERVER=$(lk_host_soa "$1" |
        awk '{sub("\\.$", "", $5); print $5}') || return
    _LK_DNS_SERVER=$NAMESERVER
    _LK_DIG_OPTIONS=(+norecurse)
    ! lk_verbose 2 || {
        lk_console_detail "Using name server:" "$NAMESERVER"
        lk_console_detail "Looking up A and AAAA records for:" "$1"
    }
    IP=($(lk_dns_get_records +VALUE A,AAAA "$1")) || return
    if [ ${#IP[@]} -eq 0 ]; then
        ! lk_verbose 2 || {
            lk_console_detail "No A or AAAA records returned"
            lk_console_detail "Looking up CNAME record for:" "$1"
        }
        CNAME=($(lk_dns_get_records +VALUE CNAME "$1")) || return
        if [ ${#CNAME[@]} -eq 1 ]; then
            ! lk_verbose 2 ||
                lk_console_detail "CNAME value from $NAMESERVER for $1:" \
                    "${CNAME[0]}"
            lk_host_ns_resolve "${CNAME[0]%.}" || return
            return
        fi
    fi
    [ ${#IP[@]} -gt 0 ] || lk_warn "could not resolve $1: $NAMESERVER" || return
    ! lk_verbose 2 ||
        lk_console_detail "A and AAAA values from $NAMESERVER for $1:" \
            "$(lk_echo_array IP)"
    lk_echo_array IP
} #### Reviewed: 2021-03-30

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
    HOST_IP=($(lk_host_ns_resolve "$1")) ||
        lk_warn "unable to retrieve authoritative DNS records for $1" || return
    lk_require_output -q comm -12 \
        <(lk_echo_array HOST_IP | sort -u) \
        <(lk_echo_array NODE_IP | sort -u)
} #### Reviewed: 2021-03-30

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
    [ ${#DOMAINS[@]} -gt 0 ] || lk_usage "\
Usage: $FUNCNAME [-w WEBROOT_PATH] DOMAIN... [-- CERTBOT_ARG...]" || return
    lk_test_many lk_is_fqdn "${DOMAINS[@]}" ||
        lk_warn "invalid domain(s): ${DOMAINS[*]}" || return
    [ -z "${WEBROOT+1}" ] || lk_elevate test -d "$WEBROOT_PATH" ||
        lk_warn "directory not found: $WEBROOT_PATH" || return
    [ -n "$EMAIL" ] || lk_warn "no email address in environment" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    for DOMAIN in "${DOMAINS[@]}"; do
        lk_node_is_host "$DOMAIN" &&
            lk_console_log "Domain resolves to this system:" "$DOMAIN" ||
            lk_console_warning -r \
                "Domain does not resolve to this system:" "$DOMAIN" ||
            ((++ERRORS))
    done
    [ "$ERRORS" -eq 0 ] ||
        lk_is_true LK_LETSENCRYPT_IGNORE_DNS ||
        lk_confirm "Ignore domain resolution errors?" N || return
    lk_run_detail lk_elevate certbot \
        ${WEBROOT-run} \
        ${WEBROOT+certonly} \
        --non-interactive \
        --keep-until-expiring \
        --expand \
        --agree-tos \
        --email "$EMAIL" \
        --no-eff-email \
        ${WEBROOT---no-redirect} \
        ${WEBROOT---"${LK_CERTBOT_PLUGIN:-apache}"} \
        ${WEBROOT+--webroot} \
        ${WEBROOT+--webroot-path "$WEBROOT_PATH"} \
        --domains "$(lk_implode_args "," "${DOMAINS[@]}")" \
        ${LK_CERTBOT_OPTIONS[@]:+"${LK_CERTBOT_OPTIONS[@]}"} \
        "$@"
} #### Reviewed: 2021-03-31

# lk_certbot_list_certificates [DOMAIN...]
function lk_certbot_list_certificates() {
    local ARGS IFS=,
    [ $# -eq 0 ] ||
        ARGS=(--domains "$*")
    lk_elevate certbot certificates ${ARGS[@]+"${ARGS[@]}"} |
        awk -f "$LK_BASE/lib/awk/certbot-parse-certificates.awk"
} #### Reviewed: 2021-04-22

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
            lk_console_message "Removing empty crontab for user '$(lk_me)'"
            lk_maybe_sudo crontab -r
        }
    else
        [ "$NEW_CRONTAB" = "$CRONTAB" ] || {
            local VERB=
            lk_console_diff \
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

lk_provide provision

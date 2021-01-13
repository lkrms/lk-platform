#!/bin/bash

# shellcheck disable=SC2015,SC2016,SC2030,SC2031,SC2034,SC2086,SC2120,SC2206,SC2207

function lk_node_service_enabled() {
    [ -n "${LK_NODE_SERVICES:-}" ] || return
    [[ ,$LK_NODE_SERVICES, == *,$1,* ]] ||
        [[ ,$(lk_node_expand_services), == *,$1,* ]]
}

function _lk_node_expand_service() {
    local SERVICE REVERSE=1
    [ "${1:-}" != -n ] || { REVERSE= && shift; }
    if [[ ,$SERVICES, == *,$1,* ]]; then
        SERVICES=$SERVICES$(printf ',%s' "${@:2}")
    elif lk_is_true REVERSE; then
        for SERVICE in "${@:2}"; do
            [[ ,$SERVICES, == *,$SERVICE,* ]] || return 0
        done
        SERVICES=$SERVICES,$1
    fi
}

function lk_node_expand_services() {
    local IFS=, SERVICES=${1:-${LK_NODE_SERVICES:-}}
    _lk_node_expand_service apache+php apache2 php-fpm
    _lk_node_expand_service mysql mariadb
    _lk_node_expand_service -n xfce4 desktop
    lk_echo_args $SERVICES | sort -u | lk_implode_input ","
}

# lk_maybe_install [-v] [-m MODE] [-o OWNER] [-g GROUP] SOURCE DEST
# lk_maybe_install -d [-v] [-m MODE] [-o OWNER] [-g GROUP] DEST
function lk_maybe_install() {
    local DEST=${*: -1:1} LK_SUDO=${LK_SUDO:-} OWNER GROUP VERBOSE MODE i \
        ARGS=("$@") LK_ARG_ARRAY=ARGS
    ! i=$(lk_array_search "-o" ARGS) || OWNER=${ARGS[*]:$((i + 1)):1}
    ! i=$(lk_array_search "-g" ARGS) || GROUP=${ARGS[*]:$((i + 1)):1}
    [ -z "${OWNER:-}${GROUP:-}" ] || LK_SUDO=1
    if lk_has_arg "-d" || lk_maybe_sudo test ! -e "$DEST"; then
        lk_maybe_sudo install "$@"
    else
        ! lk_has_arg "-v" || VERBOSE=1
        ! i=$(lk_array_search "-m" ARGS) || MODE=${ARGS[*]:$((i + 1)):1}
        [ -z "${MODE:-}" ] ||
            lk_maybe_sudo chmod ${VERBOSE+-v} "$MODE" "$DEST" || return
        [ -z "${OWNER:-}${GROUP:-}" ] ||
            lk_elevate chown ${VERBOSE+-v} \
                "${OWNER:-}${GROUP:+:$GROUP}" "$DEST" || return
    fi
}

# lk_dir_set_modes DIR REGEX DIR_MODE FILE_MODE [REGEX DIR_MODE FILE_MODE]...
function lk_dir_set_modes() {
    local DIR REGEX LOG_FILE i TYPE MODE ARGS CHANGES _CHANGES TOTAL=0 \
        _PRUNE _EXCLUDE MATCH=() DIR_MODE=() FILE_MODE=() PRUNE=() LK_USAGE
    LK_USAGE="\
Usage: $(lk_myself -f) DIR REGEX DIR_MODE FILE_MODE [REGEX DIR_MODE FILE_MODE]..."
    [ $# -ge 4 ] && ! ((($# - 1) % 3)) || lk_usage || return
    lk_maybe_sudo test -d "$1" || lk_warn "not a directory: $1" || return
    DIR=$(lk_maybe_sudo realpath "$1") || return
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
        "Updating file modes in $(lk_pretty_path "$DIR")"
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
        lk_console_message \
            "$TOTAL file $(lk_maybe_plural \
                "$TOTAL" mode modes) updated$(lk_verbose ||
                    echo " in $(lk_pretty_path "$DIR")")"
    ! ((TOTAL)) ||
        lk_console_detail "Changes logged to:" "$LOG_FILE"
}

function lk_sudo_add_nopasswd() {
    local LK_SUDO=1 FILE
    [ -n "${1:-}" ] || lk_warn "no user" || return
    lk_user_exists "$1" || lk_warn "user does not exist: $1" || return
    FILE=/etc/sudoers.d/nopasswd-$1
    lk_maybe_install -m 00440 /dev/null "$FILE" &&
        lk_file_replace "$FILE" "$1 ALL=(ALL) NOPASSWD:ALL"
}

# lk_sudo_offer_nopasswd
#
# Invite the current user to add themselves to the system's sudoers policy with
# unlimited access and no password prompts.
function lk_sudo_offer_nopasswd() {
    local FILE
    ! lk_is_root || lk_warn "cannot run as root" || return
    FILE=/etc/sudoers.d/nopasswd-$USER
    sudo -n test -e "$FILE" 2>/dev/null || {
        lk_can_sudo install || return
        lk_confirm \
            "Allow user '$USER' to run sudo without entering a password?" Y ||
            return
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
        "^$S*$OPTION($S+|$S*=).*" "^$S*#$S*$OPTION($S+|$S*=).*"
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
    [ -n "${1:-}" ] &&
        lk_ssh_list_hosts | grep -Fx "$1" >/dev/null
}

function lk_ssh_get_host_key_files() {
    local KEY_FILE
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    lk_ssh_host_exists "$1" || lk_warn "ssh host not found: $1" || return
    KEY_FILE=$(ssh -G "$1" |
        awk '/^identityfile / { print $2 }' |
        lk_expand_path |
        lk_filter "test -f") &&
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
    if ssh-keygen -l -f <(cat <<<"$KEY") >/dev/null 2>&1; then
        echo "$KEY"
    else
        # ssh-keygen doesn't allow fingerprinting from a file descriptor
        KEY_FILE=$(lk_mktemp_file) &&
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
        LK_FILE_TAKE_BACKUP='' LK_VERBOSE=0 \
        KEY JUMP_ARGS JUMP_PORT CONF CONF_FILE TEST=
    [ "${1:-}" != -t ] || { TEST=1 && shift; }
    NAME=$1
    HOST=$2
    SSH_USER=$3
    KEY_FILE=${4:-}
    JUMP_HOST_NAME=${5:-}
    [ $# -ge 3 ] || lk_usage "\
Usage: $(lk_myself -f) [-t] NAME HOST[:PORT] USER [KEY_FILE [JUMP_HOST_NAME]]" ||
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
        lk_maybe_install -m 00600 /dev/null "$KEY_FILE" &&
            lk_file_replace "$KEY_FILE" "$KEY" || return
        ssh-keygen -l -f "$KEY_FILE" >/dev/null 2>&1 || {
            # `ssh-keygen -l -f FILE` exits without error if FILE contains an
            # OpenSSH public key
            lk_console_log "Reading $KEY_FILE to create public key file"
            KEY=$(unset DISPLAY && ssh-keygen -y -f "$KEY_FILE") &&
                lk_maybe_install -m 00600 /dev/null "$KEY_FILE.pub" &&
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
                -o ControlPath="/tmp/.$(lk_myself -f)_%h-%p-%r-%l"
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
                    "${JUMP_ARGS[@]}" "$JUMP_HOST_NAME" >/dev/null 2>&1 ||
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
    lk_maybe_install -m 00600 /dev/null "$CONF_FILE" &&
        lk_file_replace "$CONF_FILE" "$CONF" || return
}

# lk_ssh_is_reachable HOST PORT [TIMEOUT_SECONDS]
function lk_ssh_is_reachable() {
    { echo QUIT | gnu_nc -w "${3:-5}" "$1" "$2" | head -n1 |
        grep -E "^SSH-[^[:blank:]-]+-[^[:blank:]-]+" >/dev/null; } \
        2>/dev/null
}

# lk_ssh_configure [JUMP_HOST[:JUMP_PORT] JUMP_USER [JUMP_KEY_FILE]]
function lk_ssh_configure() {
    local JUMP_HOST=${1:-} JUMP_USER=${2:-} JUMP_KEY_FILE=${3:-} \
        SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX} \
        LK_FILE_TAKE_BACKUP='' LK_VERBOSE=0 \
        KEY PATTERN CONF AWK OWNER GROUP \
        HOMES=(${LK_HOMES[@]+"${LK_HOMES[@]}"}) h
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
        -f "${LK_INST:-$LK_BASE}/lib/awk/update-ssh-config.awk"
        -v "SSH_PATTERN=$PATTERN"
        -v "SSH_CONFIG=$CONF")

    for h in "${HOMES[@]}"; do
        [ ! -e "$h/.${LK_PATH_PREFIX}ignore" ] &&
            [ ! -e "$h/.ssh/.${LK_PATH_PREFIX}ignore" ] || continue
        OWNER=$(lk_file_owner "$h") &&
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
        lk_file_replace "$h/.ssh/config" "$("${AWK[@]}" "$h/.ssh/config")"
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
            ! lk_is_root ||
                chown "$OWNER:$GROUP" \
                    "$h/.ssh/"{config,"$SSH_PREFIX"{config.d,keys}/*}
        )
    done
}

# lk_filter_ipv4
#
# Print each input line that is a valid dotted-decimal IPv4 address or CIDR.
function lk_filter_ipv4() {
    eval "$(lk_get_regex IPV4_OPT_PREFIX_REGEX)"
    sed -E "\\#^$IPV4_OPT_PREFIX_REGEX\$#!d"
}

# lk_filter_ipv6
#
# Print each input line that is a valid 8-hextet IPv6 address or CIDR.
function lk_filter_ipv6() {
    eval "$(lk_get_regex IPV6_OPT_PREFIX_REGEX)"
    sed -E "\\#^$IPV6_OPT_PREFIX_REGEX\$#!d"
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
        -f "${LK_INST:-$LK_BASE}/lib/awk/parse-ifconfig.awk" \
        -v "ADDRESS_FAMILY=$1" |
        sed -E 's/%[^/]+\//\//') || return
    {
        grep -Ev "^$(lk_regex_implode "${PRIVATE[@]}")" <<<"$IP" || true
        lk_is_true LK_IP_PUBLIC_ONLY ||
            for i in "${PRIVATE[@]}"; do
                grep -E "^$i" <<<"$IP" || true
            done
    } | if lk_is_true LK_IP_KEEP_PREFIX; then
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
        LK_IP_PUBLIC_ONLY=1 lk_node_ipv4
    } | sort -u
}

function lk_node_public_ipv6() {
    local IP
    {
        ! IP=$(dig +noall +answer +short @2606:4700:4700::1111 \
            whoami.cloudflare TXT CH | sed -E 's/^"(.*)"$/\1/') || echo "$IP"
        LK_IP_PUBLIC_ONLY=1 lk_node_ipv6
    } | sort -u
}

# lk_hosts_get_records [+FIELD[,FIELD...]>] TYPE[,TYPE...] HOST...
#
# Print space-separated resource records of each TYPE for each HOST, optionally
# limiting output to each FIELD.
#
# Fields and output order:
# - NAME
# - TTL
# - CLASS
# - TYPE
# - RDATA
# - VALUE (synonym for RDATA)
function lk_hosts_get_records() {
    local FIELDS FIELD CUT TYPE IFS TYPES HOST \
        COMMAND=(
            dig +noall +answer
            ${LK_DIG_OPTIONS[@]:+"${LK_DIG_OPTIONS[@]}"}
            ${LK_DIG_SERVER:+@"$LK_DIG_SERVER"}
        )
    if [ "${1:0:1}" = + ]; then
        IFS=,
        FIELDS=(${1:1})
        shift
        unset IFS
        [ ${#FIELDS[@]} -gt 0 ] || lk_warn "no output field" || return
        FIELDS=($(lk_echo_array FIELDS | sort -u))
        CUT=-f
        for FIELD in "${FIELDS[@]}"; do
            case "$FIELD" in
            NAME)
                CUT=${CUT}1,
                ;;
            TTL)
                CUT=${CUT}2,
                ;;
            CLASS)
                CUT=${CUT}3,
                ;;
            TYPE)
                CUT=${CUT}4,
                ;;
            RDATA | VALUE)
                CUT=${CUT}5,
                ;;
            *)
                lk_warn "invalid field: $FIELD"
                return 1
                ;;
            esac
        done
        CUT=${CUT%,}
    fi
    TYPE=$1
    shift
    [[ $TYPE =~ ^[a-zA-Z]+(,[a-zA-Z]+)*$ ]] ||
        lk_warn "invalid type(s): $TYPE" || return
    lk_test_many "lk_is_host" "$@" || lk_warn "invalid host(s): $*" || return
    IFS=,
    TYPES=($TYPE)
    for TYPE in "${TYPES[@]}"; do
        for HOST in "$@"; do
            COMMAND+=(
                "$HOST" "$TYPE"
            )
        done
    done
    REGEX="s/^($NS+)$S+($NS+)$S+($NS+)$S+($NS+)$S+($NS+)/\\1 \\2 \\3 \\4 \\5/"
    "${COMMAND[@]}" |
        sed -E "$REGEX" |
        awk "\$4 ~ /^$(lk_regex_implode "${TYPES[@]}")$/" |
        { [ -z "${CUT:-}" ] && cat || cut -d' ' "$CUT"; }
}

# lk_hosts_resolve HOST...
function lk_hosts_resolve() {
    local HOSTS IP_ADDRESSES
    IP_ADDRESSES=($({
        lk_echo_args "$@" | lk_filter_ipv4
        lk_echo_args "$@" | lk_filter_ipv6
    }))
    HOSTS=($(comm -23 <(lk_echo_args "$@" | sort -u) \
        <(lk_echo_array IP_ADDRESSES | sort -u)))
    [ ${#HOSTS[@]} -eq 0 ] ||
        IP_ADDRESSES+=($(lk_hosts_get_records +VALUE A,AAAA "${HOSTS[@]}")) ||
        return
    lk_echo_array IP_ADDRESSES | sort -u
}

function lk_host_first_answer() {
    local DOMAIN=$2 ANSWER
    lk_is_fqdn "$2" || lk_warn "invalid domain: $2" || return
    ANSWER=$(lk_hosts_get_records A,AAAA "$2") && [ -n "$ANSWER" ] ||
        lk_warn "lookup failed: $2" || return
    while :; do
        ANSWER=$(lk_hosts_get_records "$1" "$DOMAIN") || return
        [ -n "$ANSWER" ] || {
            DOMAIN=${DOMAIN#*.}
            lk_is_fqdn "$DOMAIN" || lk_warn "$1 lookup failed: $2" || return
            continue
        }
        echo "$ANSWER"
        return 0
    done
}

function lk_host_soa() {
    local ANSWER DOMAIN NAMESERVERS NAMESERVER SOA
    ANSWER=$(lk_host_first_answer NS "$1") || return
    ! lk_verbose || lk_console_detail "Looking up SOA for domain:" "$1"
    DOMAIN=$(awk '{ print substr($1, 1, length($1) - 1) }' <<<"$ANSWER" |
        sort -u)
    [ "$(wc -l <<<"$DOMAIN")" -eq 1 ] ||
        lk_warn "invalid response to NS lookup" || return
    NAMESERVERS=($(awk '{ print substr($5, 1, length($5) - 1) }' <<<"$ANSWER"))
    ! lk_verbose || {
        lk_console_detail "Domain apex:" "$DOMAIN"
        lk_console_detail "Name servers:" "${NAMESERVERS[*]}"
    }
    for NAMESERVER in "${NAMESERVERS[@]}"; do
        SOA=$(
            LK_DIG_SERVER=$NAMESERVER
            LK_DIG_OPTIONS=(+norecurse)
            lk_hosts_get_records SOA "$DOMAIN"
        ) && [ -n "$SOA" ] || continue
        ! lk_verbose ||
            lk_console_detail "SOA from $NAMESERVER for $DOMAIN:" \
                "$(cut -d' ' -f5- <<<"$SOA")"
        echo "$SOA"
        return 0
    done
    lk_warn "SOA lookup failed: $1"
    return 1
}

function lk_host_ns_resolve() {
    local NAMESERVER IP CNAME LK_DIG_SERVER LK_DIG_OPTIONS \
        _LK_CNAME_DEPTH=${_LK_CNAME_DEPTH:-0}
    [ "$_LK_CNAME_DEPTH" -lt 7 ] || lk_warn "too much recursion" || return
    ((++_LK_CNAME_DEPTH))
    NAMESERVER=$(lk_host_soa "$1" |
        awk '{ print substr($5, 1, length($5) - 1) }') ||
        return
    LK_DIG_SERVER=$NAMESERVER
    LK_DIG_OPTIONS=(+norecurse)
    ! lk_verbose || {
        lk_console_detail "Using name server:" "$NAMESERVER"
        lk_console_detail "Looking up A and AAAA records for:" "$1"
    }
    IP=($(lk_hosts_get_records +VALUE A,AAAA "$1")) || return
    if [ ${#IP[@]} -eq 0 ]; then
        ! lk_verbose || {
            lk_console_detail "No A or AAAA records returned"
            lk_console_detail "Looking up CNAME record for:" "$1"
        }
        CNAME=($(lk_hosts_get_records +VALUE CNAME "$1")) || return
        if [ ${#CNAME[@]} -eq 1 ]; then
            ! lk_verbose ||
                lk_console_detail "CNAME record from $NAMESERVER for $1:" \
                    "${CNAME[0]}"
            lk_host_ns_resolve "${CNAME[0]%.}" || return
            return 0
        fi
    fi
    [ ${#IP[@]} -gt 0 ] || lk_warn "could not resolve $1: $NAMESERVER" || return
    ! lk_verbose || lk_console_detail "A and AAAA records from $NAMESERVER for $1:" \
        "$(lk_echo_array IP)"
    lk_echo_array IP
}

function lk_node_is_host() {
    local NODE_IP HOST_IP
    NODE_IP=($(lk_node_public_ipv4)) &&
        NODE_IP+=($(lk_node_public_ipv6)) &&
        [ ${#NODE_IP} -gt 0 ] ||
        lk_warn "public IP address not found" || return
    HOST_IP=($(lk_host_ns_resolve "$1")) ||
        lk_warn "unable to retrieve authoritative DNS records for $1" || return
    # True if at least one node IP matches a host IP
    [ "$(comm -12 \
        <(lk_echo_array HOST_IP) \
        <(lk_echo_array NODE_IP) | wc -l)" -gt 0 ]
}

if lk_is_macos; then
    function lk_tcp_listening_ports() {
        netstat -nap tcp | sed "/${S}LISTEN$S*\$/!d" |
            awk '{print $4}' |
            sed -E 's/.*\.([0-9]+)$/\1/' |
            sort -nu
    }
else
    function lk_tcp_listening_ports() {
        ss -nHO --listening --tcp |
            awk '{print $4}' |
            sed -E 's/.*:([0-9]+)$/\1/' |
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
    gnu_nc -z -w "${3:-5}" "$1" "$2" >/dev/null 2>&1
}

function lk_certbot_install() {
    local EMAIL=${LK_LETSENCRYPT_EMAIL-${LK_ADMIN_EMAIL:-}} DOMAIN DOMAINS_OK
    lk_test_many "lk_is_fqdn" "$@" || lk_warn "invalid domain(s): $*" || return
    [ -n "$EMAIL" ] || lk_warn "email address not set" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    for DOMAIN in "$@"; do
        lk_node_is_host "$DOMAIN" &&
            lk_console_log "Domain resolves to this system:" "$DOMAIN" ||
            lk_console_warning -r \
                "Domain does not resolve to this system:" "$DOMAIN" ||
            DOMAINS_OK=0
    done
    ! lk_is_false DOMAINS_OK ||
        lk_is_true LK_LETSENCRYPT_IGNORE_DNS ||
        lk_confirm "Ignore domain resolution errors?" N || return
    lk_elevate certbot run \
        --non-interactive \
        --keep-until-expiring \
        --expand \
        --agree-tos \
        --email "$EMAIL" \
        --no-eff-email \
        --"${LK_CERTBOT_PLUGIN:-apache}" \
        ${LK_CERTBOT_OPTIONS[@]:+"${LK_CERTBOT_OPTIONS[@]}"} \
        --domains "$(lk_implode_args "," "$@")"
}

# lk_cpanel_get_ssl_cert SSH_HOST DOMAIN [TARGET_DIR]
function lk_cpanel_get_ssl_cert() {
    local TARGET_DIR=${3:-~/ssl} SSL_JSON CERT KEY \
        LK_TTY_NO_FOLD=1 LK_FILE_TAKE_BACKUP=1
    [ $# -ge 2 ] && lk_is_fqdn "$2" || lk_usage "\
Usage: $(lk_myself -f) SSH_HOST DOMAIN [TARGET_DIR]

Use fetch_best_for_domain to retrieve the best available SSL certificate,
CA bundle and private key for DOMAIN from SSH_HOST to TARGET_DIR
(default: ~/ssl)." || return
    TARGET_DIR=${TARGET_DIR%/}
    [ -e "$TARGET_DIR" ] ||
        install -d -m 00750 "$TARGET_DIR" &&
        lk_maybe_install -m 00640 /dev/null "$TARGET_DIR/$2.cert" &&
        lk_maybe_install -m 00640 /dev/null "$TARGET_DIR/$2.key" || return
    lk_console_message "Retrieving SSL certificate"
    lk_console_detail "Host:" "$1"
    lk_console_detail "Domain:" "$2"
    SSL_JSON=$(ssh "$1" uapi --output=json \
        SSL fetch_best_for_domain domain="$2") &&
        CERT=$(jq -r '.result.data.crt' <<<"$SSL_JSON") &&
        CA_BUNDLE=$(jq -r '.result.data.cab' <<<"$SSL_JSON") &&
        KEY=$(jq -r '.result.data.key' <<<"$SSL_JSON") ||
        lk_warn "unable to retrieve SSL certificate for domain $2" || return
    lk_console_message "Verifying certificate"
    lk_ssl_verify_cert "$CERT" "$KEY" "$CA_BUNDLE" || return
    lk_console_message "Writing certificate files"
    lk_console_detail \
        "Certificate and CA bundle:" "$(lk_pretty_path "$TARGET_DIR/$2.cert")"
    lk_console_detail \
        "Private key:" "$(lk_pretty_path "$TARGET_DIR/$2.key")"
    lk_file_replace "$TARGET_DIR/$2.cert" \
        "$(lk_echo_args "$CERT" "$CA_BUNDLE")" &&
        lk_file_replace "$TARGET_DIR/$2.key" "$KEY"
}

# lk_ssl_verify_cert CERT KEY [CA_BUNDLE]
function lk_ssl_verify_cert() {
    local CERT=$1 KEY=$2 CA_BUNDLE=${3:-}
    openssl verify \
        ${CA_BUNDLE:+-CAfile <(cat <<<"$CA_BUNDLE")} <<<"$CERT" >/dev/null ||
        lk_warn "invalid certificate chain" || return
    openssl x509 -noout -checkend 86400 <<<"$CERT" >/dev/null ||
        lk_warn "certificate has expired" || return
    CERT_MODULUS=$(openssl x509 -noout -modulus <<<"$CERT") &&
        KEY_MODULUS=$(openssl rsa -noout -modulus <<<"$KEY") &&
        [ "$CERT_MODULUS" = "$KEY_MODULUS" ] ||
        lk_warn "certificate and private key have different modulus" || return
    lk_console_log "SSL certificate and private key verified"
}

function _lk_option_check() {
    { { [ $# -gt 0 ] &&
        echo -n "$1" ||
        lk_maybe_sudo cat "$FILE"; } |
        grep -E "$CHECK_REGEX"; } >/dev/null 2>&1
}

# lk_option_set [-p] FILE SETTING CHECK_REGEX [REPLACE_REGEX...]
#
# If CHECK_REGEX doesn't match any lines in FILE, replace each REPLACE_REGEX
# match with SETTING until there's a match for CHECK_REGEX. If there is still no
# match, append SETTING to FILE.
#
# If -p is set, pass each REPLACE_REGEX to sed as-is, otherwise pass
# "0,/REPLACE_REGEX/{s/REGEX/SETTING/}" (after escaping SETTING).
function lk_option_set() {
    local FILE SETTING CHECK_REGEX REPLACE_WITH PRESERVE
    [ "${1:-}" != -p ] || {
        PRESERVE=
        shift
    }
    [ $# -ge 3 ] || lk_usage "\
Usage: $(lk_myself -f) [-p] FILE SETTING CHECK_REGEX [REPLACE_REGEX...]" || return
    FILE=$1
    SETTING=$2
    CHECK_REGEX=$3
    ! _lk_option_check || return 0
    lk_maybe_sudo test -e "$FILE" ||
        { lk_maybe_install -d -m 00755 "${FILE%/*}" &&
            lk_maybe_install -m 00644 /dev/null "$FILE"; } || return
    lk_maybe_sudo test -f "$FILE" || lk_warn "file not found: $FILE" || return
    lk_file_get_text "$FILE" _FILE || return
    [ "${PRESERVE+1}" = 1 ] ||
        REPLACE_WITH=$(lk_escape_ere_replace "$SETTING")
    shift 3
    for REGEX in "$@"; do
        _FILE=$(gnu_sed -E \
            ${PRESERVE+"$REGEX"} \
            ${PRESERVE-"0,/$REGEX/{s/$REGEX/$REPLACE_WITH/}"} <<<"$_FILE"$'\n.') &&
            _FILE=${_FILE%$'\n.'} || return
        ! _lk_option_check "$_FILE" || {
            lk_file_keep_original "$FILE" &&
                lk_file_replace "$FILE" "$_FILE" || return
            return 0
        }
    done
    # Get a clean copy of FILE in case of buggy regex
    lk_file_get_text "$FILE" _FILE &&
        lk_file_keep_original "$FILE" &&
        lk_file_replace "$FILE" "$_FILE$SETTING"
}

# lk_conf_set_option OPTION VALUE [FILE]
function lk_conf_set_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1=$2" \
        "^$S*$OPTION$S*=$S*$VALUE$S*\$" \
        "^$S*$OPTION$S*=.*" "^$S*#$S*$OPTION$S*=.*"
}

# lk_conf_enable_row ROW [FILE]
function lk_conf_enable_row() {
    local ROW FILE=${2:-$LK_CONF_OPTION_FILE}
    ROW=$(lk_regex_expand_whitespace "$(lk_escape_ere "$1")")
    lk_option_set "$FILE" \
        "$1" \
        "^$ROW\$" \
        "^$S*$ROW$S*\$" "^$S*#$S*$ROW$S*\$"
}

# lk_php_set_option OPTION VALUE [FILE]
function lk_php_set_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1=$2" \
        "^$S*$OPTION$S*=$S*$VALUE$S*\$" \
        "^$S*$OPTION$S*=.*" "^$S*;$S*$OPTION$S*=.*"
}

# lk_php_enable_option OPTION VALUE [FILE]
function lk_php_enable_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_escape_ere "$1")
    VALUE=$(lk_escape_ere "$2")
    lk_option_set "$FILE" \
        "$1=$2" \
        "^$S*$OPTION$S*=$S*$VALUE$S*\$" \
        "^$S*;$S*$OPTION$S*=$S*$VALUE$S*\$"
}

# lk_httpd_set_option OPTION VALUE [FILE]
function lk_httpd_set_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    REPLACE_WITH=$(lk_escape_ere_replace "$1 $2")
    lk_option_set -p "$FILE" \
        "$1 $2" \
        "^$S*$OPTION$S+$VALUE$S*\$" \
        "0,/^$S*$OPTION$S+.*/{s/^($S*)$OPTION$S+.*/\\1$REPLACE_WITH/}" \
        "0,/^$S*#$S*$OPTION$S+.*/{s/^($S*)#$S*$OPTION$S+.*/\\1$REPLACE_WITH/}"
}

# lk_httpd_enable_option OPTION VALUE [FILE]
function lk_httpd_enable_option() {
    local OPTION VALUE FILE=${3:-$LK_CONF_OPTION_FILE}
    OPTION=$(lk_regex_case_insensitive "$(lk_escape_ere "$1")")
    VALUE=$(lk_regex_expand_whitespace "$(lk_escape_ere "$2")")
    REPLACE_WITH=$(lk_escape_ere_replace "$1 $2")
    lk_option_set -p "$FILE" \
        "$1 $2" \
        "^$S*$OPTION$S+$VALUE$S*\$" \
        "0,/^$S*#$S*$OPTION$S+$VALUE$S*\$/{s/^($S*)#$S*$OPTION$S+$VALUE$S*\$/\\1$REPLACE_WITH/}"
}

# _lk_crontab REMOVE_REGEX ADD_COMMAND
function _lk_crontab() {
    local REGEX=${1:+".*$1.*"} ADD_COMMAND=${2:-} TYPE=${2:+a}${1:+r} \
        CRONTAB HAD_CRONTAB NEW_CRONTAB
    lk_command_exists crontab || lk_warn "crontab required" || return
    CRONTAB=$(lk_maybe_sudo crontab -l 2>/dev/null) &&
        HAD_CRONTAB= ||
        CRONTAB=
    [ "$TYPE" != ar ] ||
        [[ $ADD_COMMAND =~ $REGEX ]] ||
        lk_warn "command does not match regex" || return
    case "$TYPE" in
    a | ar)
        REGEX=${REGEX:-"^$S*$(lk_regex_expand_whitespace \
            "$(lk_escape_ere "$ADD_COMMAND")")$S*\$"}
        # If the command is already present, replace the first occurrence and
        # delete any duplicates
        if grep -E "$REGEX" >/dev/null <<<"$CRONTAB"; then
            NEW_CRONTAB=$(gnu_sed -E "0,/$REGEX/{s/$REGEX/$(
                lk_escape_ere_replace "$ADD_COMMAND"
            )/};t;/$REGEX/d" <<<"$CRONTAB")
        else
            # Otherwise, add it to the end of the file
            NEW_CRONTAB=${CRONTAB:+$CRONTAB$'\n'}$ADD_COMMAND
        fi
        ;;
    r)
        NEW_CRONTAB=$(sed -E "/$REGEX/d" <<<"$CRONTAB")
        ;;
    *)
        false || lk_warn "invalid arguments"
        ;;
    esac || return
    if [ -z "$NEW_CRONTAB" ]; then
        [ -z "${HAD_CRONTAB+1}" ] || {
            lk_console_message "Removing empty crontab for user '$(lk_me)'"
            lk_maybe_sudo crontab -r
        }
    else
        [ "$NEW_CRONTAB" = "$CRONTAB" ] || {
            local VERB=${HAD_CRONTAB-Creating}${HAD_CRONTAB+Updating}
            LK_TTY_COLOUR2='' \
                lk_console_item "$VERB crontab for user '$(lk_me)'" \
                "$(gnu_diff --color=always \
                    <([ -z "$CRONTAB" ] || cat <<<"$CRONTAB") \
                    <(cat <<<"$NEW_CRONTAB"))"
            lk_maybe_sudo crontab - <<<"$NEW_CRONTAB"
        }
    fi
}

# lk_crontab_add COMMAND
function lk_crontab_add() {
    _lk_crontab "" "${1:-}"
}

# lk_crontab_remove REGEX
function lk_crontab_remove() {
    _lk_crontab "${1:-}" ""
}

# lk_crontab_apply CHECK_REGEX COMMAND
function lk_crontab_apply() {
    _lk_crontab "${1:-}" "${2:-}"
}

# lk_crontab_remove_command COMMAND
function lk_crontab_remove_command() {
    _lk_crontab "$(lk_regex_expand_whitespace "$(lk_escape_ere "${1:-}")")" ""
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
            awk -v"p=$((POWER - 1))" \
            '/^MemTotal\W/{print int($2/1024^p)}' \
            /proc/meminfo
    elif lk_is_macos; then
        sysctl -n hw.memsize |
            lk_require_output \
                awk -v"p=$POWER" '{print int($1/1024^p)}'
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
            awk -v"p=$((POWER - 1))" \
            '/^MemAvailable\W/{print int($2/1024^p)}' \
            /proc/meminfo
    elif lk_is_macos; then
        vm_stat |
            lk_require_output \
                awk -v"p=$POWER" \
                -F"[^0-9]+" \
                'NR==1{b=$2;FS=":"} /^Pages free\W/{print int(b*$2/1024^p)}'
    else
        false
    fi
}

lk_provide provision

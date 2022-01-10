#!/bin/bash

if [[ ! ${1-} =~ ^(--new|--old)$ ]]; then

    lk_bin_depth=1 . lk-bash-load.sh || exit
    lk_require provision

    # TODO: implement NEW_PASSWORD
    _NEW_HOST_NAME=
    NEW_USER=
    NEW_HOST=
    NEW_KEY_FILE=
    NEW_KEY=
    NEW_PASSWORD=

    _OLD_HOST_NAME=
    OLD_USER=
    OLD_HOST=
    OLD_KEY=
    OLD_PASSWORD=

    LK_USAGE="\
${0##*/} [OPTIONS] [USER@]SOURCE[:PORT] [USER@]TARGET[:PORT]

Configure SSH hosts and keys for access to SOURCE from TARGET using private keys
held only in an authentication agent on the local system. Requires lk-platform
to be installed on TARGET.

OPTIONS

    -o, --source-name=HOST          specify the SSH host name for SOURCE
    -n, --target-name=HOST          specify the SSH host name for TARGET
    -k, --source-key=FILE           use key in FILE when logging into SOURCE
    -i, --target-key=FILE           use key in FILE when logging into TARGET
    -p, --source-password=PASSWORD  use PASSWORD when logging into SOURCE

EXAMPLES

    If 'lk-mysite' is already configured as an SSH host on the local system:

\\        ${0##*/} -p 'Passw0rd!' mysite@198.51.100.42:4001 lk-mysite

    If SSH hosts 'new-mysite' and 'old-mysite' are already configured on the
    local system and TARGET respectively:

\\        ${0##*/} -p 'Passw0rd!' old-mysite new-mysite"

    lk_getopt "o:n:k:i:p:" \
        "source-name:,target-name:,source-key:,target-key:,source-password:"
    eval "set -- $LK_GETOPT"

    while :; do
        OPT=$1
        shift
        case "$OPT" in
        -o | --source-name)
            _OLD_HOST_NAME=$1
            ;;
        -n | --target-name)
            _NEW_HOST_NAME=$1
            ;;
        -k | --source-key)
            [ -f "$1" ] || lk_warn "file not found: $1" || lk_usage
            OLD_KEY=$(lk_ssh_get_public_key "$1" 2>/dev/null) ||
                lk_warn "invalid key file: $1" || lk_usage
            ;;
        -i | --target-key)
            [ -f "$1" ] || lk_warn "file not found: $1" || lk_usage
            NEW_KEY=$(lk_ssh_get_public_key "$1" 2>/dev/null) ||
                lk_warn "invalid key file: $1" || lk_usage
            NEW_KEY_FILE=$1
            ;;
        -p | --source-password)
            OLD_PASSWORD=$1
            ;;
        -w | --target-password)
            NEW_PASSWORD=$1
            ;;
        --)
            break
            ;;
        esac
        shift
    done

    case "$#" in
    2)
        [[ $1 =~ ^(([^@]+)@)?([^@]+)$ ]] || lk_usage
        OLD_USER=${BASH_REMATCH[2]}
        OLD_HOST=${BASH_REMATCH[3]}
        [[ $2 =~ ^(([^@]+)@)?([^@]+)$ ]] || lk_usage
        NEW_USER=${BASH_REMATCH[2]}
        NEW_HOST=${BASH_REMATCH[3]}
        shift 2
        ;;
    *)
        lk_usage
        ;;
    esac

fi

STAGE=${1:-local}
STAGE=${STAGE#--}
if [ "$STAGE" = "local" ]; then
    SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX}
    NEW_HOST_NAME=${_NEW_HOST_NAME:-${NEW_USER:-$NEW_HOST}}
    NEW_HOST_NAME=${_NEW_HOST_NAME:-$SSH_PREFIX${NEW_HOST_NAME#"$SSH_PREFIX"}}
elif [ "$STAGE" = "new" ]; then
    . lk-bash-load.sh || exit
    lk_require provision

    SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX}
    NEW_HOST_NAME={{NEW_HOST_NAME}}
    NEW_KEY={{NEW_KEY}}
    OLD_USER={{OLD_USER}}
    OLD_HOST={{OLD_HOST}}
    OLD_KEY={{OLD_KEY}}
    OLD_PASSWORD={{OLD_PASSWORD}}
    _OLD_HOST_NAME={{_OLD_HOST_NAME}}
    OLD_HOST_NAME=${_OLD_HOST_NAME:-${OLD_USER:-$OLD_HOST}-old}
    OLD_HOST_NAME=${_OLD_HOST_NAME:-$SSH_PREFIX${OLD_HOST_NAME#"$SSH_PREFIX"}}
else
    set -euo pipefail
    LK_BOLD={{LK_BOLD}}
    LK_CYAN={{LK_CYAN}}
    LK_YELLOW={{LK_YELLOW}}
    LK_GREY={{LK_GREY}}
    LK_RESET={{LK_RESET}}
fi

function lk_console_message() {
    echo "\
$LK_GREY[ $H ] \
$LK_RESET$LK_BOLD${_LK_TTY_COLOUR-$LK_CYAN}${_LK_TTY_PREFIX-==> }\
$LK_RESET${_LK_TTY_MESSAGE_COLOUR-$LK_BOLD}\
$(sed "1b
s/^/$H_SPACES${_LK_TTY_SPACES-  }/" <<<"$1")$LK_RESET" >&2
}

function lk_console_item() {
    lk_console_message "\
$1$LK_RESET${_LK_TTY_COLOUR2-${_LK_TTY_COLOUR-$LK_CYAN}}$(
        [ "${2/$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"${2#$'\n'}"
    )"
}

function lk_console_detail() {
    local _LK_TTY_PREFIX=" -> " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR=$LK_YELLOW _LK_TTY_MESSAGE_COLOUR=
    [ $# -le 1 ] &&
        lk_console_message "$1" ||
        lk_console_item "$1" "$2"
}

function lk_console_log() {
    local _LK_TTY_PREFIX=" :: " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR2=${_LK_TTY_COLOUR2-$LK_BOLD}
    [ $# -le 1 ] &&
        lk_console_message "${_LK_TTY_COLOUR-$LK_CYAN}$1" ||
        lk_console_item "${_LK_TTY_COLOUR-$LK_CYAN}$1" "$2"
}

function lk_ellipsis() {
    [ "$1" -gt 3 ] &&
        [[ $2 =~ ^(.{$(($1 - 3))}).{4,} ]] &&
        echo "${BASH_REMATCH[1]}..." ||
        echo "$2"
}

function add_authorized_key() {
    local FILE DIR
    FILE=~/.ssh/authorized_keys
    DIR=~/.ssh
    if ! grep -Fxq "$1" "$FILE" 2>/dev/null; then
        lk_console_item "Adding public key to" "$FILE"
        mkdir -p "$DIR" &&
            cat >>"$FILE" <<<"$1" || return
    else
        lk_console_item "Public key already present in" "$FILE"
    fi
    chmod 700 "$DIR" &&
        chmod 600 "$FILE"
}

H=${HOSTNAME:-$(hostname -s)} || H="<unknown>"
H=$(lk_ellipsis 10 "$(printf '%10s' "$H")")
H_SPACES="               "

case "$STAGE" in
local)
    lk_console_message "Configuring SSH"
    lk_ssh_configure
    lk_ssh_host_exists "$NEW_HOST_NAME" || {
        NEW_HOST_NAME=$SSH_PREFIX${NEW_HOST_NAME#"$SSH_PREFIX"}
        lk_console_detail \
            "Adding host:" "$NEW_HOST_NAME (${NEW_USER:+$NEW_USER@}$NEW_HOST)"
        lk_ssh_add_host -t \
            "$NEW_HOST_NAME" \
            "$NEW_HOST" \
            "$NEW_USER" \
            "${NEW_KEY_FILE-}" \
            "${LK_SSH_JUMP_HOST:+jump}"
    }

    lk_console_item "Connecting to" "$NEW_HOST_NAME"
    ssh -o LogLevel=QUIET -t \
        "${NEW_USER:+$NEW_USER@}$NEW_HOST_NAME" \
        "bash -c$(printf ' %q' "$(lk_expand_template -q "$0")" bash --new)"
    ;;

new)
    lk_console_message "Configuring SSH"
    lk_ssh_configure
    [ -z "$NEW_KEY" ] ||
        add_authorized_key "$NEW_KEY"
    lk_ssh_host_exists "$OLD_HOST_NAME" || {
        OLD_HOST_NAME=$SSH_PREFIX${OLD_HOST_NAME#"$SSH_PREFIX"}
        lk_console_detail \
            "Adding host:" "$OLD_HOST_NAME (${OLD_USER:+$OLD_USER@}$OLD_HOST)"
        [ -n "$OLD_KEY" ] &&
            KEY_FILE=- ||
            KEY_FILE=${LK_SSH_JUMP_HOST:+jump}
        lk_ssh_add_host -t \
            "$OLD_HOST_NAME" \
            "$OLD_HOST" \
            "$OLD_USER" \
            "$KEY_FILE" \
            "${LK_SSH_JUMP_HOST:+jump}" <<<"$OLD_KEY"
    }
    KEY_FILE=$(lk_ssh_get_host_key_files "$OLD_HOST_NAME" | head -n1) ||
        lk_die "no IdentityFile for host $OLD_HOST_NAME"
    KEY=$(lk_ssh_get_public_key "$KEY_FILE") ||
        lk_die "no public key for $KEY_FILE"

    lk_console_item "Connecting to" "$OLD_HOST_NAME"
    if [ -n "$OLD_PASSWORD" ]; then
        SSH_ASKPASS=$(mktemp)
        lk_console_detail "Creating temporary SSH_ASKPASS script:" "$SSH_ASKPASS"
        cat <<EOF >"$SSH_ASKPASS"
#!/bin/bash
echo $(printf '%q' "$OLD_PASSWORD")
EOF
        chmod u+x "$SSH_ASKPASS"
        export SSH_ASKPASS
        export DISPLAY=not_really
    else
        lk_console_detail \
            "Password will be requested if public key not already installed"
    fi
    ${OLD_PASSWORD:+setsid -w} ssh -o LogLevel=QUIET -t \
        "${OLD_USER:+$OLD_USER@}$OLD_HOST_NAME" \
        "bash -c$(printf ' %q' "$BASH_EXECUTION_STRING" bash --old "$KEY")" ||
        lk_die "ssh command failed (exit status $?)"
    if [ -n "${SSH_ASKPASS-}" ]; then
        lk_console_detail "Deleting:" "$SSH_ASKPASS"
        rm "$SSH_ASKPASS"
    fi && lk_console_log "\
SSH host '$OLD_HOST_NAME' configured on '$NEW_HOST_NAME' for key-based
access using an authentication agent"
    exit
    ;;

old)
    KEY=$2
    add_authorized_key "$KEY"
    exit
    ;;
*)
    lk_console_item "Invalid arguments:" "$*"
    exit 1
    ;;
esac

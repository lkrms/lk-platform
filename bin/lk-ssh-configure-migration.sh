#!/bin/bash

# shellcheck disable=SC1083,SC1087,SC2015,SC2034

if [[ ! ${1:-} =~ ^(--new|--old)$ ]]; then

    lk_bin_depth=1 include=provision . lk-bash-load.sh || exit

    # TODO: implement TARGET_PASSWORD
    NEW_USER=
    NEW_HOST=
    NEW_KEY=${TARGET_KEY:-}

    # TODO: implement SOURCE_KEY
    OLD_USER=
    OLD_HOST=
    OLD_PASSWORD=${SOURCE_PASSWORD:-}

    LK_USAGE="\
Usage: ${0##*/} [OPTION...] [USER@]SOURCE[:PORT] [USER@]TARGET[:PORT]

Configure SSH hosts and keys on SOURCE, TARGET, and the local system to allow
key-based access to SOURCE from TARGET using private keys held only in an
authentication agent on the local system. Requires lk-platform to be installed
on TARGET.

Options:
  -i, --target-key=FILE             use key in FILE when logging into TARGET
                                    (default: TARGET_KEY from environment)
  -p, --source-password=PASSWORD    use PASSWORD when logging into SOURCE
                                    (default: SOURCE_PASSWORD from environment)"

    lk_check_args
    OPTS=$(
        gnu_getopt --options "i:p:" \
            --longoptions "target-key:,source-password:" \
            --name "${0##*/}" \
            -- "$@"
    ) || lk_usage
    eval "set -- $OPTS"

    while :; do
        OPT=$1
        shift
        case "$OPT" in
        -i | --target-key)
            [ -f "$1" ] || lk_warn "file not found: $1" || lk_usage
            NEW_KEY=$1
            ;;
        -p | --source-password)
            OLD_PASSWORD=$1
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
    NEW_HOST_NAME=$SSH_PREFIX$NEW_USER
elif [ "$STAGE" = "new" ]; then
    include=provision . lk-bash-load.sh || exit
    SSH_PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX}
    NEW_HOST_NAME={{NEW_HOST_NAME}}
    OLD_USER={{OLD_USER}}
    OLD_HOST={{OLD_HOST}}
    OLD_PASSWORD={{OLD_PASSWORD}}
    OLD_HOST_NAME=${SSH_PREFIX}old-$OLD_USER
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
$LK_RESET$LK_BOLD${LK_CONSOLE_COLOUR-$LK_CYAN}${LK_CONSOLE_PREFIX-==> }\
$LK_RESET${LK_CONSOLE_MESSAGE_COLOUR-$LK_BOLD}\
${1//$'\n'/$'\n'"$H_SPACES${LK_CONSOLE_SPACES-  }"}$LK_RESET" >&2
}

function lk_console_item() {
    lk_console_message "\
$1$LK_RESET${LK_CONSOLE_COLOUR2-${LK_CONSOLE_COLOUR-$LK_CYAN}}$(
        [ "${2//$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"$2"
    )"
}

function lk_console_detail() {
    local LK_CONSOLE_PREFIX="   -> " LK_CONSOLE_SPACES="    " \
        LK_CONSOLE_COLOUR=$LK_YELLOW LK_CONSOLE_MESSAGE_COLOUR=
    [ $# -le 1 ] &&
        lk_console_message "$1" ||
        lk_console_item "$1" "$2"
}

function lk_console_log() {
    local LK_CONSOLE_PREFIX=" :: " LK_CONSOLE_SPACES="    " \
        LK_CONSOLE_COLOUR2=$LK_BOLD
    [ $# -le 1 ] &&
        lk_console_message "$LK_CYAN$1" ||
        lk_console_item "$LK_CYAN$1" "$2"
}

function lk_ellipsis() {
    [ "$1" -gt 3 ] &&
        [[ "$2" =~ ^(.{$(($1 - 3))}).{4,} ]] &&
        echo "${BASH_REMATCH[1]}..." ||
        echo "$2"
}

H=${HOSTNAME:-$(hostname -s)} || H="<unknown>"
H=$(lk_ellipsis 10 "$(printf '%10s' "$H")")
H_SPACES="               "

case "$STAGE" in
local)
    lk_console_message "Configuring SSH"
    lk_ssh_configure
    lk_console_detail "Adding host:" "$NEW_HOST_NAME ($NEW_USER@$NEW_HOST)"
    lk_ssh_add_host \
        "$NEW_HOST_NAME" \
        "$NEW_HOST" \
        "$NEW_USER" \
        "${NEW_KEY:-}" \
        "${LK_SSH_JUMP_HOST:-}"

    lk_console_item "Connecting to" "$NEW_HOST_NAME"
    ssh -o LogLevel=QUIET -t "$NEW_HOST_NAME" "bash -c$(
        printf ' %q' "$(LK_EXPAND_QUOTE=1 lk_expand_template "$0")" bash --new
    )"
    ;;

new)
    lk_console_message "Configuring SSH"
    lk_ssh_configure
    lk_console_detail "Adding host:" "$OLD_HOST_NAME ($OLD_USER@$OLD_HOST)"
    lk_ssh_add_host \
        "$OLD_HOST_NAME" \
        "$OLD_HOST" \
        "$OLD_USER" \
        "${LK_SSH_JUMP_KEY:-}" \
        "${LK_SSH_JUMP_HOST:+jump}"

    KEY_FILE=$(ssh -G "$OLD_HOST_NAME" |
        awk '/^identityfile / { print $2 }' |
        lk_expand_paths |
        lk_filter -f |
        head -n1) &&
        [ -n "$KEY_FILE" ] ||
        lk_die "no IdentityFile for host $OLD_HOST_NAME"
    KEY=$(
        # Use the key's .pub file if it's valid
        if [ -f "$KEY_FILE.pub" ] &&
            ssh-keygen -l -f <(cat "$KEY_FILE.pub") >/dev/null 2>&1; then
            cat "$KEY_FILE.pub"
        elif ssh-keygen -l -f <(cat "$KEY_FILE") >/dev/null 2>&1; then
            # Or the key file itself if it's a public key
            cat "$KEY_FILE"
        else
            # Otherwise, get the public key from the private key
            ssh-keygen -y -f "$KEY_FILE"
        fi
    ) || lk_die "no public key for $KEY_FILE"

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
    ${OLD_PASSWORD:+setsid -w} ssh -o LogLevel=QUIET -t "$OLD_HOST_NAME" \
        "bash -c$(printf ' %q' "$BASH_EXECUTION_STRING" bash --old "$KEY")"
    if [ -n "${SSH_ASKPASS:-}" ]; then
        lk_console_detail "Deleting:" "$SSH_ASKPASS"
        rm "$SSH_ASKPASS"
    fi && lk_console_log "\
SSH host '$OLD_HOST_NAME' configured on '$NEW_HOST_NAME' for key-based
access using an authentication agent"
    exit
    ;;

old)
    KEY=$2
    FILE=~/.ssh/authorized_keys
    DIR=~/.ssh
    if ! grep -Fxq "$KEY" "$FILE" 2>/dev/null; then
        lk_console_item "Adding public key to" "$FILE"
        mkdir -p "$DIR"
        cat >>"$FILE" <<<"$KEY"
    else
        lk_console_item "Public key already present in" "$FILE"
    fi
    chmod 700 "$DIR"
    chmod 600 "$FILE"
    exit
    ;;
*)
    lk_console_item "Invalid arguments:" "$*"
    exit 1
    ;;
esac

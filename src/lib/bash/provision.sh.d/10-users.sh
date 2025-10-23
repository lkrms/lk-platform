#!/usr/bin/env bash

# lk_user_exists USER
function lk_user_exists() {
    id "$1" &>/dev/null || return
}

# lk_user_home USER
function lk_user_home() {
    [[ $1 =~ ^[a-zA-Z_][-a-zA-Z0-9\$_]*$ ]] || return
    eval "echo ~${1//\$/\\\$}"
}

# lk_user_groups [USER]
function lk_user_groups() {
    id -Gn ${1+"$1"} | tr -s '[:blank:]' '\n'
}

# lk_user_in_group GROUP [USER]
function lk_user_in_group() {
    lk_user_groups ${2+"$2"} | grep -Fx "$1" >/dev/null
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

# lk_group_exists NAME|GID
function lk_group_exists() {
    lk_list_group_ids | tr '\t' '\n' | grep -Fx "$1" >/dev/null
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
    MATCH="^($LK_h*#)?$LK_h*($REGEX|\"$REGEX\")($LK_h+|$LK_h*=$LK_h*)"
    CONFIG="\
Match Group $SFTP_ONLY
ForceCommand internal-sftp
ChrootDirectory %h"
    lk_file_keep_original "$FILE"
    lk_file_replace "$FILE" < <(awk \
        -v "BLOCK=$CONFIG" \
        -v "FIRST=$MATCH(${REGEX[1]}|\"${REGEX[1]}\")$LK_h+(${SFTP_ONLY}|\"${SFTP_ONLY}\")$LK_h*$" \
        -v "BREAK=$MATCH" \
        -f "$LK_BASE/lib/awk/block-replace.awk" "$FILE")
    ! lk_false LK_FILE_REPLACE_NO_CHANGE ||
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

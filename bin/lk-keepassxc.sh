#!/bin/bash

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

. "$LK_BASE/lib/bash/common.sh"
lk_include secret

lk_assert_not_root
lk_assert_not_wsl
KEEPASSXC=$(lk_command_first_existing \
    keepassxc \
    /Applications/KeePassXC.app/Contents/MacOS/KeePassXC) ||
    lk_die "KeePassXC not found"

DAEMON=1
REGISTER=0
RESET_PASSWORD=0
CHECK_HAS_PASSWORD=0

LK_USAGE="\
Usage: ${0##*/} [OPTION...] DATABASE_FILE...

Use KeePassXC to open each DATABASE_FILE with a password previously stored in
the current user's secret service. If running on a terminal, prompt the user to
enter each missing password.

Options:
  -d, --detach              run KeePassXC in the background
  -r, --reset-password      update the stored password for each database
      --autostart           only register KeePassXC to open each database at startup
      --check-has-password  only prompt for each missing password"

lk_getopt "dr" \
    "detach,reset-password,autostart,check-has-password"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -d | --detach)
        DAEMON=0
        ;;
    -r | --reset-password)
        RESET_PASSWORD=1
        ;;
    --autostart)
        REGISTER=1
        ;;
    --check-has-password)
        CHECK_HAS_PASSWORD=1
        ;;
    --)
        break
        ;;
    esac
done
# --detach, --autostart and --check-has-password are mutually exclusive
[ $(((1 - DAEMON) + CHECK_HAS_PASSWORD + REGISTER)) -le 1 ] || lk_usage

lk_files_exist "$@" || lk_usage

DATABASES=()
PASSWORDS=()

for DATABASE_FILE in "$@"; do
    DATABASE_FILE=$(realpath "$DATABASE_FILE")
    if lk_is_true RESET_PASSWORD; then
        lk_remove_secret "$DATABASE_FILE"
    fi
    PASSWORD="$(lk_secret "$DATABASE_FILE" "KeePassXC password for ${DATABASE_FILE##*/}")" ||
        lk_die "unable to retrieve password for $DATABASE_FILE"
    [ -n "$PASSWORD" ] || lk_die "empty password for $DATABASE_FILE"
    DATABASES+=("$DATABASE_FILE")
    PASSWORDS+=("$PASSWORD")
done

[ ${#PASSWORDS[@]} -gt 0 ] ||
    lk_die "no database to open"

if lk_is_true REGISTER; then
    if lk_is_macos; then
        function plist() {
            defaults write "$_FILE" "$@"
        }
        LABEL=com.linacreative.platform.keepassxc
        FILE=~/Library/LaunchAgents/$LABEL.plist
        _FILE=$(lk_mktemp_dir)/$LABEL.plist && lk_delete_on_exit "${_FILE%/*}"
        plist Disabled -bool false
        plist Label -string "$LABEL"
        plist ProcessType -string "Interactive"
        plist ProgramArguments -array "$(realpath "${BASH_SOURCE[0]}")" "${DATABASES[@]}"
        plist RunAtLoad -bool true
        plist StandardErrorPath -string /tmp/lk-keepassxc.sh.err
        plist StandardOutPath -string /tmp/lk-keepassxc.sh.out
        if ! diff -q \
            <(plutil -convert xml1 -o - "$FILE" 2>/dev/null) \
            <(plutil -convert xml1 -o - "$_FILE") >/dev/null; then
            launchctl unload "$FILE" &>/dev/null || true
            lk_install -d -m 00755 "${FILE%/*}"
            lk_install -m 00644 "$FILE"
            cp "$_FILE" "$FILE"
            launchctl load -w "$FILE"
        fi
    else
        lk_die "--autostart not implemented on this platform"
    fi
    exit
fi

! lk_is_true CHECK_HAS_PASSWORD ||
    exit 0

FIFO=$(lk_mktemp_dir)/fifo
PW_FIFO=${FIFO%/*}/pw_fifo
mkfifo "$FIFO" "$PW_FIFO"
FIFO_FD=$(lk_fd_next)
eval "exec $FIFO_FD"'<>"$FIFO"'
PW_FIFO_FD=$(lk_fd_next)
eval "exec $PW_FIFO_FD"'<>"$PW_FIFO"'

MAIN_PID=$$
if ! lk_is_true DAEMON; then
    nohup \
        "$KEEPASSXC" --pw-stdin "${DATABASES[@]}" \
        <&"$PW_FIFO_FD" >&"$FIFO_FD" 2>/dev/null &
    MAIN_PID=$!
    disown
fi

(
    lk_set_bashpid
    PW_PID=$BASHPID
    (
        while :; do
            sleep 2
            lk_check_pid "$MAIN_PID" || break
        done
        # Stop waiting for a password prompt if KeePassXC is dead
        kill "$PW_PID" 2>/dev/null || true
    ) &
    CHECK_PID=$!
    for PASSWORD in "${PASSWORDS[@]}"; do
        # Wait for the first character of the password prompt
        IFS= read -rd '' -n1 -u"$FIFO_FD" CHAR || break
        # Flush the rest of it
        lk_fifo_flush "$FIFO"
        echo "$PASSWORD" >&"$PW_FIFO_FD"
    done
    kill "$CHECK_PID" 2>/dev/null || true
) &

if lk_is_true DAEMON; then
    # Prevent the subshell spawned above becoming a zombie when KeePassXC fails
    # to reap it
    trap "" SIGCHLD
    exec \
        "$KEEPASSXC" --pw-stdin "${DATABASES[@]}" \
        <&"$PW_FIFO_FD" >&"$FIFO_FD"
fi

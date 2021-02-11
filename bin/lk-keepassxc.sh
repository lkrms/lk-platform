#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015,SC2034

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

include=secret . "$LK_BASE/lib/bash/common.sh"

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
            defaults write "$PLIST" "$@"
        }
        LABEL=com.linacreative.platform.keepassxc
        PLIST=~/Library/LaunchAgents/$LABEL.plist
        launchctl unload "$PLIST" &>/dev/null || true
        plist Disabled -bool false
        plist Label -string "$LABEL"
        plist ProcessType -string "Interactive"
        plist ProgramArguments -array "$(realpath "${BASH_SOURCE[0]}")" "${DATABASES[@]}"
        plist RunAtLoad -bool true
        plist StandardErrorPath -string /tmp/lk-keepassxc.sh.err
        plist StandardOutPath -string /tmp/lk-keepassxc.sh.out
        launchctl load -w "$PLIST"
    else
        lk_die "--autostart not implemented on this platform"
    fi
    exit
fi

! lk_is_true CHECK_HAS_PASSWORD ||
    exit 0

if lk_is_true DAEMON; then
    exec "$KEEPASSXC" \
        --pw-stdin "${DATABASES[@]}"
else
    nohup "$KEEPASSXC" \
        --pw-stdin "${DATABASES[@]}" &>/dev/null &
    disown
fi < <(for PASSWORD in "${PASSWORDS[@]}"; do
    sleep 5
    echo "$PASSWORD"
done)

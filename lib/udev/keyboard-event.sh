#!/usr/bin/env bash

set -euo pipefail
lk_die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }

_DIR=${BASH_SOURCE%"${BASH_SOURCE##*/}"}
LK_BASE=$(cd "${_DIR:-.}/../.." && pwd -P) &&
    [ "$LK_BASE/lib/udev/${BASH_SOURCE##*/}" -ef "$BASH_SOURCE" ] &&
    export LK_BASE || lk_die "LK_BASE not found"

. "$LK_BASE/lib/bash/common.sh"

lk_assert_root

DEVICE=${1-}
[[ $DEVICE =~ ^([0-9a-f]{4}(:|$)){2}$ ]] || lk_usage

FILE=/tmp/.${LK_PATH_PREFIX:-lk-}udev-keyboard-event
# Supported: autorandr_load, dpms_off
_ACTION=autorandr_load
case "${ACTION-}" in
add)
    OTHER_FILE=${FILE}-removed
    FILE+=-added
    ;;
remove)
    OTHER_FILE=${FILE}-added
    FILE+=-removed
    ;;
*)
    lk_die "invalid action: ${ACTION-}"
    ;;
esac

lk_lock || exit 0

rm -f "$OTHER_FILE"
[ ! -f "$FILE" ] || lk_warn "event already processed for $DEVICE" || exit 0
touch "$FILE"

lk_log_open

lk_tty_print "Processing udev keyboard event for $DEVICE"
lk_tty_detail "Action:" "$ACTION"
! lk_debug_is_on ||
    lk_tty_detail "Environment:" "$(printenv | sort)"

SESSIONS=$(
    loginctl list-sessions --no-legend |
        awk '{ print $1 }' |
        xargs loginctl show-session -p Name -p Display -p Remote -p State |
        awk '
function print_active() {
    if (a["Display"] && a["Remote"] == "no" && a["State"] == "active") {
        print a["Name"], a["Display"]
    }
    for (i in a) {
            delete a[i]
    }
}
/=/     { i = index($0, "=")
          p = substr($0, 1, i - 1)
          a[p] = substr($0, i + 1) }
/^$/    { print_active() }
END     { print_active() }'
)

[ -n "$SESSIONS" ] || lk_warn "no active sessions" || exit 0

lk_tty_detail "Active sessions with local displays:" $'\n'"$SESSIONS"

while read -r _USER _DISPLAY; do
    case "$_ACTION" in
    autorandr_load)
        lk_tty_detail "Triggering autorandr on display" "$_DISPLAY"
        ;;
    dpms_off)
        lk_tty_detail "Turning off display" "$_DISPLAY"
        ;;
    esac
    export _ACTION _DISPLAY
    UNSET=("${!_LK_@}")
    env ${UNSET+"${UNSET[@]/#/--unset=}"} runuser -u "$_USER" -- bash -c "$(
        run() {
            autorandr_load() {
                autorandr --change --force
            }
            dpms_off() {
                xset dpms force off
            }
            at now < <(lk_quote_args bash -c "$(
                declare -f "$_ACTION"
                lk_quote_args \
                    DISPLAY=$_DISPLAY XAUTHORITY=~/.Xauthority "$_ACTION"
            ) &>>/tmp/$1-action-\$EUID.out")
        }
        declare -f run lk_quote_args
        lk_quote_args run "${0##*/}"
    ) &>>/tmp/${0##*/}-run-\$EUID.out"
done <<<"$SESSIONS"

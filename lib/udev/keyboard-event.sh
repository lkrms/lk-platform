#!/bin/bash

set -euo pipefail
die() { echo "${BASH_SOURCE:-$0}: $1" >&2 && rm -f "$out" && false || exit; }

_DIR=${BASH_SOURCE%${BASH_SOURCE##*/}}
_DIR=$(cd "${_DIR:-$PWD}" && pwd -P) &&
    export LK_BASE=${_DIR%/*/*} || die "LK_BASE not found"

. "$LK_BASE/lib/bash/common.sh"

lk_assert_is_root

DEVICE=${1-}
[[ $DEVICE =~ ^([0-9a-f]{4}(:|$)){2}$ ]] || lk_usage

FILE=/tmp/.${LK_PATH_PREFIX:-lk-}udev-keyboard-event
case "${ACTION-}" in
add)
    OTHER_FILE=${FILE}-removed
    FILE+=-added
    _ACTION=postswitch
    ;;
remove)
    OTHER_FILE=${FILE}-added
    FILE+=-removed
    _ACTION=dpms_off
    ;;
*)
    lk_die "invalid action: ${ACTION-}"
    ;;
esac

lk_lock || exit 0

rm -f "$OTHER_FILE"
[ ! -f "$FILE" ] || lk_warn "event already processed for $DEVICE" || exit 0
touch "$FILE"

lk_log_start

lk_tty_print "Processing udev keyboard event for $DEVICE"
lk_tty_detail "Action:" "$ACTION"
[ "${LK_DEBUG-}" != 1 ] ||
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

lk_tty_detail "Active sessions with local displays:" $'\n'"$SESSIONS"

while read -r _USER _DISPLAY; do
    case "$_ACTION" in
    postswitch)
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
            postswitch() {
                autorandr --change --default default --force ||
                    AUTORANDR_PROFILE_FOLDER=~/.config/autorandr/default \
                        "$1"
            }
            dpms_off() {
                xset dpms force off
            }
            at now < <(lk_quote_args bash -c "$(
                declare -f "$_ACTION"
                lk_quote_args DISPLAY=$_DISPLAY XAUTHORITY=~/.Xauthority \
                    "$_ACTION" \
                    "$2"
            ) &>>/tmp/$1-action-\$EUID.out")
        }
        declare -f run lk_quote_args
        lk_quote_args run \
            "${0##*/}" \
            "$LK_BASE/lib/autorandr/postswitch"
    ) &>>/tmp/${0##*/}-run-\$EUID.out"
done <<<"$SESSIONS"

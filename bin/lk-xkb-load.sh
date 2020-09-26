#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit

LK_USAGE="Usage: ${0##*/} KEYMAP_FILE"

lk_check_args
[ $# -eq 1 ] || lk_usage
[ -f "$1" ] || lk_die "file not found: $1"

ARGS=(-I"$LK_BASE/etc/X11/xkb")
for DIR in "/etc/X11/xkb" "$HOME/.xkb"; do
    [ ! -d "$DIR" ] || ARGS+=(-I"$DIR")
done

lk_console_item "Updating keymap from file:" "$1"
xkbcomp "${ARGS[@]}" "$1" "$DISPLAY"

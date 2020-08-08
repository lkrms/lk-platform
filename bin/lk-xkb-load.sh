#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && false || exit $s; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "realpath: command not found"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval "printf '/..%.s' {1..$_DEPTH}")") &&
    [ "$LK_BASE" != / ] && [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

include= . "$LK_BASE/lib/bash/common.sh"

[ "$#" -eq "1" ] || lk_usage "Usage: ${0##*/} KEYMAP_FILE"
[ -f "$1" ] || lk_die "file not found: $1"

ARGS=(-I"$LK_BASE/etc/X11/xkb")
for DIR in "/etc/X11/xkb" "$HOME/.xkb"; do
    [ ! -d "$DIR" ] || ARGS+=(-I"$DIR")
done

lk_console_item "Updating keymap from file:" "$1"
xkbcomp "${ARGS[@]}" "$1" "$DISPLAY"

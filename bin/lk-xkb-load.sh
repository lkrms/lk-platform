#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "$(dirname "$BS")/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

include= . "$LK_BASE/lib/bash/common.sh"

[ "$#" -eq "1" ] || lk_usage "Usage: $(basename "$0") KEYMAP_FILE"
[ -f "$1" ] || lk_die "file not found: $1"

ARGS=(-I"$LK_BASE/etc/X11/xkb")
for DIR in "/etc/X11/xkb" "$HOME/.xkb"; do
    [ ! -d "$DIR" ] || ARGS+=(-I"$DIR")
done

lk_console_item "Updating keymap from file:" "$1"
xkbcomp "${ARGS[@]}" "$1" "$DISPLAY"

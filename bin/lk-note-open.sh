#!/usr/bin/env bash

. lk-bash-load.sh || exit

OPEN=$(lk_first_command xdg-open open) ||
    lk_die "command not found: open"

DIR=${LK_NOTE_DIR:-~/Documents/Notes}
FILE=$DIR/Daily/$(lk_date "%Y-%m-%d").md

mkdir -p "${FILE%/*}"

[ -e "$FILE" ] ||
    printf "**Scratchpad for %s**\n\n\n" "$(lk_date "%A, %-d %B %Y")" >>"$FILE"

"$OPEN" "$FILE"

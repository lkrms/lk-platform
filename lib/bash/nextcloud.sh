#!/bin/bash

function lk_nextcloud_get_excluded() {
    (
        shopt -s globstar nullglob || exit
        LIST=(
            ~/.config/**/sync-exclude.lst
            ~/Library/Preferences/**/sync-exclude.lst
        )
        [ "${#LIST[@]}" -eq 1 ] ||
            lk_warn "exactly one sync-exclude.lst required (${#LIST[@]} found)" ||
            return
        FILE="${LIST[0]}"
        eval "LIST=($(sed -Ee '/^([[:blank:]]*$|#)/d' -e 's/^[]\]//' -e 's/[[:blank:]]/\\&/g' -e 's/^/**\//' "$FILE"))"
        lk_console_item "${#LIST[@]} $(lk_maybe_plural "${#LIST[@]}" file files) excluded by $FILE:"
        lk_echo_array LIST
    )
}

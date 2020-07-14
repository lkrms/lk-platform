#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015,SC2034

set -euo pipefail
_FILE="${BASH_SOURCE[0]}" && [ ! -L "$_FILE" ] &&
    LK_BASE="$(cd "${_FILE%/*}/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] ||
    { echo "${_FILE:+$_FILE: }unable to find LK_BASE" >&2 && exit 1; }

include= . "$LK_BASE/lib/bash/common.sh"

lk_elevate

shopt -s nullglob

BACKUP_SUFFIX="-$(lk_timestamp).bak"

lk_console_message "Installing gnu_* symlinks"
lk_install_gnu_commands

RC_FILES=(
    /etc/skel/.bashrc
    /root/.bashrc
    /home/*/.bashrc
    /srv/www/*/.bashrc
)
lk_resolve_files RC_FILES
[ "${#RC_FILES[@]}" -gt "0" ] || lk_die "no ~/.bashrc files found"
lk_echo_array "${RC_FILES[@]}" |
    lk_console_list "Checking ~/.bashrc for all users:" "file" "files"
RC_PATH_QUOTED="$(lk_esc "$LK_BASE/lib/bash/rc.sh")"
BASH_SKEL="
# Added by $(basename "$0") at $(lk_now)
if [ -f \"$RC_PATH_QUOTED\" ]; then
    . \"$RC_PATH_QUOTED\"
fi"
for RC_FILE in "${RC_FILES[@]}"; do
    # fix legacy references to $LK_BASE/**/.bashrc
    lk_maybe_sed -Ee "s/($(
        lk_escape_ere "$LK_BASE"
    ))(\/.*)?\/.bashrc/\1\/lib\/bash\/rc.sh/g" \
        -e "s/'($(
            lk_escape_ere "$LK_BASE"
        )\/lib\/bash\/rc\.sh)'/\"$(
            lk_escape_ere_replace "$RC_PATH_QUOTED"
        )\"/g" \
        "$RC_FILE"

    # source $LK_BASE/lib/bash/rc.sh unless a reference is already present
    grep -Fq "$RC_PATH_QUOTED" "$RC_FILE" || {
        lk_keep_original "$RC_FILE" &&
            echo "$BASH_SKEL" >>"$RC_FILE"
    }
done

if lk_is_linux && lk_is_desktop; then

    if lk_command_exists autorandr; then
        lk_console_message "Configuring autorandr hooks"
        lk_safe_symlink "$LK_BASE/lib/autorandr/postsave" "/etc/xdg/autorandr/postsave"
        lk_safe_symlink "$LK_BASE/lib/autorandr/postswitch" "/etc/xdg/autorandr/postswitch"
    fi

fi

lk_console_message "lk-platform successfully installed" "$LK_GREEN"

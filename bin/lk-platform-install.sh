#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "${BS%/*}/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

include= . "$LK_BASE/lib/bash/common.sh"

lk_elevate

lk_console_message "Configuring gnu_* symlinks"
lk_install_gnu_commands

if lk_is_desktop; then

    if lk_command_exists autorandr; then
        lk_console_message "Configuring autorandr hooks"
        lk_safe_symlink "$LK_BASE/lib/autorandr/postsave" "/etc/xdg/autorandr/postsave"
        lk_safe_symlink "$LK_BASE/lib/autorandr/postswitch" "/etc/xdg/autorandr/postswitch"
    fi

fi

lk_console_message "lk-platform successfully installed" "$LK_GREEN"

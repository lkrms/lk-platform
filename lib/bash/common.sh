#!/bin/bash
# shellcheck disable=SC1090,SC1091,SC2001,SC2030,SC2031,SC2034

[ ! -f "/etc/default/lk-platform" ] || . "/etc/default/lk-platform"
LK_PATH_PREFIX="${LK_PATH_PREFIX:-lk-}"
LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(echo "$LK_PATH_PREFIX" |
    sed 's/[^a-zA-Z0-9]//g')}"
[ ! -f "${HOME:+$HOME/.${LK_PATH_PREFIX}settings}" ] ||
    . "$HOME/.${LK_PATH_PREFIX}settings"

[ -n "${LK_BASE:-}" ] ||
    eval "$(
        BS="${BASH_SOURCE[0]}"
        if [ ! -L "$BS" ] &&
            LK_BASE="$(cd "$(dirname "$BS")/../.." && pwd -P)" &&
            [ -d "$LK_BASE/lib/bash" ]; then
            echo "LK_BASE=\"$(lk_esc "$LK_BASE")\""
        else
            echo "$BS: LK_BASE not set" >&2
        fi
    )"
export LK_BASE

. "$LK_BASE/lib/bash/core.sh"
. "$LK_BASE/lib/bash/assert.sh"

function _lk_include() {
    local INCLUDE INCLUDE_PATH
    for INCLUDE in ${LK_INCLUDE:+${LK_INCLUDE//,/ }}; do
        INCLUDE_PATH="$LK_BASE/lib/bash/$INCLUDE.sh"
        [ -r "$INCLUDE_PATH" ] ||
            lk_warn "file not found: $INCLUDE_PATH" || return
        echo ". \"\$LK_BASE/lib/bash/$INCLUDE.sh\""
    done
}

function lk_has_arg() {
    lk_in_array "$1" LK_ARGV
}

function lk_elevate() {
    [ "$EUID" -eq "0" ] || {
        sudo -H "$0" "$@"
        exit
    }
}

lk_trap_err

eval "$(. "$LK_BASE/lib/bash/env.sh")"

LK_ARGV=("$@")

eval "$(LK_INCLUDE="${LK_INCLUDE:-${INCLUDE:-${include:-}}}" _lk_include)"
unset LK_INCLUDE

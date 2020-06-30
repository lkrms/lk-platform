#!/bin/bash
# shellcheck disable=SC1090,SC2034

[ -n "${LK_BASE:-}" ] || {
    echo "${BASH_SOURCE[0]}: LK_BASE not set" >&2
    exit 1
}

[ ! -f "$LK_BASE/etc/server.conf" ] ||
    . "$LK_BASE/etc/server.conf"

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
        sudo "$0" "$@"
        exit
    }
}

lk_trap_err

LK_ARGV=("$@")

eval "$(LK_INCLUDE="${LK_INCLUDE:-${INCLUDE:-${include:-}}}" _lk_include)"
unset LK_INCLUDE

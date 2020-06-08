#!/bin/bash

[ -n "${LK_BASE:-}" ] || {
    echo "${BASH_SOURCE[0]}: LK_BASE not set" >&2
    exit 1
}

[ ! -f "$LK_BASE/etc/server.conf" ] ||
    . "$LK_BASE/etc/server.conf"

. "$LK_BASE/lib/bash/core.sh"

lk_trap_err

function lk_elevate() {
    [ "$EUID" -eq "0" ] || {
        sudo "$0" "$@"
        exit
    }
}

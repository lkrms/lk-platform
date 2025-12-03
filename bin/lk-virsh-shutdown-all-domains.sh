#!/usr/bin/env bash

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

. "$LK_BASE/lib/bash/common.sh"
lk_require linux

lk_assert_is_linux

unset _USER
lk_user_is_root || {
    _USER=
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$EUID}
}
lk_systemctl_running ${_USER+-u} libvirtd.service ||
    lk_warn "libvirtd not running; skipping" ||
    exit 0

function virsh() {
    command virsh "$@" </dev/null
}

virsh connect &>/dev/null ||
    lk_die "unable to connect to default URI"

i=0
while [ $((SECONDS + 5)) -lt 120 ] || (((i - 1) % 5)); do
    ! ((i)) || sleep 1
    PENDING=0
    PENDING_DOMAINS=()
    while IFS= read -r DOMAIN; do
        ((++PENDING))
        if ! ((i % 5)); then
            virsh shutdown "$DOMAIN" >/dev/null
            PENDING_DOMAINS+=("$DOMAIN")
        fi
    done < <(virsh list --name | sed '/^$/d')
    if ((PENDING)); then
        if ((i % 5)); then
            printf '.' >&"${_LK_FD-2}"
        else
            ! ((i)) || printf '\r' >&"${_LK_FD-2}"
            lk_tty_detail \
                "Shutdown pending:" "$(lk_implode_arr ", " PENDING_DOMAINS)"
        fi
    else
        break
    fi
    ((++i))
done

printf '\r' >&"${_LK_FD-2}"

! ((PENDING)) &&
    lk_tty_success "All libvirt domains shut down successfully" ||
    lk_tty_error -r "Unable to shut down all libvirt domains" || lk_die ""

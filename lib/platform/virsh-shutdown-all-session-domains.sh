#!/bin/bash

set -euo pipefail
_DEPTH=2
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

lk_assert_root

IFS=$'\n'
SESSION_USERS=($(pgrep -x libvirtd |
    xargs ps -o user= |
    sort -u |
    sed '/^root$/d'))

STATUS=0
i=0
for _USER in ${SESSION_USERS[@]+"${SESSION_USERS[@]}"}; do
    ! ((i)) || lk_console_blank
    lk_console_item "Shutting down libvirt session domains for user:" "$_USER"
    lk_run_as "$_USER" "$LK_BASE/bin/lk-virsh-shutdown-all.sh" ||
        lk_warn "shutdown command failed" || STATUS=$?
    ((++i))
done

(exit "$STATUS") || lk_die ""

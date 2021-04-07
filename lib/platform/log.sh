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

include= . "$LK_BASE/lib/bash/common.sh"

[ $# -gt 0 ] &&
    { lk_command_exists "$1" || lk_warn "command not found: $1"; } ||
    lk_usage "\
Usage: ${0##*/} COMMAND [ARG...]"

[ -n "${LK_LOG_BASENAME:-}" ] ||
    LK_LOG_BASENAME=${1##*/}-$(lk_hash "$@")
export -n LK_LOG_BASENAME

_LK_LOG_CMDLINE=("$@")
lk_log_start

exec "$@"

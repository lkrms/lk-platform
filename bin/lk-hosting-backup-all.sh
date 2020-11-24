#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2153,SC2206

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (return $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval "printf '/..%.s' {1..$_DEPTH}")") &&
    [ "$LK_BASE" != / ] && [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

include='' . "$LK_BASE/lib/bash/common.sh"

lk_elevate

BACKUP_ROOT=${LK_BACKUP_ROOT:-/srv/backup}
install -d -m 00751 -g adm "$BACKUP_ROOT"

# Use one timestamp for all snapshots in this batch
LK_BACKUP_TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
export LK_BACKUP_TIMESTAMP

IFS=':'
BASE_DIRS=(
    /srv/www
    ${LK_BACKUP_BASE_DIRS:-}
    "$@"
)
lk_resolve_files BASE_DIRS
[ ${#BASE_DIRS[@]} -gt 0 ] ||
    lk_die "no base directories found"
unset IFS
lk_mapfile <(comm -12 \
    <(getent passwd | cut -d: -f6 | sort -u) \
    <(find "${BASE_DIRS[@]}" -mindepth 1 -maxdepth 1 -type d | sort |
        sed -E '/^\/(proc|sys|dev|run|tmp)$/d')) SOURCES
[ ${#SOURCES[@]} -gt 0 ] ||
    lk_die "nothing to back up"
lk_echo_array SOURCES |
    lk_console_list "Creating local snapshot of:" account accounts

for SOURCE in "${SOURCES[@]}"; do
    OWNER=$(lk_file_owner "$SOURCE")
    GROUP=$(id -gn "$OWNER")
    "$LK_BASE/bin/lk-backup-create-snapshot.sh" \
        "${SOURCE##*/}" "$SOURCE" "$BACKUP_ROOT" \
        --chown="root:$GROUP" \
        --chmod=go-w
done

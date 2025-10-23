#!/usr/bin/env bash

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
# Provides `lk_maybe_trace`
lk_include provision

lk_elevate

export TZ=UTC

lk_log_start
lk_start_trace

{
    BACKUP_ROOT=${LK_BACKUP_ROOT:-/srv/backup}
    install -d -m 00751 -g adm "$BACKUP_ROOT"{,/archive}

    # Use one timestamp for all snapshots in this batch
    LK_BACKUP_TIMESTAMP=${LK_BACKUP_TIMESTAMP:-$(date +"%Y-%m-%d-%H%M%S")}
    export LK_BACKUP_TIMESTAMP

    IFS=':'
    BASE_DIRS=(
        ${LK_BACKUP_BASE_DIRS:-/srv/www}
    )
    lk_remove_missing BASE_DIRS
    lk_resolve_files BASE_DIRS
    [ ${#BASE_DIRS[@]} -gt 0 ] ||
        lk_die "no base directories found"
    unset IFS
    lk_mapfile SOURCES <(comm -12 \
        <(getent passwd | cut -d: -f6 | sort -u) \
        <(find "${BASE_DIRS[@]}" \
            -mindepth 1 -maxdepth 1 -type d \
            -execdir test ! -e '{}/.lk-archived' \; -print | sort |
            sed -E '/^\/(proc|sys|dev|run|tmp)$/d'))
    [ ${#SOURCES[@]} -eq 0 ] ||
        lk_tty_list SOURCES "Backing up:" account accounts

    RSYNC_FILTER_ARGS=()
    EXIT_STATUS=0
    i=0
    for SOURCE in ${SOURCES[@]+"${SOURCES[@]}"}; do
        RSYNC_FILTER_ARGS+=(--filter "- $SOURCE")
        OWNER=$(lk_file_owner "$SOURCE")
        GROUP=$(id -gn "$OWNER")
        MESSAGE="Backup $((++i)) of ${#SOURCES[@]} "
        lk_log_bypass \
            lk_maybe_trace "$LK_BASE/bin/lk-backup-create-snapshot.sh" \
            --group "$GROUP" \
            --filter "$LK_BASE/lib/hosting/backup-filter-rsync" \
            --hook post_rsync:"$LK_BASE/lib/hosting/backup-hook-post_rsync.sh" \
            "${SOURCE##*/}" "$SOURCE" "$BACKUP_ROOT" \
            -- \
            --one-file-system \
            --chmod=go-w,g+r,Dg+x \
            --owner \
            --group \
            --chown="root:$GROUP" \
            "$@" &&
            lk_tty_success "${MESSAGE}completed successfully:" "$SOURCE" || {
            EXIT_STATUS=$?
            lk_tty_error \
                "${MESSAGE}failed to complete (exit status $EXIT_STATUS):" \
                "$SOURCE"
            continue
        }
        install -d -m 02770 -g "$GROUP" "$BACKUP_ROOT/archive/${SOURCE##*/}"
        lk_symlink "$BACKUP_ROOT/snapshot/${SOURCE##*/}" "$SOURCE/backup"
        lk_symlink "$BACKUP_ROOT/archive/${SOURCE##*/}" "$SOURCE/backup-archive"
    done

    lk_tty_print "Backing up system files"
    lk_log_bypass \
        lk_maybe_trace "$LK_BASE/bin/lk-backup-create-snapshot.sh" \
        --filter "$LK_BASE/lib/hosting/backup-filter-system_rsync" \
        --hook post_rsync:"$LK_BASE/lib/hosting/backup-hook-post_rsync.sh" \
        "root" "/" "$BACKUP_ROOT" \
        -- \
        --one-file-system \
        --owner \
        --group \
        ${RSYNC_FILTER_ARGS[@]+"${RSYNC_FILTER_ARGS[@]}"} &&
        lk_tty_success "System backup completed successfully" || {
        EXIT_STATUS=$?
        lk_tty_error \
            "System backup failed to complete (exit status $EXIT_STATUS)"
    }

    lk_maybe_trace "$LK_BASE/bin/lk-backup-prune-snapshots.sh" "$BACKUP_ROOT" ||
        EXIT_STATUS=$?

    exit "$EXIT_STATUS"
}

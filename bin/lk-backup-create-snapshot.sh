#!/bin/bash

# shellcheck disable=SC2015

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

include= . "$LK_BASE/lib/bash/common.sh"

function find_file() {
    local DIR
    for DIR in "$BACKUP_ROOT/conf" "$_DIR"; do
        [ -e "$DIR/$1" ] || continue
        realpath "$DIR/$1"
        return
    done
    false
}

function assert_stage_valid() {
    [ -n "$1" ] &&
        lk_in_array "$1" SNAPSHOT_STAGES ||
        lk_die "invalid stage: $1"
}

function mark_stage_complete() {
    is_stage_complete "$1" ||
        touch "$LK_SNAPSHOT_ROOT/.$1"
}

function is_stage_complete() {
    assert_stage_valid "$1"
    [ -e "$LK_SNAPSHOT_ROOT/.$1" ]
}

function get_stage() {
    local STAGE
    for STAGE in $(tac < <(lk_echo_array SNAPSHOT_STAGES)) not-started; do
        [ ! -e "$LK_SNAPSHOT_ROOT/.$STAGE" ] || break
    done
    echo "${STAGE//-/${1--}}"
}

SNAPSHOT_STAGES=(
    previous-copy-started
    previous-copy-finished
    hook-pre_rsync-started
    hook-pre_rsync-finished
    rsync-started
    rsync-finished
    hook-post_rsync-started
    hook-post_rsync-finished
    finished
)

LK_USAGE="\
Usage: ${0##*/} SOURCE_NAME SSH_HOST:SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME RSYNC_HOST::SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]

Use hard links to duplicate the previous SOURCE_NAME snapshot at BACKUP_ROOT,
then rsync SOURCE_PATH to the replica to create a new snapshot of SOURCE_NAME.

This approach uses less storage than rsync --link-dest, which breaks hard links
when permissions change."

[ $# -ge 3 ] || lk_usage

SOURCE_NAME=$1
SOURCE=$2
BACKUP_ROOT=$3
shift 3

case "$SOURCE" in
*::*)
    RSYNC_HOST=${SOURCE%%::*}
    SOURCE_PATH=${SOURCE#*::}
    SOURCE_TYPE="rsync"
    ;;
*:*)
    SSH_HOST=${SOURCE%%:*}
    SOURCE_PATH=${SOURCE#*:}
    SOURCE_TYPE="rsync over SSH"
    ;;
*)
    SOURCE_PATH=$SOURCE
    SOURCE_TYPE="filesystem"
    ;;
esac

[ -d "$BACKUP_ROOT" ] || lk_die "directory not found: $BACKUP_ROOT"
[ -w "$BACKUP_ROOT" ] || lk_die "cannot write to directory: $BACKUP_ROOT"

SOURCE_NAME=${SOURCE_NAME//\//_}
BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
LOCK_FILE=/tmp/${0##*/}-${BACKUP_ROOT//\//_}-$SOURCE_NAME.lock
exec 9>"$LOCK_FILE" &&
    flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"

LK_SNAPSHOT_TIMESTAMP=${LK_BACKUP_TIMESTAMP:-$(date +"%Y-%m-%d-%H%M%S")}
LK_SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME/$LK_SNAPSHOT_TIMESTAMP
LK_SNAPSHOT_FS_ROOT=$LK_SNAPSHOT_ROOT/fs
LK_SNAPSHOT_DB_ROOT=$LK_SNAPSHOT_ROOT/db
export LK_SNAPSHOT_TIMESTAMP \
    LK_SNAPSHOT_ROOT LK_SNAPSHOT_FS_ROOT LK_SNAPSHOT_DB_ROOT

SOURCE_LATEST=$BACKUP_ROOT/latest/$SOURCE_NAME
SNAPSHOT_LOG_FILE=$LK_SNAPSHOT_ROOT/log/snapshot.log
RSYNC_OUT_FILE=$LK_SNAPSHOT_ROOT/log/rsync.log
RSYNC_ERR_FILE=$LK_SNAPSHOT_ROOT/log/rsync.err.log

! is_stage_complete finished ||
    lk_die "already finalised: $LK_SNAPSHOT_ROOT"

lk_log_output

install -d -m 0711 \
    "$BACKUP_ROOT/"{,latest,log,snapshot/{,"$SOURCE_NAME/"{,"$LK_SNAPSHOT_TIMESTAMP/"{,db,log}}}}
for f in SNAPSHOT_LOG_FILE RSYNC_OUT_FILE RSYNC_ERR_FILE; do
    [ -e "${!f}" ] ||
        install -m 0600 /dev/null "${!f}"
done

{
    lk_console_message "Backing up $SOURCE_NAME to $BACKUP_ROOT"
    lk_console_detail "Source:" "$SOURCE"
    lk_console_detail "Transport:" "$SOURCE_TYPE"
    lk_console_detail "Snapshot:" "$LK_SNAPSHOT_TIMESTAMP"
    lk_console_detail "Status:" "$(get_stage " ")"

    if [ -d "$SOURCE_LATEST/fs" ] && ! is_stage_complete previous-copy-finished; then
        LATEST=$(realpath "$SOURCE_LATEST/fs")
        [ "$LATEST" != "$(realpath "$LK_SNAPSHOT_FS_ROOT")" ] ||
            lk_die "latest and pending snapshots cannot be the same"
        lk_console_message "Duplicating previous snapshot using hard links"
        ! is_stage_complete previous-copy-started || {
            lk_console_detail "Deleting incomplete replica from previous run"
            rm -Rf "$LK_SNAPSHOT_FS_ROOT"
        }
        [ ! -e "$LK_SNAPSHOT_FS_ROOT" ] ||
            lk_die "directory already exists: $LK_SNAPSHOT_FS_ROOT"
        lk_console_detail "Snapshot:" "$LATEST"
        lk_console_detail "Replica:" "$LK_SNAPSHOT_FS_ROOT"
        mark_stage_complete previous-copy-started
        cp -al "$LATEST" "$LK_SNAPSHOT_FS_ROOT"
        mark_stage_complete previous-copy-finished
        lk_console_log "Copy complete"
    else
        mark_stage_complete previous-copy-finished
    fi

    lk_console_item "Creating snapshot at" "$LK_SNAPSHOT_ROOT"
    lk_console_detail "Log files:" "$(lk_echo_args \
        "$SNAPSHOT_LOG_FILE" "$RSYNC_OUT_FILE" "$RSYNC_ERR_FILE")"
    RSYNC_ARGS=(-vrlpt --delete)
    ! RSYNC_FILTER=$(find_file "$SOURCE_NAME-filter") || {
        lk_console_detail "Rsync filter:" "$RSYNC_FILTER"
        RSYNC_ARGS=("${RSYNC_ARGS[@]}" --delete-excluded --filter ". $RSYNC_FILTER")
    }

    # shellcheck disable=SC1090
    if SOURCE_SCRIPT=$(find_file "$SOURCE_NAME-hook-pre_rsync"); then
        export LK_SOURCE_SCRIPT_ALREADY_STARTED=0 \
            LK_SOURCE_SCRIPT_ALREADY_FINISHED=0
        ! is_stage_complete hook-pre_rsync-started ||
            LK_SOURCE_SCRIPT_ALREADY_STARTED=1
        ! is_stage_complete hook-pre_rsync-finished ||
            LK_SOURCE_SCRIPT_ALREADY_FINISHED=1
        mark_stage_complete hook-pre_rsync-started
        lk_console_item "Running hook script:" "$SOURCE_SCRIPT"
        . "$SOURCE_SCRIPT"
        mark_stage_complete hook-pre_rsync-finished
        lk_console_log "Hook script finished"
    fi

    RSYNC_ARGS=("${RSYNC_ARGS[@]}" "$@" "${SOURCE%/}/" "$LK_SNAPSHOT_FS_ROOT/")

    ! lk_in_array --inplace RSYNC_ARGS &&
        ! lk_in_array --write-devices RSYNC_ARGS ||
        lk_die "invalid rsync arguments (--inplace not supported)"

    ! lk_in_array --dry-run RSYNC_ARGS &&
        ! lk_in_array -n RSYNC_ARGS || DRY_RUN=1

    [ "${DRY_RUN:-0}" -ne 0 ] || mark_stage_complete rsync-started
    lk_console_item "Running rsync:" \
        $'>>>\n'"  rsync$(printf ' \\ \n    %q' "${RSYNC_ARGS[@]}")"$'\n<<<'
    EXIT_STATUS=0
    rsync "${RSYNC_ARGS[@]}" \
        > >(tee >(lk_log >>"$RSYNC_OUT_FILE") >&6) \
        2> >(tee >(lk_log >>"$RSYNC_ERR_FILE") >&7) || EXIT_STATUS=$?
    case "$EXIT_STATUS" in
    0)
        RSYNC_RESULT="completed successfully"
        ;;
    23 | 24)
        RSYNC_RESULT="completed with partial transfer (exit status $EXIT_STATUS)"
        ;;
    *)
        lk_die "rsync failed to execute (exit status $EXIT_STATUS)"
        ;;
    esac
    [ "${DRY_RUN:-0}" -ne 0 ] || mark_stage_complete rsync-finished
    lk_console_log "rsync $RSYNC_RESULT"

    # shellcheck disable=SC1090
    if SOURCE_SCRIPT=$(find_file "$SOURCE_NAME-hook-post_rsync"); then
        export LK_SOURCE_SCRIPT_ALREADY_STARTED=0 \
            LK_SOURCE_SCRIPT_ALREADY_FINISHED=0
        ! is_stage_complete hook-post_rsync-started ||
            LK_SOURCE_SCRIPT_ALREADY_STARTED=1
        ! is_stage_complete hook-post_rsync-finished ||
            LK_SOURCE_SCRIPT_ALREADY_FINISHED=1
        mark_stage_complete hook-post_rsync-started
        lk_console_item "Running hook script:" "$SOURCE_SCRIPT"
        . "$SOURCE_SCRIPT"
        mark_stage_complete hook-post_rsync-finished
        lk_console_log "Hook script finished"
    fi

    [ "${DRY_RUN:-0}" -ne 0 ] || {
        lk_console_message "Updating latest snapshot symlink for $SOURCE_NAME"
        ln -sfnv "$LK_SNAPSHOT_ROOT" "$SOURCE_LATEST"
        mark_stage_complete finished
    }

    exec 9>&-
    rm -f "$LOCK_FILE"

    exit
}

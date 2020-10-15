#!/bin/bash

# shellcheck disable=SC2015

set -eu

lk_die() { s=$? && echo "${LK_DIE_PREFIX-${0##*/}: }$1" >&2 &&
    (return $s) && false || exit; }
_DIR=${0%/*}
[ "$_DIR" != "$0" ] || _DIR=.
_DIR=$(cd "$_DIR" && pwd -P) && [ ! -L "$0" ] ||
    lk_die "unable to resolve path to script"

function lk_realpath() {
    local FILE=$1 i=0 COMPONENT LN RESOLVED=
    [ -e "$FILE" ] || return
    [ "${FILE:0:1}" = / ] || FILE=${PWD%/}/$FILE
    while [ -n "$FILE" ]; do
        ((i++)) || {
            # 1. Replace "/./" with "/"
            # 2. Replace subsequent "/"s with one "/"
            # 3. Remove trailing "/"
            FILE=$(sed -e 's/\/\.\//\//g' -e 's/\/\+/\//g' -e 's/\/$//' \
                <<<"$FILE") || return
            FILE=${FILE:1}
        }
        COMPONENT=${FILE%%/*}
        [ "$COMPONENT" != "$FILE" ] ||
            FILE=
        FILE=${FILE#*/}
        case "$COMPONENT" in
        '' | .)
            continue
            ;;
        ..)
            RESOLVED=${RESOLVED%/*}
            continue
            ;;
        esac
        RESOLVED=$RESOLVED/$COMPONENT
        [ ! -L "$RESOLVED" ] || {
            LN=$(readlink "$RESOLVED") || return
            [ "${LN:0:1}" = / ] || LN=${RESOLVED%/*}/$LN
            FILE=$LN${FILE:+/$FILE}
            RESOLVED=
            i=0
        }
    done
    echo "$RESOLVED"
}

function lk_in_array() {
    local _LK_ARRAY _LK_VALUE
    eval "_LK_ARRAY=(\${$2[@]+\"\${$2[@]}\"})"
    for _LK_VALUE in ${_LK_ARRAY[@]+"${_LK_ARRAY[@]}"}; do
        [ "$_LK_VALUE" = "$1" ] || continue
        return
    done
    false
}

function lk_date_log() {
    date +"%Y-%m-%d %H:%M:%S %z"
}

function lk_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(lk_date_log)" "$LINE"
    done
}

function lk_console_message() {
    local SPACES=$'\n'"${LK_CONSOLE_SPACES-  }"
    echo "\
$LK_BOLD${LK_CONSOLE_COLOUR-$LK_CYAN}${LK_CONSOLE_PREFIX-==> }\
$LK_RESET${LK_CONSOLE_MESSAGE_COLOUR-$LK_BOLD}\
${1//$'\n'/$SPACES}$LK_RESET"
}

function lk_console_item() {
    lk_console_message "\
$1$LK_RESET${LK_CONSOLE_COLOUR2-${LK_CONSOLE_COLOUR-$LK_CYAN}}$(
        [ "${2//$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"${2#$'\n'}"
    )"
}

function lk_console_detail() {
    local LK_CONSOLE_PREFIX="   -> " LK_CONSOLE_SPACES="    " \
        LK_CONSOLE_COLOUR=$LK_YELLOW LK_CONSOLE_MESSAGE_COLOUR=
    [ $# -le 1 ] &&
        lk_console_message "$1" ||
        lk_console_item "$1" "$2"
}

function lk_console_log() {
    local LK_CONSOLE_PREFIX=" :: " LK_CONSOLE_SPACES="    " \
        LK_CONSOLE_COLOUR2=${LK_CONSOLE_COLOUR2-$LK_BOLD}
    [ $# -le 1 ] &&
        lk_console_message "${LK_CONSOLE_COLOUR-$LK_CYAN}$1" ||
        lk_console_item "${LK_CONSOLE_COLOUR-$LK_CYAN}$1" "$2"
}

function lk_console_error() {
    local EXIT_STATUS=$?
    LK_CONSOLE_COLOUR=$LK_RED lk_console_log "$@"
    return "$EXIT_STATUS"
}

LK_BOLD=$(tput bold 2>/dev/null) || LK_BOLD=
LK_RED=$(tput setaf 1 2>/dev/null) || LK_RED=
LK_CYAN=$(tput setaf 6 2>/dev/null) || LK_CYAN=
LK_YELLOW=$(tput setaf 3 2>/dev/null) || LK_YELLOW=
LK_RESET=$(tput sgr0 2>/dev/null) || LK_RESET=

##

function find_custom() {
    local FILE ALL=0 COUNT=0
    [ "$1" != --all ] || {
        ALL=1
        shift
    }
    for FILE in {"$_DIR","$BACKUP_ROOT"/conf.d}/{"$1","$SOURCE_NAME/${1#$SOURCE_NAME-}"}; do
        [ -e "$FILE" ] || continue
        lk_realpath "$FILE" || lk_die
        ((++COUNT))
        [ "$ALL" -eq 1 ] || break
    done
    ((COUNT))
}

function run_custom_hook() {
    local HOOK=$1 SCRIPTS SOURCE_SCRIPT LINES LINE SH
    export LK_SOURCE_SCRIPT_ALREADY_STARTED=0 \
        LK_SOURCE_SCRIPT_ALREADY_FINISHED=0
    ! is_stage_complete "hook-$HOOK-started" ||
        LK_SOURCE_SCRIPT_ALREADY_STARTED=1
    ! is_stage_complete "hook-$HOOK-finished" ||
        LK_SOURCE_SCRIPT_ALREADY_FINISHED=1
    if SCRIPTS=($(find_custom --all "$SOURCE_NAME-hook-$HOOK")); then
        mark_stage_complete "hook-$HOOK-started"
        for SOURCE_SCRIPT in "${SCRIPTS[@]}"; do
            lk_console_item "Running hook script:" "$SOURCE_SCRIPT"
            (
                EXIT_STATUS=0
                . "$SOURCE_SCRIPT" || EXIT_STATUS=$?
                echo "# ." >&4
                exit "$EXIT_STATUS"
            ) &
            LINES=()
            while IFS= read -ru 4 LINE && [ "$LINE" != "# ." ]; do
                LINES=(${LINES[@]+"${LINES[@]}"} "$LINE")
            done
            wait "$!" ||
                lk_die "hook script failed (exit status $?)"
            [ ${#LINES[@]} -eq 0 ] || {
                SH=$(printf '%s\n' "${LINES[@]}")
                eval "$SH" ||
                    LK_CONSOLE_COLOUR2='' lk_console_error "\
Shell commands emitted by hook script failed (exit status $?):" $'\n'"$SH" ||
                    lk_die ""
            }
            lk_console_log "Hook script finished"
        done
        mark_stage_complete "hook-$HOOK-finished"
    fi
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
    for STAGE in $(tac < <(printf '%s\n' \
        "${SNAPSHOT_STAGES[@]}")) starting; do
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

[ $# -ge 3 ] || LK_DIE_PREFIX='' lk_die "\
Usage: ${0##*/} SOURCE_NAME SSH_HOST:SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME RSYNC_HOST::SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]

Use hard links to duplicate the previous SOURCE_NAME snapshot at BACKUP_ROOT,
then rsync SOURCE_PATH to the replica to create a new snapshot of SOURCE_NAME.

This approach uses less storage than rsync --link-dest, which breaks hard links
when permissions change."

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
BACKUP_ROOT=$(lk_realpath "$BACKUP_ROOT")
! type -P flock >/dev/null || {
    LOCK_FILE=/tmp/${0##*/}-${BACKUP_ROOT//\//_}-$SOURCE_NAME.lock
    exec 9>"$LOCK_FILE" &&
        flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"
}
TMPDIR=${TMPDIR:-/tmp}
FIFO_FILE=$(mktemp -d -- "${TMPDIR%/}/${0##*/}.XXXXXXXXXX")/fifo
mkfifo "$FIFO_FILE"
exec 4<>"$FIFO_FILE"

LK_SNAPSHOT_TIMESTAMP=${LK_BACKUP_TIMESTAMP:-$(date +"%Y-%m-%d-%H%M%S")}
LK_SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME/$LK_SNAPSHOT_TIMESTAMP
LK_SNAPSHOT_FS_ROOT=$LK_SNAPSHOT_ROOT/fs
LK_SNAPSHOT_DB_ROOT=$LK_SNAPSHOT_ROOT/db
export LK_SNAPSHOT_TIMESTAMP \
    LK_SNAPSHOT_ROOT LK_SNAPSHOT_FS_ROOT LK_SNAPSHOT_DB_ROOT

SOURCE_LATEST=$BACKUP_ROOT/latest/$SOURCE_NAME
LOG_FILE=$BACKUP_ROOT/log/snapshot.log
SNAPSHOT_LOG_FILE=$LK_SNAPSHOT_ROOT/log/snapshot.log
RSYNC_OUT_FILE=$LK_SNAPSHOT_ROOT/log/rsync.log
RSYNC_ERR_FILE=$LK_SNAPSHOT_ROOT/log/rsync.err.log

! is_stage_complete finished ||
    lk_die "already finalised: $LK_SNAPSHOT_ROOT"

install -d -m 0711 \
    "$BACKUP_ROOT/"{,latest,log,snapshot/{,"$SOURCE_NAME/"{,"$LK_SNAPSHOT_TIMESTAMP/"{,db,log}}}}
for f in LOG_FILE SNAPSHOT_LOG_FILE RSYNC_OUT_FILE RSYNC_ERR_FILE; do
    [ -e "${!f}" ] ||
        install -m 0600 /dev/null "${!f}"
done

lk_log >>"$LOG_FILE" <<<"====> $(lk_realpath "$0") invoked on $(hostname -f)"
exec 6>&1 7>&2
exec > >(tee >(lk_log | tee -a "$SNAPSHOT_LOG_FILE" >>"$LOG_FILE")) 2>&1

{
    lk_console_message "Backing up $SOURCE_NAME to $BACKUP_ROOT"
    lk_console_detail "Source:" "$SOURCE"
    lk_console_detail "Transport:" "$SOURCE_TYPE"
    lk_console_detail "Snapshot:" "$LK_SNAPSHOT_TIMESTAMP"
    lk_console_detail "Status:" "$(get_stage " ")"

    if [ -d "$SOURCE_LATEST/fs" ] && ! is_stage_complete previous-copy-finished; then
        LATEST=$(lk_realpath "$SOURCE_LATEST/fs")
        [ "$LATEST" != "$(lk_realpath "$LK_SNAPSHOT_FS_ROOT")" ] ||
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
    lk_console_detail "Log files:" "$(printf '%s\n' \
        "$SNAPSHOT_LOG_FILE" "$RSYNC_OUT_FILE" "$RSYNC_ERR_FILE")"
    RSYNC_ARGS=(-vrlpt --delete)
    ! RSYNC_FILTER=$(find_custom "$SOURCE_NAME-filter-rsync") || {
        lk_console_detail "Rsync filter:" "$RSYNC_FILTER"
        RSYNC_ARGS=("${RSYNC_ARGS[@]}" --delete-excluded --filter ". $RSYNC_FILTER")
    }

    run_custom_hook pre_rsync

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

    run_custom_hook post_rsync

    [ "${DRY_RUN:-0}" -ne 0 ] || {
        lk_console_message "Updating latest snapshot symlink for $SOURCE_NAME"
        ln -sfnv "$LK_SNAPSHOT_ROOT" "$SOURCE_LATEST"
        mark_stage_complete finished
    }

    exec 4>&-
    rm -Rf "${FIFO_FILE%/*}"

    [ -z "${LOCK_FILE:-}" ] || {
        exec 9>&-
        rm -f "$LOCK_FILE"
    }

    exit
}

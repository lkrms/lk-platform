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
    eval "_LK_ARRAY=(\${$2+\"\${$2[@]}\"})"
    for _LK_VALUE in ${_LK_ARRAY+"${_LK_ARRAY[@]}"}; do
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
            echo $'\n'"$2"
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
        LK_CONSOLE_COLOUR2=$LK_BOLD
    [ $# -le 1 ] &&
        lk_console_message "$LK_CYAN$1" ||
        lk_console_item "$LK_CYAN$1" "$2"
}

LK_BOLD=$(tput bold 2>/dev/null) || LK_BOLD=
LK_CYAN=$(tput setaf 6 2>/dev/null) || LK_CYAN=
LK_YELLOW=$(tput setaf 3 2>/dev/null) || LK_YELLOW=
LK_RESET=$(tput sgr0 2>/dev/null) || LK_RESET=

##

function find_file() {
    local DIR
    for DIR in "$BACKUP_ROOT/conf" "$_DIR"; do
        [ -e "$DIR/$1" ] || continue
        lk_realpath "$DIR/$1"
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
        touch "$SNAPSHOT_ROOT/.$1"
}

function is_stage_complete() {
    assert_stage_valid "$1"
    [ -e "$SNAPSHOT_ROOT/.$1" ]
}

function get_stage() {
    local STAGE SEPARATOR=${1:--}
    for STAGE in $(tac <(printf '%s\n' "${SNAPSHOT_STAGES[@]}")) not-started; do
        [ ! -e "$SNAPSHOT_ROOT/.$STAGE" ] || break
    done
    echo "${STAGE//-/$SEPARATOR}"
}

SNAPSHOT_STAGES=(
    previous-copy-started
    previous-copy-finished
    hook-pre-rsync-started
    hook-pre-rsync-finished
    rsync-started
    rsync-finished
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
SOURCE=${2%/}
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

BACKUP_ROOT=$(lk_realpath "$BACKUP_ROOT")
LOCK_FILE=/tmp/${0##*/}-${BACKUP_ROOT//\//_}.lock
exec 9>"$LOCK_FILE"
flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"

LOG_FILE=$BACKUP_ROOT/log/snapshot.log
SOURCE_NAME=${SOURCE_NAME//\//_}
SOURCE_LATEST=$BACKUP_ROOT/latest/$SOURCE_NAME
SNAPSHOT_TIMESTAMP=${LK_BACKUP_TIMESTAMP:-$(date +"%Y-%m-%d-%H%M%S")}
SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME/$SNAPSHOT_TIMESTAMP
SNAPSHOT_FS_ROOT=$SNAPSHOT_ROOT/fs
SNAPSHOT_DB_ROOT=$SNAPSHOT_ROOT/db
SNAPSHOT_LOG_FILE=$SNAPSHOT_ROOT/log/snapshot.log
RSYNC_OUT_FILE=$SNAPSHOT_ROOT/log/rsync.log
RSYNC_ERR_FILE=$SNAPSHOT_ROOT/log/rsync.err.log

install -d -m 0700 \
    "$BACKUP_ROOT/"{,latest,log,snapshot/{,"$SOURCE_NAME/"{,"$SNAPSHOT_TIMESTAMP/"{,db,log}}}}
for f in LOG_FILE SNAPSHOT_LOG_FILE RSYNC_OUT_FILE RSYNC_ERR_FILE; do
    [ -e "${!f}" ] ||
        install -m 0600 /dev/null "${!f}"
done

lk_log >>"$LOG_FILE" <<<"====> $(lk_realpath "$0") invoked on $(hostname -f)"
exec 6>&1 7>&2
exec > >(tee >(lk_log | tee -a "$SNAPSHOT_LOG_FILE" >>"$LOG_FILE")) 2>&1

! is_stage_complete finished ||
    lk_die "already finalised: $SNAPSHOT_ROOT"

lk_console_message "Backing up $SOURCE_NAME to $BACKUP_ROOT"
lk_console_detail "Source:" "$SOURCE"
lk_console_detail "Transport:" "$SOURCE_TYPE"
lk_console_detail "Snapshot:" "$SNAPSHOT_TIMESTAMP"
lk_console_detail "Status:" "$(get_stage " ")"

if [ -d "$SOURCE_LATEST/fs" ] && ! is_stage_complete previous-copy-finished; then
    LATEST=$(lk_realpath "$SOURCE_LATEST/fs")
    [ "$LATEST" != "$(lk_realpath "$SNAPSHOT_FS_ROOT")" ] || exit
    lk_console_message "Duplicating previous snapshot using hard links"
    ! is_stage_complete previous-copy-started || {
        lk_console_detail "Deleting incomplete replica from previous run"
        rm -Rf "$SNAPSHOT_FS_ROOT"
    }
    [ ! -e "$SNAPSHOT_FS_ROOT" ] ||
        lk_die "directory already exists: $SNAPSHOT_FS_ROOT"
    lk_console_detail "Snapshot:" "$LATEST"
    lk_console_detail "Replica:" "$SNAPSHOT_FS_ROOT"
    mark_stage_complete previous-copy-started
    cp -al "$LATEST" "$SNAPSHOT_FS_ROOT"
    mark_stage_complete previous-copy-finished
    lk_console_log "Copy complete"
else
    mark_stage_complete previous-copy-finished
fi

lk_console_item "Creating snapshot at" "$SNAPSHOT_ROOT"
lk_console_detail "Log files:" "$(printf '%s\n' \
    "$SNAPSHOT_LOG_FILE" "$RSYNC_OUT_FILE" "$RSYNC_ERR_FILE")"
RSYNC_ARGS=(-vrlpt --delete)
! RSYNC_FILTER=$(find_file "$SOURCE_NAME-filter") || {
    lk_console_detail "Rsync filter:" "$RSYNC_FILTER"
    RSYNC_ARGS=("${RSYNC_ARGS[@]}" --delete-excluded --filter ". $RSYNC_FILTER")
}

# shellcheck disable=SC1090
if SOURCE_SCRIPT=$(find_file "$SOURCE_NAME-hook-pre_rsync") &&
    ! is_stage_complete hook-pre-rsync-finished; then
    SOURCE_SCRIPT_FIRST_RUN=1
    ! is_stage_complete hook-pre-rsync-started || SOURCE_SCRIPT_FIRST_RUN=0
    mark_stage_complete hook-pre-rsync-started
    lk_console_item "Running hook script:" "$SOURCE_SCRIPT"
    . "$SOURCE_SCRIPT"
    mark_stage_complete hook-pre-rsync-finished
    lk_console_log "Hook script finished"
fi

RSYNC_ARGS=("${RSYNC_ARGS[@]}" "$@" "$SOURCE/" "$SNAPSHOT_FS_ROOT/")

! lk_in_array --inplace RSYNC_ARGS &&
    ! lk_in_array --write-devices RSYNC_ARGS ||
    lk_die "invalid rsync arguments (--inplace not supported)"

mark_stage_complete rsync-started
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
mark_stage_complete rsync-finished
lk_console_log "rsync $RSYNC_RESULT"

lk_console_message "Updating latest snapshot symlink for $SOURCE_NAME"
ln -sfnv "$SNAPSHOT_ROOT" "$SOURCE_LATEST"
mark_stage_complete finished

exec 9>&-
rm -f "$LOCK_FILE"

#!/bin/bash

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
lk_include backup mail mysql
! lk_is_linux ||
    lk_include linux

function exit_trap() {
    local EXIT_STATUS=$? MESSAGE TAR SUBJECT
    exec 8>&- &&
        rm -Rf "${FIFO_FILE%/*}" || true
    lk_log_close -r
    [ -z "$LK_BACKUP_MAIL" ] ||
        { [ "$EXIT_STATUS" -eq 0 ] &&
            [ "$RSYNC_EXIT_VALUE" -eq 0 ] &&
            [ "$LK_BACKUP_MAIL_ERROR_ONLY" = Y ]; } || {
        lk_mail_new
        MESSAGE=
        { [ ! -s "$RSYNC_OUT_FILE" ] && [ ! -s "$RSYNC_ERR_FILE" ]; } ||
            ! TAR=$(lk_mktemp_file) ||
            ! lk_delete_on_exit "$TAR" ||
            ! tar -C "${RSYNC_OUT_FILE%/*}" -czf "$TAR" \
                "${RSYNC_OUT_FILE##*/}" \
                "${RSYNC_ERR_FILE##*/}" || {
            lk_mail_attach \
                "$TAR" \
                "$HN-$SOURCE_NAME-$LK_SNAPSHOT_TIMESTAMP-rsync.log.tgz" \
                application/gzip &&
                MESSAGE="the attached log files and " || true
        }
        [ "$EXIT_STATUS" -eq 0 ] && {
            [ "$RSYNC_EXIT_VALUE" -eq 0 ] && {
                SUBJECT="Success"
                MESSAGE="\
The following backup ${RSYNC_RESULT:-completed without error}."
            } || {
                SUBJECT="Please review"
                MESSAGE="\
The following backup ${RSYNC_RESULT:-completed with errors}. Please review \
${MESSAGE}the output below${MESSAGE:+,} and take action if required."
            }
        } || {
            SUBJECT="ACTION REQUIRED"
            MESSAGE="\
The following backup ${RSYNC_RESULT:-failed to complete}. Please review \
${MESSAGE}the output below${MESSAGE:+,} and action accordingly."
        }
        SUBJECT="$SUBJECT: backup of $SOURCE_NAME to $HN:$BACKUP_ROOT"
        MESSAGE="
Hello

$MESSAGE

Source: $SOURCE
Destination: $BACKUP_ROOT on $FQDN
Transport: $SOURCE_TYPE
Snapshot: $LK_SNAPSHOT_TIMESTAMP
Status: $(get_stage)

Running as: $USER
Command line:
$(printf '%q' "$0" && { [ ${#LK_ARGV[@]} -eq 0 ] || printf ' \\\n    %q' "${LK_ARGV[@]}"; })

Output:

$(lk_strip_non_printing <"$SNAPSHOT_LOG_FILE")" &&
            lk_mail_set_text "$MESSAGE" &&
            lk_mail_send "$SUBJECT" "$LK_BACKUP_MAIL" "$LK_BACKUP_MAIL_FROM" || true
    }
}

function find_custom() {
    local ARR="${1//-/_}[@]" FILE COUNT=0
    for FILE in {"$LK_BASE/etc/backup","$BACKUP_ROOT/conf.d"}/{"$1","$SOURCE_NAME-$1","$SOURCE_NAME/$1"} \
        ${!ARR+"${!ARR}"}; do
        [ -e "$FILE" ] || continue
        realpath "$FILE" || lk_die
        ((++COUNT))
    done
    ((COUNT))
}

function run_custom_hook() {
    local HOOK=$1 SCRIPTS SOURCE_SCRIPT i=0 LINES LINE SH \
        LK_SOURCE_SCRIPT_ALREADY_STARTED=0 \
        LK_SOURCE_SCRIPT_ALREADY_FINISHED=0
    ! is_stage_complete "hook-$HOOK-started" ||
        LK_SOURCE_SCRIPT_ALREADY_STARTED=1
    ! is_stage_complete "hook-$HOOK-finished" ||
        LK_SOURCE_SCRIPT_ALREADY_FINISHED=1
    if SCRIPTS=($(find_custom "hook-$HOOK")); then
        mark_stage_complete "hook-$HOOK-started"
        for SOURCE_SCRIPT in "${SCRIPTS[@]}"; do
            lk_console_item "Running hook script:" "$SOURCE_SCRIPT"
            (
                EXIT_STATUS=0
                . "$SOURCE_SCRIPT" || EXIT_STATUS=$?
                echo "# ." >&8
                exit "$EXIT_STATUS"
            ) &
            LINES=()
            while IFS= read -ru 8 LINE && [ "$LINE" != "# ." ]; do
                LINES[$((i++))]=$LINE
            done
            wait "$!" ||
                lk_die "hook script failed (exit status $?)"
            [ ${#LINES[@]} -eq 0 ] || {
                SH=$(lk_echo_array LINES)
                eval "$SH" ||
                    LK_TTY_COLOUR2='' LK_TTY_NO_FOLD=1 \
                        lk_console_error -r "\
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
        touch "$LK_SNAPSHOT/.$1"
}

function is_stage_complete() {
    assert_stage_valid "$1"
    [ -e "$LK_SNAPSHOT/.$1" ]
}

function get_stage() {
    local STAGE
    for STAGE in $(tac < <(lk_echo_array SNAPSHOT_STAGES)) starting; do
        [ ! -e "$LK_SNAPSHOT/.$STAGE" ] || break
    done
    echo "${STAGE//-/ }"
}

# run_rsync [SOURCE DEST]
function run_rsync() {
    local SRC=${1:-} DEST=${2:-}
    [ $# -eq 2 ] || {
        SRC=${SOURCE%/}/
        DEST=$LK_SNAPSHOT_FS/
    }
    lk_run rsync "${RSYNC_ARGS[@]}" "$SRC" "$DEST" \
        > >(lk_log_bypass_stdout tee -a "$RSYNC_OUT_FILE") \
        2> >(lk_log_bypass_stdout tee -a "$RSYNC_ERR_FILE")
}

SNAPSHOT_STAGES=(
    previous-copy-started
    previous-copy-finished
    hook-pre_rsync-started
    hook-pre_rsync-finished
    rsync-started
    rsync-partial_transfer-finished
    rsync-finished
    hook-post_rsync-started
    hook-post_rsync-finished
    finished
)

SNAPSHOT_GROUP=
filter_rsync=()
hook_pre_rsync=()
hook_post_rsync=()

LK_USAGE="\
Usage: ${0##*/} [OPTIONS] SOURCE_NAME SOURCE BACKUP_ROOT [-- RSYNC_ARG...]

Use hard links to duplicate the previous SOURCE_NAME snapshot at BACKUP_ROOT,
then rsync from SOURCE to the replica to create a new snapshot of SOURCE_NAME.

This approach doesn't preserve historical file modes but uses less storage than
rsync --link-dest, which breaks hard links when permissions change.

Custom hook scripts are processed in the following order. Rsync filters are
added in the reverse order.
  1. $LK_BASE/etc/backup/<filter-rsync|hook-HOOK>
  2. $LK_BASE/etc/backup/<SOURCE_NAME>/<filter-rsync|hook-HOOK>
  3. <BACKUP_ROOT>/conf.d/<filter-rsync|hook-HOOK>
  4. <BACKUP_ROOT>/conf.d/<SOURCE_NAME>/<filter-rsync|hook-HOOK>
  5. command-line

Hook scripts are sourced in a Bash subshell. If they return zero, any output on
file descriptor 8 is eval'd in the global scope of ${0##*/}.

Options:
  -g, --group GROUP             create snapshot directories with group GROUP
  -f, --filter RSYNC_FILTER     add filtering rules from file RSYNC_FILTER
  -h, --hook HOOK:BASH_SCRIPT   register BASH_SCRIPT with HOOK

Sources:
  SSH_HOST:SOURCE_PATH
  RSYNC_HOST::SOURCE_PATH
  SOURCE_PATH

Hooks:
  pre_rsync
  post_rsync"

lk_getopt "g:f:h:" \
    "group:,filter:,hook:"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -g | --group)
        # TODO: add macOS-friendly test
        getent group "$1" &>/dev/null ||
            lk_die "group not found: $1"
        SNAPSHOT_GROUP=$1
        shift
        ;;
    -f | --filter)
        [ -f "$1" ] || lk_die "file not found: $1"
        filter_rsync+=("$1")
        shift
        ;;
    -h | --hook)
        [[ $1 =~ ^(pre_rsync|post_rsync):(.+)$ ]] ||
            lk_die "invalid argument: $1"
        HOOK=${BASH_REMATCH[1]}
        HOOK_SCRIPT=${BASH_REMATCH[2]}
        [ -f "$HOOK_SCRIPT" ] || lk_die "file not found: $HOOK_SCRIPT"
        eval "hook_$HOOK+=(\"\$HOOK_SCRIPT\")"
        shift
        ;;
    --)
        break
        ;;
    esac
done

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
LOCK_NAME=${0##*/}-${BACKUP_ROOT//\//_}-$SOURCE_NAME
lk_lock LOCK_FILE LOCK_FD "$LOCK_NAME"
FIFO_FILE=$(lk_mktemp_dir)/fifo
mkfifo "$FIFO_FILE"
exec 8<>"$FIFO_FILE"

export TZ=UTC
HN=$(lk_hostname) || HN=localhost
FQDN=$(lk_fqdn) || FQDN=$HN.localdomain
SENDER_NAME="${LK_PATH_PREFIX}backup on $HN"
LK_SNAPSHOT_TIMESTAMP=${LK_BACKUP_TIMESTAMP:-$(date +"%Y-%m-%d-%H%M%S")}
LK_SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME
LK_SNAPSHOT=$LK_SNAPSHOT_ROOT/$LK_SNAPSHOT_TIMESTAMP
LK_SNAPSHOT_FS=$LK_SNAPSHOT/fs
LK_SNAPSHOT_DB=$LK_SNAPSHOT/db
LK_BACKUP_MAIL=${LK_BACKUP_MAIL-root}
LK_BACKUP_MAIL_FROM=${LK_BACKUP_MAIL_FROM-"$SENDER_NAME <$USER@$FQDN>"}
LK_BACKUP_MAIL_ERROR_ONLY=${LK_BACKUP_MAIL_ERROR_ONLY-Y}

SOURCE_LATEST=$BACKUP_ROOT/latest/$SOURCE_NAME
SNAPSHOT_LOG_FILE=$LK_SNAPSHOT/log/snapshot.log
RSYNC_OUT_FILE=$LK_SNAPSHOT/log/rsync.log
RSYNC_ERR_FILE=$LK_SNAPSHOT/log/rsync.err.log

[ -d "$SOURCE_LATEST" ] ||
    [ ! -d "$LK_SNAPSHOT_ROOT" ] ||
    SOURCE_LATEST=$LK_SNAPSHOT_ROOT/$(lk_backup_snapshot_latest "$LK_SNAPSHOT_ROOT") ||
    SOURCE_LATEST=

! is_stage_complete finished ||
    lk_die "already finalised: $LK_SNAPSHOT"

umask 022
SOURCE_MODE=00700
SNAPSHOT_MODE=00700
LOG_MODE=00600
[ -z "$SNAPSHOT_GROUP" ] || {
    SOURCE_MODE=02770
    SNAPSHOT_MODE=02750
    LOG_MODE=00640
}

install -d -m 00755 "$BACKUP_ROOT"
install -d -m 00751 "$BACKUP_ROOT"/{latest,snapshot}
install -d -m "$SOURCE_MODE" ${SNAPSHOT_GROUP:+-g "$SNAPSHOT_GROUP"} \
    "$LK_SNAPSHOT_ROOT"
install -d -m "$SNAPSHOT_MODE" ${SNAPSHOT_GROUP:+-g "$SNAPSHOT_GROUP"} \
    "$LK_SNAPSHOT"/{,db,log}
for f in SNAPSHOT_LOG_FILE RSYNC_OUT_FILE RSYNC_ERR_FILE; do
    [ -e "${!f}" ] ||
        install -m "$LOG_MODE" /dev/null "${!f}"
done

LK_SECONDARY_LOG_FILE=$SNAPSHOT_LOG_FILE \
    lk_log_start

RSYNC_EXIT_VALUE=0
RSYNC_RESULT=
RSYNC_STAGE_SUFFIX=

lk_trap_add EXIT exit_trap

{
    lk_console_message "Backing up $SOURCE_NAME to $HN:$BACKUP_ROOT"
    lk_console_detail "Source:" "$SOURCE"
    lk_console_detail "Destination:" "$BACKUP_ROOT on $FQDN"
    lk_console_detail "Transport:" "$SOURCE_TYPE"
    lk_console_detail "Snapshot:" "$LK_SNAPSHOT_TIMESTAMP"
    lk_console_detail "Status:" "$(get_stage)"

    if [ -d "$SOURCE_LATEST/fs" ] &&
        ! is_stage_complete previous-copy-finished; then
        LATEST=$(realpath "$SOURCE_LATEST/fs")
        [ "$LATEST" != "$(realpath "$LK_SNAPSHOT_FS")" ] ||
            lk_die "latest and pending snapshots cannot be the same"
        lk_console_message "Duplicating previous snapshot using hard links"
        ! is_stage_complete previous-copy-started || {
            lk_console_detail "Deleting incomplete replica from previous run"
            rm -Rf "$LK_SNAPSHOT_FS"
        }
        [ ! -e "$LK_SNAPSHOT_FS" ] ||
            lk_die "directory already exists: $LK_SNAPSHOT_FS"
        lk_console_detail "Snapshot:" "$LATEST"
        lk_console_detail "Replica:" "$LK_SNAPSHOT_FS"
        mark_stage_complete previous-copy-started
        # Prevent unwelcome set-group-ID propagation
        install -d -m 00700 "$LK_SNAPSHOT_FS"
        gnu_cp -alT "$LATEST" "$LK_SNAPSHOT_FS"
        mark_stage_complete previous-copy-finished
        lk_console_log "Copy complete"
    else
        mark_stage_complete previous-copy-finished
    fi

    lk_console_item "Creating snapshot at" "$LK_SNAPSHOT"
    lk_console_detail "Log files:" "$(lk_echo_args \
        "$SNAPSHOT_LOG_FILE" "$RSYNC_OUT_FILE" "$RSYNC_ERR_FILE")"
    RSYNC_ARGS=(-vrlpt --delete --stats "$@")
    ! RSYNC_FILTERS=($(find_custom filter-rsync | tac)) || {
        lk_console_detail "Rsync filter:" \
            "$(lk_echo_args "${RSYNC_FILTERS[@]/#/. }")"
        RSYNC_ARGS+=(--delete-excluded)
        for RSYNC_FILTER in "${RSYNC_FILTERS[@]}"; do
            RSYNC_ARGS+=(--filter ". $RSYNC_FILTER")
        done
    }

    run_custom_hook pre_rsync

    ! lk_in_array --inplace RSYNC_ARGS &&
        ! lk_in_array --write-devices RSYNC_ARGS ||
        lk_die "invalid rsync arguments (--inplace not supported)"

    ! lk_in_array --dry-run RSYNC_ARGS &&
        ! lk_in_array -n RSYNC_ARGS || DRY_RUN=1

    [ "${DRY_RUN:-0}" -ne 0 ] || mark_stage_complete rsync-started
    run_rsync || RSYNC_EXIT_VALUE=$?
    EXIT_STATUS=$RSYNC_EXIT_VALUE
    case "$EXIT_STATUS" in
    0)
        RSYNC_RESULT="completed successfully"
        ;;
    23 | 24)
        RSYNC_RESULT="completed with transfer errors"
        RSYNC_STAGE_SUFFIX=partial_transfer
        EXIT_STATUS=0
        ;;
    *)
        RSYNC_RESULT="failed to complete"
        ;;
    esac
    [ "${DRY_RUN:-0}" -ne 0 ] || [ "$EXIT_STATUS" -ne 0 ] ||
        mark_stage_complete \
            "rsync${RSYNC_STAGE_SUFFIX:+-$RSYNC_STAGE_SUFFIX}-finished"
    lk_console_log "rsync $RSYNC_RESULT (exit status $RSYNC_EXIT_VALUE)"

    run_custom_hook post_rsync

    [ "${DRY_RUN:-0}" -ne 0 ] || [ "$EXIT_STATUS" -ne 0 ] || {
        lk_console_message "Updating latest snapshot symlink for $SOURCE_NAME"
        ln -sfnv "$LK_SNAPSHOT" "$BACKUP_ROOT/latest/$SOURCE_NAME"
        mark_stage_complete finished
    }

    exit "$EXIT_STATUS"
}

#!/bin/bash

set -eu

lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (exit $s) && false || exit; }
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
        return 0
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

function lk_echo_args() {
    [ $# -eq 0 ] ||
        printf '%s\n' "$@"
}

function lk_echo_array() {
    eval "lk_echo_args \${$1[@]+\"\${$1[@]}\"}"
}

function lk_console_message() {
    echo "\
$LK_BOLD${_LK_TTY_COLOUR-$LK_CYAN}${_LK_TTY_PREFIX-==> }\
$LK_RESET${_LK_TTY_MESSAGE_COLOUR-$LK_BOLD}\
$(sed "1b
s/^/${_LK_TTY_SPACES-  }/" <<<"$1")$LK_RESET" >&2
}

function lk_console_item() {
    lk_console_message "\
$1$LK_RESET${_LK_TTY_COLOUR2-${_LK_TTY_COLOUR-$LK_CYAN}}$(
        [ "${2/$'\n'/}" = "$2" ] &&
            echo " $2" ||
            echo $'\n'"${2#$'\n'}"
    )"
}

function lk_console_detail() {
    local _LK_TTY_PREFIX="   -> " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR=$LK_YELLOW _LK_TTY_MESSAGE_COLOUR=
    [ $# -le 1 ] &&
        lk_console_message "$1" ||
        lk_console_item "$1" "$2"
}

function lk_console_detail_list() {
    lk_console_detail \
        "$1" "$(COLUMNS=${COLUMNS+$((COLUMNS - 4))} column | expand)"
}

function lk_console_log() {
    local _LK_TTY_PREFIX=" :: " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR2=${_LK_TTY_COLOUR2-$LK_BOLD}
    [ $# -le 1 ] &&
        lk_console_message "${_LK_TTY_COLOUR-$LK_CYAN}$1" ||
        lk_console_item "${_LK_TTY_COLOUR-$LK_CYAN}$1" "$2"
}

function lk_console_success() {
    _LK_TTY_COLOUR=$LK_GREEN lk_console_log "$@"
}

function lk_console_warning() {
    local EXIT_STATUS=$?
    _LK_TTY_COLOUR=$LK_YELLOW lk_console_log "$@"
    return "$EXIT_STATUS"
}

function lk_console_error() {
    local EXIT_STATUS=$?
    _LK_TTY_COLOUR=$LK_RED lk_console_log "$@"
    return "$EXIT_STATUS"
}

function lk_random_hex() {
    printf '%02x' $(for i in $(seq 1 "$1"); do echo $((RANDOM % 256)); done)
    printf '\n'
}

function lk_base64() {
    if type -P openssl >/dev/null &&
        openssl base64 >/dev/null 2>&1 </dev/null; then
        openssl base64
    elif type -P base64 >/dev/null &&
        base64 --version 2>/dev/null </dev/null | grep -i gnu >/dev/null; then
        base64
    else
        false
    fi
}

function lk_mail_new() {
    _LK_MAIL_TEXT=
    _LK_MAIL_HTML=
    _LK_MAIL_ATTACH=()
    _LK_MAIL_ATTACH_NAME=()
    _LK_MAIL_ATTACH_TYPE=()
}

function lk_mail_set_text() {
    _LK_MAIL_TEXT=$1
}

function lk_mail_set_html() {
    _LK_MAIL_HTML=$1
}

# lk_mail_attach FILE_PATH [FILE_NAME [MIME_TYPE]]
function lk_mail_attach() {
    local FILE_NAME MIME_TYPE
    [ -f "$1" ] || return
    FILE_NAME=${2:-${1##*/}}
    MIME_TYPE=${3:-$(file -bi "$(lk_realpath "$1")" | cut -d';' -f1)} ||
        MIME_TYPE=application/octet-stream
    _LK_MAIL_ATTACH=(
        ${_LK_MAIL_ATTACH[@]+"${_LK_MAIL_ATTACH[@]}"} "$1")
    _LK_MAIL_ATTACH_NAME=(
        ${_LK_MAIL_ATTACH_NAME[@]+"${_LK_MAIL_ATTACH_NAME[@]}"} "$FILE_NAME")
    _LK_MAIL_ATTACH_TYPE=(
        ${_LK_MAIL_ATTACH_TYPE[@]+"${_LK_MAIL_ATTACH_TYPE[@]}"} "$MIME_TYPE")
}

# _lk_mail_get_part CONTENT CONTENT_TYPE [ENCODING [HEADER...]]
function _lk_mail_get_part() {
    local BOUNDARY=${ALT_BOUNDARY:-$BOUNDARY}
    cat <<EOF
${BOUNDARY:+${PREAMBLE:+$PREAMBLE
}--${ALT_BOUNDARY:-$BOUNDARY}
}Content-Type: $2${3:+
Content-Transfer-Encoding: $3}$([ $# -lt 4 ] || printf '\n%s' "${@:4}")
${1:+
$1}
EOF
    PREAMBLE=
}

function _lk_mail_end_parts() {
    [ -z "${!1}" ] || {
        printf -- '--%s--\n\n' "${!1}"
        eval "$1="
    }
}

# lk_mail_get_mime SUBJECT TO [FROM [HEADERS...]]
#
# shellcheck disable=SC2097,SC2098
function lk_mail_get_mime() {
    local SUBJECT TO FROM HEADERS BOUNDARY='' ALT_BOUNDARY='' ALT_TYPE i \
        TEXT TEXT_PART=() TEXT_PART_TYPE=() ENCODING=8bit CHARSET=utf-8 \
        PREAMBLE="This is a multi-part message in MIME format."
    [ $# -ge 2 ] || return
    SUBJECT=$1
    TO=$2
    FROM=${3:-${LK_MAIL_FROM-$USER@$FQDN}} || return
    case "$SUBJECT$TO$FROM" in
    *$'\r'* | *$'\n'*)
        lk_die "line breaks not permitted in SUBJECT, TO, or FROM"
        ;;
    esac
    HEADERS=(
        "From: $FROM"
        "To: $TO"
        "Date: $(date -R)"
        "Subject: $SUBJECT"
        "${@:4}"
    )
    TEXT_PART=(${_LK_MAIL_TEXT:+"$_LK_MAIL_TEXT"}
        ${_LK_MAIL_HTML:+"$_LK_MAIL_HTML"})
    TEXT_PART_TYPE=(${_LK_MAIL_TEXT:+"text/plain"}
        ${_LK_MAIL_HTML:+"text/html"})
    lk_echo_array TEXT_PART |
        grep -v "^[[:alnum:][:space:][:punct:][:cntrl:]]*\$" >/dev/null || {
        ENCODING=7bit
        CHARSET=us-ascii
    }
    [ ${#TEXT_PART[@]} -le 1 ] || {
        ALT_BOUNDARY=$(lk_random_hex 12)
        ALT_TYPE="multipart/alternative; boundary=$ALT_BOUNDARY"
    }
    [ ${#_LK_MAIL_ATTACH[@]} -eq 0 ] ||
        { [ ${#_LK_MAIL_ATTACH[@]} -eq 1 ] && [ ${#TEXT_PART[@]} -eq 0 ]; } ||
        BOUNDARY=$(lk_random_hex 12)
    [ -z "${BOUNDARY:-$ALT_BOUNDARY}" ] || {
        [ -n "$BOUNDARY" ] &&
            HEADERS=(${HEADERS[@]+"${HEADERS[@]}"}
                "MIME-Version: 1.0"
                "Content-Type: multipart/mixed; boundary=$BOUNDARY"
                "") ||
            HEADERS=(${HEADERS[@]+"${HEADERS[@]}"}
                "MIME-Version: 1.0"
                "Content-Type: $ALT_TYPE"
                "Content-Transfer-Encoding: $ENCODING"
                "")
    }
    lk_echo_array HEADERS
    [ -z "$BOUNDARY" ] || [ -z "$ALT_BOUNDARY" ] ||
        ALT_BOUNDARY='' _lk_mail_get_part "" "$ALT_TYPE" "$ENCODING"
    [ ${#TEXT_PART[@]} -eq 0 ] ||
        for i in $(seq 0 $((${#TEXT_PART[@]} - 1))); do
            TEXT=${TEXT_PART[$i]}
            [ "${TEXT: -1:1}" = $'\n' ] || TEXT=$TEXT$'\n'
            _lk_mail_get_part "$TEXT" \
                "${TEXT_PART_TYPE[$i]}; charset=$CHARSET" "$ENCODING"
        done
    _lk_mail_end_parts ALT_BOUNDARY
    [ ${#_LK_MAIL_ATTACH[@]} -eq 0 ] ||
        for i in $(seq 0 $((${#_LK_MAIL_ATTACH[@]} - 1))); do
            _lk_mail_get_part "" \
                "$(printf '%s; name="%s"' \
                    "${_LK_MAIL_ATTACH_TYPE[$i]}" \
                    "${_LK_MAIL_ATTACH_NAME[$i]//\"/\\\"}")" \
                "base64" \
                "$(printf 'Content-Disposition: attachment; filename="%s"' \
                    "${_LK_MAIL_ATTACH_NAME[$i]//\"/\\\"}")"
            lk_base64 <"${_LK_MAIL_ATTACH[$i]}" || return
        done
    _lk_mail_end_parts BOUNDARY
}

# lk_mail_send SUBJECT TO [FROM [HEADERS...]]
function lk_mail_send() {
    [ $# -ge 2 ] || return
    lk_mail_get_mime "$@" | if type -P sendmail >/dev/null; then
        sendmail -oi -t
    elif type -P msmtp >/dev/null; then
        msmtp -oi -t
    else
        false
    fi
}

LK_BOLD=$'\E[1m'
LK_RED=$'\E[31m'
LK_GREEN=$'\E[32m'
LK_YELLOW=$'\E[33m'
LK_CYAN=$'\E[36m'
LK_RESET=$'\E[m\017'

##

function exit_trap() {
    local EXIT_STATUS=$? MESSAGE TAR SUBJECT
    exec 8>&- &&
        rm -Rf "${FIFO_FILE%/*}" || true
    [ -z "${LOCK_FILE-}" ] || {
        exec 9>&- &&
            rm -f "$LOCK_FILE" || true
    }
    # Redirecting output with one command would keep SNAPSHOT_LOG_FILE open
    # (even though nothing further would be written to it)
    # 1. Close SNAPSHOT_LOG_FILE by restoring original stdout and stderr
    exec >&6 2>&7 &&
        # 2. Reopen LOG_FILE for any further output
        exec > >(tee >(lk_log >>"$LOG_FILE")) 2>&1
    [ -z "$LK_BACKUP_MAIL" ] ||
        { [ "$EXIT_STATUS" -eq 0 ] &&
            [ "$RSYNC_EXIT_VALUE" -eq 0 ] &&
            [ "$LK_BACKUP_MAIL_ERROR_ONLY" = Y ]; } || {
        lk_mail_new
        MESSAGE=
        { [ ! -s "$RSYNC_OUT_FILE" ] && [ ! -s "$RSYNC_ERR_FILE" ]; } ||
            ! TAR=$(mktemp -- "${TMPDIR%/}/${0##*/}.XXXXXXXXXX") ||
            ! tar -C "${RSYNC_OUT_FILE%/*}" -czf "$TAR" \
                "${RSYNC_OUT_FILE##*/}" \
                "${RSYNC_ERR_FILE##*/}" || {
            lk_mail_attach \
                "$TAR" \
                "$HN-$SOURCE_NAME-$LK_SNAPSHOT_TIMESTAMP-rsync.log.tgz" \
                application/gzip &&
                MESSAGE="the attached log files and " || true
            rm -f "$TAR" || true
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
$(printf '%q' "$0" && { [ ${#ARGS[@]} -eq 0 ] || printf ' \\\n    %q' "${ARGS[@]}"; })

Output:

$(sed \
            -e $'s/\x01[^\x02]*\x02//g' \
            -e $'s/\x1b\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]//g' \
            -e $'s/\x1b[\x20-\x2f]*[\x30-\x7e]//g' \
            "$SNAPSHOT_LOG_FILE")" &&
            lk_mail_set_text "$MESSAGE" &&
            lk_mail_send "$SUBJECT" "$LK_BACKUP_MAIL" "$LK_BACKUP_MAIL_FROM" || true
    }
}

function find_custom() {
    local FILE COUNT=0
    for FILE in {"$_DIR","$BACKUP_ROOT/conf.d"}/{"$1","$SOURCE_NAME-$1","$SOURCE_NAME/$1"}; do
        [ -e "$FILE" ] || continue
        lk_realpath "$FILE" || lk_die
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
                    _LK_TTY_COLOUR2='' lk_console_error "\
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
    local SRC=${1-} DEST=${2-}
    [ $# -eq 2 ] || {
        SRC=${SOURCE%/}/
        DEST=$LK_SNAPSHOT_FS/
    }
    lk_console_item "Running rsync:" \
        $'>>>\n'"  rsync$(printf ' \\ \n    %q' \
            "${RSYNC_ARGS[@]}" "$SRC" "$DEST")"$'\n<<<'
    rsync "${RSYNC_ARGS[@]}" "$SRC" "$DEST" \
        > >(tee -a "$RSYNC_OUT_FILE" >&6) \
        2> >(tee -a "$RSYNC_ERR_FILE" >&7)
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

[ $# -ge 3 ] || {
    echo "\
Usage: ${0##*/} SOURCE_NAME SSH_HOST:SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME RSYNC_HOST::SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]
   or: ${0##*/} SOURCE_NAME SOURCE_PATH BACKUP_ROOT [RSYNC_ARG...]

Use hard links to duplicate the previous SOURCE_NAME snapshot at BACKUP_ROOT,
then rsync SOURCE_PATH to the replica to create a new snapshot of SOURCE_NAME.

This approach uses less storage than rsync --link-dest, which breaks hard links
when permissions change." >&2
    exit 1
}

ARGS=("$@")

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
exec 8<>"$FIFO_FILE"

export LC_ALL=C TZ=UTC
USER=${USER:-$(id -un)}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
HN=$(hostname -s) || HN=localhost
FQDN=$(hostname -f) || FQDN=$HN.localdomain
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
LOG_FILE=$BACKUP_ROOT/log/snapshot.log
SNAPSHOT_LOG_FILE=$LK_SNAPSHOT/log/snapshot.log
RSYNC_OUT_FILE=$LK_SNAPSHOT/log/rsync.log
RSYNC_ERR_FILE=$LK_SNAPSHOT/log/rsync.err.log

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
install -d -m 00751 "$BACKUP_ROOT"/{latest,log,snapshot}
install -d -m "$SOURCE_MODE" ${SNAPSHOT_GROUP:+-g "$SNAPSHOT_GROUP"} \
    "$BACKUP_ROOT/snapshot/$SOURCE_NAME"
install -d -m "$SNAPSHOT_MODE" ${SNAPSHOT_GROUP:+-g "$SNAPSHOT_GROUP"} \
    "$BACKUP_ROOT/snapshot/$SOURCE_NAME/$LK_SNAPSHOT_TIMESTAMP"/{,db,log}
for f in LOG_FILE SNAPSHOT_LOG_FILE RSYNC_OUT_FILE RSYNC_ERR_FILE; do
    [ -e "${!f}" ] ||
        install -m "$LOG_MODE" /dev/null "${!f}"
done

if [[ $- != *x* ]]; then
    lk_log >>"$LOG_FILE" <<<"====> $(lk_realpath "$0") invoked on $FQDN"
    exec 6>&1 7>&2
    exec > >(tee >(lk_log | tee -a "$SNAPSHOT_LOG_FILE" >>"$LOG_FILE")) 2>&1
fi

RSYNC_EXIT_VALUE=0
RSYNC_RESULT=
RSYNC_STAGE_SUFFIX=

trap exit_trap EXIT

{
    lk_console_message "Backing up $SOURCE_NAME to $HN:$BACKUP_ROOT"
    lk_console_detail "Source:" "$SOURCE"
    lk_console_detail "Destination:" "$BACKUP_ROOT on $FQDN"
    lk_console_detail "Transport:" "$SOURCE_TYPE"
    lk_console_detail "Snapshot:" "$LK_SNAPSHOT_TIMESTAMP"
    lk_console_detail "Status:" "$(get_stage)"

    if [ -d "$SOURCE_LATEST/fs" ] && ! is_stage_complete previous-copy-finished; then
        LATEST=$(lk_realpath "$SOURCE_LATEST/fs")
        [ "$LATEST" != "$(lk_realpath "$LK_SNAPSHOT_FS")" ] ||
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
        LATEST_MODE=$(stat --format=%a "$LATEST")
        install -d -m "0$LATEST_MODE" "$LK_SNAPSHOT_FS"
        (shopt -s dotglob &&
            cp -al "$LATEST"/* "$LK_SNAPSHOT_FS")
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
        RSYNC_ARGS[${#RSYNC_ARGS[@]}]=--delete-excluded
        for RSYNC_FILTER in "${RSYNC_FILTERS[@]}"; do
            RSYNC_ARGS[${#RSYNC_ARGS[@]}]=--filter
            RSYNC_ARGS[${#RSYNC_ARGS[@]}]=". $RSYNC_FILTER"
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
        ln -sfnv "$LK_SNAPSHOT" "$SOURCE_LATEST"
        mark_stage_complete finished
    }

    exit "$EXIT_STATUS"
}

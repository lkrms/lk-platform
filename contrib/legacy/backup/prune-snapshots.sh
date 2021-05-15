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

function lk_date_log() {
    date +"%Y-%m-%d %H:%M:%S %z"
}

function lk_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(lk_date_log)" "$LINE"
    done
}

function lk_maybe_plural() {
    [ "$1" -eq 1 ] && echo "$2" || echo "$3"
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

function lk_mapfile() {
    local i=0 LINE
    eval "$1=()"
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        eval "$1[$((i++))]=\$LINE"
    done <"$2"
}

LK_BOLD=$'\E[1m'
LK_RED=$'\E[31m'
LK_GREEN=$'\E[32m'
LK_YELLOW=$'\E[33m'
LK_CYAN=$'\E[36m'
LK_RESET=$'\E[m\017'

##

function find_snapshots() {
    lk_mapfile "$1" <(
        find "$SNAPSHOT_ROOT" \
            -mindepth 1 -maxdepth 1 -type d \
            -regex ".*/${BACKUP_TIMESTAMP_FINDUTILS_REGEX}[^/]*" \
            "${@:2}" \
            -printf '%f\n' | sort -r
    )
    eval "$1_COUNT=\${#$1[@]}"
}

function snapshot_date() {
    echo "${1:0:10}"
}

function first_snapshot_on_date() {
    lk_echo_array SNAPSHOTS_CLEAN |
        grep "^$1" |
        tail -n1
    return "${PIPESTATUS[1]}"
}

function snapshot_hour() {
    echo "${1:0:10} ${1:11:2}:00:00"
}

function first_snapshot_in_hour() {
    lk_echo_array SNAPSHOTS_CLEAN |
        grep "^${1:0:10}-${1:11:2}" |
        tail -n1
    return "${PIPESTATUS[1]}"
}

function prune_snapshot() {
    local PRUNE=$SNAPSHOT_ROOT/$1
    lk_console_item \
        "Pruning (${2:-expired}):" "${PRUNE#$BACKUP_ROOT/snapshot/}"
    touch "$PRUNE/.pruning" &&
        rm -Rf "$PRUNE"
}

function get_usage() {
    df --sync --portability --block-size=$((1024 * 1024)) "$@" |
        awk 'NR > 1 { print $3 "M", $5 }'
}

function print_max_age() {
    case "$1" in
    "")
        lk_console_detail "$2 snapshots" \
            "do not expire"
        ;;
    0)
        lk_console_detail "$2 snapshots" \
            "expire immediately"
        ;;
    *)
        lk_console_detail "$2 snapshots" \
            "expire after $1 $(lk_maybe_plural "$1" "$3" "$4")"
        ;;
    esac
}

HOURLY_MAX_AGE=${LK_SNAPSHOT_HOURLY_MAX_AGE-24}
DAILY_MAX_AGE=${LK_SNAPSHOT_DAILY_MAX_AGE-7}
WEEKLY_MAX_AGE=${LK_SNAPSHOT_WEEKLY_MAX_AGE-52}
FAILED_MAX_AGE=${LK_SNAPSHOT_FAILED_MAX_AGE-28}

[ "${HOURLY_MAX_AGE:--1}" -gt -1 ] || HOURLY_MAX_AGE=
[ "${DAILY_MAX_AGE:--1}" -gt -1 ] || DAILY_MAX_AGE=
[ "${WEEKLY_MAX_AGE:--1}" -gt -1 ] || WEEKLY_MAX_AGE=
[ "${FAILED_MAX_AGE:--1}" -gt -1 ] || FAILED_MAX_AGE=

[ $# -ge 1 ] || {
    echo "\
Usage: ${0##*/} BACKUP_ROOT" >&2
    exit 1
}

BACKUP_ROOT=$1

[ -d "$BACKUP_ROOT" ] || lk_die "directory not found: $BACKUP_ROOT"
[ -d "$BACKUP_ROOT/snapshot" ] || {
    lk_console_log "Nothing to prune"
    exit
}

BACKUP_ROOT=$(lk_realpath "$BACKUP_ROOT")
! type -P flock >/dev/null || {
    LOCK_FILE=/tmp/${0##*/}-${BACKUP_ROOT//\//_}.lock
    exec 9>"$LOCK_FILE" &&
        flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"
}

export LC_ALL=C TZ=UTC
HN=$(hostname -s) || HN=localhost
FQDN=$(hostname -f) || FQDN=$HN.localdomain
_2="[0-9][0-9]"
_4="$_2$_2"
BACKUP_TIMESTAMP_FINDUTILS_REGEX="$_4-$_2-$_2-$_4$_2"

LOG_FILE=$BACKUP_ROOT/log/snapshot-prune.log
install -d -m 00711 "$BACKUP_ROOT/log"
[ -e "$LOG_FILE" ] ||
    install -m 00600 /dev/null "$LOG_FILE"

if [[ $- != *x* ]]; then
    lk_log >>"$LOG_FILE" <<<"====> $(lk_realpath "$0") invoked on $FQDN"
    exec 6>&1 7>&2
    exec > >(tee >(lk_log >>"$LOG_FILE")) 2>&1
fi

{
    USAGE_START=($(get_usage "$BACKUP_ROOT"))
    lk_console_log "Pruning backups at $BACKUP_ROOT on $FQDN (storage used: ${USAGE_START[0]}/${USAGE_START[1]})"
    lk_console_message "Settings:"
    print_max_age "$HOURLY_MAX_AGE" Hourly hour hours
    print_max_age "$DAILY_MAX_AGE" Daily day days
    print_max_age "$WEEKLY_MAX_AGE" Weekly week weeks
    print_max_age "$FAILED_MAX_AGE" Failed day days
    lk_mapfile SOURCE_NAMES <(find "$BACKUP_ROOT/snapshot" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | sort)
    for SOURCE_NAME in ${SOURCE_NAMES[@]+"${SOURCE_NAMES[@]}"}; do
        lk_console_message "Checking '$SOURCE_NAME' snapshots"
        SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME

        find_snapshots SNAPSHOTS_CLEAN \
            -exec test -e '{}/.finished' \; \
            ! -exec test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_CLEAN_COUNT" -gt 0 ] ||
            lk_console_warning "Skipping $SOURCE_NAME (no clean snapshots)" ||
            continue
        LATEST_CLEAN=$(snapshot_date "${SNAPSHOTS_CLEAN[0]}")
        OLDEST_CLEAN=$(snapshot_date \
            "${SNAPSHOTS_CLEAN[$((SNAPSHOTS_CLEAN_COUNT - 1))]}")
        lk_console_detail "Clean:" \
            "$SNAPSHOTS_CLEAN_COUNT ($([ "$LATEST_CLEAN" = "$OLDEST_CLEAN" ] ||
                echo "$OLDEST_CLEAN to ")$LATEST_CLEAN)"

        find_snapshots SNAPSHOTS_PRUNING -exec test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_PRUNING_COUNT" -eq 0 ] ||
            lk_console_detail \
                "Partially pruned:" "$SNAPSHOTS_PRUNING_COUNT"

        if [ -n "$FAILED_MAX_AGE" ]; then
            PRUNE_FAILED_BEFORE_DATE=$(date \
                -d "$LATEST_CLEAN $FAILED_MAX_AGE days ago" +"%F")
            # Add a strict -regex test to keep failed snapshots with
            # non-standard names
            find_snapshots SNAPSHOTS_FAILED \
                -exec test ! -e '{}/.finished' \; \
                -regex ".*/$BACKUP_TIMESTAMP_FINDUTILS_REGEX" \
                -exec sh -c 'test "${1##*/}" \< "$2"' sh \
                '{}' "$PRUNE_FAILED_BEFORE_DATE" \;
            [ "$SNAPSHOTS_FAILED_COUNT" -eq 0 ] ||
                lk_console_detail "Failed >$FAILED_MAX_AGE days ago:" \
                    "$SNAPSHOTS_FAILED_COUNT"
        fi

        # Keep the latest snapshot
        KEEP=(
            "${SNAPSHOTS_CLEAN[0]}"
        )

        # Keep one snapshot per hour for the last HOURLY_MAX_AGE hours
        # (indefinitely if HOURLY_MAX_AGE is empty)
        LATEST_CLEAN_HOUR=$(snapshot_hour "${SNAPSHOTS_CLEAN[0]}")
        OLDEST_CLEAN_HOUR=$(snapshot_hour \
            "${SNAPSHOTS_CLEAN[$((SNAPSHOTS_CLEAN_COUNT - 1))]}")
        HOUR=$LATEST_CLEAN_HOUR
        HOURS=0
        while { [ "$OLDEST_CLEAN_HOUR" \< "$HOUR" ] ||
            [ "$OLDEST_CLEAN_HOUR" = "$HOUR" ]; } &&
            { [ -z "$HOURLY_MAX_AGE" ] ||
                [ $((HOURS++)) -le "$HOURLY_MAX_AGE" ]; }; do
            ! SNAPSHOT=$(first_snapshot_in_hour "$HOUR") ||
                KEEP[${#KEEP[@]}]=$SNAPSHOT
            HOUR=$(date -d "$LATEST_CLEAN_HOUR $HOURS hours ago" +"%F %T")
        done

        # Keep one snapshot per day for the last DAILY_MAX_AGE days
        # (indefinitely if DAILY_MAX_AGE is empty)
        DAY=$LATEST_CLEAN
        DAYS=0
        while { [ "$OLDEST_CLEAN" \< "$DAY" ] ||
            [ "$OLDEST_CLEAN" = "$DAY" ]; } &&
            { [ -z "$DAILY_MAX_AGE" ] ||
                [ $((DAYS++)) -le "$DAILY_MAX_AGE" ]; }; do
            ! SNAPSHOT=$(first_snapshot_on_date "$DAY") ||
                KEEP[${#KEEP[@]}]=$SNAPSHOT
            DAY=$(date -d "$LATEST_CLEAN $DAYS days ago" +"%F")
        done

        # Keep one snapshot per week for the last WEEKLY_MAX_AGE weeks
        # (indefinitely if WEEKLY_MAX_AGE is empty)
        SUNDAY=$(date -d "$(date -d "$LATEST_CLEAN" +"%F %u days ago")" +"%F")
        WEEKS=0
        while { [ "$OLDEST_CLEAN" \< "$SUNDAY" ] ||
            [ "$OLDEST_CLEAN" = "$SUNDAY" ]; } &&
            { [ -z "$WEEKLY_MAX_AGE" ] ||
                [ $((WEEKS++)) -le "$WEEKLY_MAX_AGE" ]; }; do
            DAY=$SUNDAY
            for i in $(seq 0 6); do
                [ "$i" -eq 0 ] || DAY=$(date -d "$SUNDAY $i days ago" +"%F")
                SNAPSHOT=$(first_snapshot_on_date "$DAY") || continue
                KEEP[${#KEEP[@]}]=$SNAPSHOT
                break
            done
            SUNDAY=$(date -d "$SUNDAY 7 days ago" +"%F")
        done

        # Keep snapshots with non-standard names
        lk_mapfile _KEEP <(lk_echo_array SNAPSHOTS_CLEAN |
            grep -v "^$BACKUP_TIMESTAMP_FINDUTILS_REGEX$")
        KEEP=("${KEEP[@]}" ${_KEEP[@]+"${_KEEP[@]}"})

        lk_mapfile SNAPSHOTS_KEEP <(
            lk_echo_array KEEP | sort -ru
        )
        SNAPSHOTS_KEEP_COUNT=${#SNAPSHOTS_KEEP[@]}

        lk_mapfile SNAPSHOTS_PRUNE <(comm -23 \
            <(lk_echo_array SNAPSHOTS_CLEAN | sort) \
            <(lk_echo_array SNAPSHOTS_KEEP | sort))
        SNAPSHOTS_PRUNE_COUNT=${#SNAPSHOTS_PRUNE[@]}

        lk_console_detail \
            "Expired:" "$SNAPSHOTS_PRUNE_COUNT"
        lk_console_detail \
            "Fresh:" "$SNAPSHOTS_KEEP_COUNT" "$LK_BOLD$LK_GREEN"

        [ "$SNAPSHOTS_PRUNING_COUNT" -eq 0 ] || {
            for SNAPSHOT in "${SNAPSHOTS_PRUNING[@]}"; do
                prune_snapshot "$SNAPSHOT" "partially pruned" || lk_die
            done
        }
        [ "${SNAPSHOTS_FAILED_COUNT:-0}" -eq 0 ] || {
            for SNAPSHOT in "${SNAPSHOTS_FAILED[@]}"; do
                prune_snapshot "$SNAPSHOT" "failed" || lk_die
            done
        }
        [ "$SNAPSHOTS_PRUNE_COUNT" -eq 0 ] || {
            for SNAPSHOT in "${SNAPSHOTS_PRUNE[@]}"; do
                prune_snapshot "$SNAPSHOT" || lk_die
            done
        }
    done
    [ -z "${LOCK_FILE-}" ] || {
        exec 9>&- &&
            rm -f "$LOCK_FILE" || true
    }
    USAGE_END=($(get_usage "$BACKUP_ROOT"))
    lk_console_success \
        "Pruning complete (storage used: ${USAGE_END[0]}/${USAGE_END[1]})"
    exit
}

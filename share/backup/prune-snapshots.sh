#!/bin/bash

# shellcheck disable=SC2015,SC2016,SC2153,SC2207

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

function lk_date_log() {
    date +"%Y-%m-%d %H:%M:%S %z"
}

function lk_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(lk_date_log)" "$LINE"
    done
}

function lk_echo_array() {
    eval "printf '%s\n' \${$1[@]+\"\${$1[@]}\"}"
}

function lk_console_message() {
    local SPACES=${LK_CONSOLE_SPACES-  }
    echo "\
$LK_BOLD${LK_CONSOLE_COLOUR-$LK_CYAN}${LK_CONSOLE_PREFIX-==> }\
$LK_RESET${LK_CONSOLE_MESSAGE_COLOUR-$LK_BOLD}\
$(sed "1b;s/^/$SPACES/" <<<"$1")$LK_RESET"
}

function lk_console_item() {
    lk_console_message "\
$1$LK_RESET${LK_CONSOLE_COLOUR2-${LK_CONSOLE_COLOUR-$LK_CYAN}}$(
        [ "${2/$'\n'/}" = "$2" ] &&
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

function lk_console_detail_list() {
    lk_console_detail \
        "$1" "$(COLUMNS=${COLUMNS+$((COLUMNS - 4))} column | expand)"
}

function lk_console_log() {
    local LK_CONSOLE_PREFIX=" :: " LK_CONSOLE_SPACES="    " \
        LK_CONSOLE_COLOUR2=${LK_CONSOLE_COLOUR2-$LK_BOLD}
    [ $# -le 1 ] &&
        lk_console_message "${LK_CONSOLE_COLOUR-$LK_CYAN}$1" ||
        lk_console_item "${LK_CONSOLE_COLOUR-$LK_CYAN}$1" "$2"
}

function lk_console_warning() {
    local EXIT_STATUS=$?
    LK_CONSOLE_COLOUR=$LK_YELLOW lk_console_log "$@"
    return "$EXIT_STATUS"
}

function lk_console_success() {
    LK_CONSOLE_COLOUR=$LK_GREEN lk_console_log "$@"
}

function lk_mapfile() {
    local i=0 LINE
    eval "$2=()"
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        eval "$2[$((i++))]=\$LINE"
    done <"$1"
}

LK_BOLD=$(tput bold 2>/dev/null) || LK_BOLD=
LK_GREEN=$(tput setaf 2 2>/dev/null) || LK_GREEN=
LK_CYAN=$(tput setaf 6 2>/dev/null) || LK_CYAN=
LK_YELLOW=$(tput setaf 3 2>/dev/null) || LK_YELLOW=
LK_RESET=$(tput sgr0 2>/dev/null) || LK_RESET=

##

function find_snapshots() {
    lk_mapfile <(
        find "$SNAPSHOT_ROOT" \
            -mindepth 1 -maxdepth 1 -type d \
            -regex ".*/${BACKUP_TIMESTAMP_FINDUTILS_REGEX}[^/]*" \
            "${@:2}" \
            -printf '%f\n' | sort -r
    ) "$1"
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

function prune_snapshot() {
    local PRUNE=$SNAPSHOT_ROOT/$1
    lk_console_warning "Pruning ${PRUNE#$BACKUP_ROOT/snapshot/}"
    touch "$PRUNE/.pruning" &&
        rm -Rf "$PRUNE"
}

function get_usage() {
    df --sync --portability --block-size=$((1024 * 1024)) "$@" |
        awk 'NR > 1 { print $3, $5 }'
}

PRUNE_DAILY_AFTER_DAYS=${LK_SNAPSHOT_PRUNE_DAILY_AFTER_DAYS:-7}
PRUNE_FAILED_AFTER_DAYS=${LK_SNAPSHOT_PRUNE_FAILED_AFTER_DAYS-28}
PRUNE_WEEKLY_AFTER_WEEKS=${LK_SNAPSHOT_PRUNE_WEEKLY_AFTER_WEEKS-52}

[ $# -ge 1 ] || LK_DIE_PREFIX='' lk_die "\
Usage: ${0##*/} BACKUP_ROOT"

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
    TZ=UTC
    lk_console_log "Pruning backups at $BACKUP_ROOT on $FQDN"
    USAGE_START=($(get_usage "$BACKUP_ROOT"))
    lk_console_detail "Storage used on backup volume:" \
        "${USAGE_START[0]%M}M (${USAGE_START[1]})"
    lk_mapfile <(find "$BACKUP_ROOT/snapshot" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | sort) SOURCE_NAMES
    for SOURCE_NAME in ${SOURCE_NAMES[@]+"${SOURCE_NAMES[@]}"}; do
        lk_console_message "Checking $SOURCE_NAME snapshots"
        SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME
        lk_console_detail "Snapshot directory:" "$SNAPSHOT_ROOT"

        find_snapshots SNAPSHOTS_CLEAN \
            -exec test -e '{}/.finished' \; \
            ! -exec test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_CLEAN_COUNT" -gt 0 ] ||
            lk_console_warning "Skipping $SOURCE_NAME (no clean snapshots)" ||
            continue
        LATEST_CLEAN=$(snapshot_date "${SNAPSHOTS_CLEAN[0]}")
        OLDEST_CLEAN=$(snapshot_date \
            "${SNAPSHOTS_CLEAN[$((SNAPSHOTS_CLEAN_COUNT - 1))]}")
        lk_console_detail "Clean snapshots:" \
            "$SNAPSHOTS_CLEAN_COUNT ($([ "$LATEST_CLEAN" = "$OLDEST_CLEAN" ] ||
                echo "$OLDEST_CLEAN to ")$LATEST_CLEAN)"

        find_snapshots SNAPSHOTS_PRUNING -exec test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_PRUNING_COUNT" -eq 0 ] || {
            lk_echo_array SNAPSHOTS_PRUNING |
                lk_console_detail_list \
                    "Removing $SNAPSHOTS_PRUNING_COUNT partially pruned snapshot(s):"
            for SNAPSHOT in "${SNAPSHOTS_PRUNING[@]}"; do
                prune_snapshot "$SNAPSHOT" || lk_die
            done
        }

        if [ -n "$PRUNE_FAILED_AFTER_DAYS" ]; then
            PRUNE_FAILED_BEFORE_DATE=$(date \
                -d "$LATEST_CLEAN -$PRUNE_FAILED_AFTER_DAYS day" +"%F")
            # Add a strict -regex test to keep failed snapshots with
            # non-standard names
            find_snapshots SNAPSHOTS_FAILED \
                -exec test ! -e '{}/.finished' \; \
                -regex ".*/$BACKUP_TIMESTAMP_FINDUTILS_REGEX" \
                -exec sh -c 'test "${1##*/}" \< "$2"' sh \
                '{}' "$PRUNE_FAILED_BEFORE_DATE" \;
            [ "$SNAPSHOTS_FAILED_COUNT" -eq 0 ] || {
                lk_echo_array SNAPSHOTS_FAILED |
                    lk_console_detail_list \
                        "Removing $SNAPSHOTS_FAILED_COUNT failed snapshot(s):"
                for SNAPSHOT in "${SNAPSHOTS_FAILED[@]}"; do
                    prune_snapshot "$SNAPSHOT" || lk_die
                done
            }
        fi

        # Keep the latest snapshot
        KEEP=(
            "${SNAPSHOTS_CLEAN[0]}"
        )

        # Keep one snapshot per day for the last PRUNE_DAILY_AFTER_DAYS
        DAY=$LATEST_CLEAN
        for i in $(seq 0 "$PRUNE_DAILY_AFTER_DAYS"); do
            [ "$i" -eq 0 ] || DAY=$(date -d "$LATEST_CLEAN -$i day" +"%F")
            SNAPSHOT=$(first_snapshot_on_date "$DAY") || continue
            KEEP[${#KEEP[@]}]=$SNAPSHOT
        done

        # Keep one snapshot per week for the last PRUNE_WEEKLY_AFTER_WEEKS
        # (indefinitely if PRUNE_WEEKLY_AFTER_WEEKS is the empty string)
        SUNDAY=$(date -d "$(date -d "$LATEST_CLEAN" +"%F -%u day")" +"%F")
        WEEKS=0
        while { [ "$OLDEST_CLEAN" \< "$SUNDAY" ] ||
            [ "$OLDEST_CLEAN" = "$SUNDAY" ]; } &&
            { [ -z "$PRUNE_WEEKLY_AFTER_WEEKS" ] ||
                [ $((WEEKS++)) -le "$PRUNE_WEEKLY_AFTER_WEEKS" ]; }; do
            DAY=$SUNDAY
            for i in $(seq 0 6); do
                [ "$i" -eq 0 ] || DAY=$(date -d "$SUNDAY -$i day" +"%F")
                SNAPSHOT=$(first_snapshot_on_date "$DAY") || continue
                KEEP[${#KEEP[@]}]=$SNAPSHOT
                break
            done
            SUNDAY=$(date -d "$SUNDAY -7 day" +"%F")
        done

        # Keep snapshots with non-standard names
        lk_mapfile <(lk_echo_array SNAPSHOTS_CLEAN |
            grep -v "^$BACKUP_TIMESTAMP_FINDUTILS_REGEX$") _KEEP
        KEEP=("${KEEP[@]}" ${_KEEP[@]+"${_KEEP[@]}"})

        lk_mapfile <(
            lk_echo_array KEEP | sort -ru
        ) SNAPSHOTS_KEEP

        lk_mapfile <(comm -23 \
            <(lk_echo_array SNAPSHOTS_CLEAN | sort) \
            <(lk_echo_array SNAPSHOTS_KEEP | sort)) \
            SNAPSHOTS_PRUNE
        SNAPSHOTS_PRUNE_COUNT=${#SNAPSHOTS_PRUNE[@]}
        [ "$SNAPSHOTS_PRUNE_COUNT" -eq 0 ] || {
            lk_echo_array SNAPSHOTS_PRUNE | tac |
                lk_console_detail_list \
                    "Removing $SNAPSHOTS_PRUNE_COUNT expired snapshot(s):"
            for SNAPSHOT in "${SNAPSHOTS_PRUNE[@]}"; do
                prune_snapshot "$SNAPSHOT" || lk_die
            done
        }
    done
    [ -z "${LOCK_FILE:-}" ] || {
        exec 9>&- &&
            rm -f "$LOCK_FILE" || true
    }
    lk_console_success "Pruning complete"
    USAGE_END=($(get_usage "$BACKUP_ROOT"))
    lk_console_detail "Storage used on backup volume:" \
        "${USAGE_END[0]%M}M (${USAGE_END[1]})"
    exit
}

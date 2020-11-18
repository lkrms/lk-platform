#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2016,SC2207,SC2153

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
}

function snapshot_hour() {
    echo "${1:0:10} ${1:11:2}:00:00"
}

function first_snapshot_in_hour() {
    lk_echo_array SNAPSHOTS_CLEAN |
        grep "^${1:0:10}-${1:11:2}" |
        tail -n1
}

function prune_snapshot() {
    local PRUNE=$SNAPSHOT_ROOT/$1
    lk_console_item \
        "Pruning (${2:-expired}):" "${PRUNE#$BACKUP_ROOT/snapshot/}"
    touch "$PRUNE/.pruning" &&
        rm -Rf "$PRUNE"
}

function get_usage() {
    gnu_df --sync --output=used,pcent --block-size=M "$@" | sed '1d'
}

PRUNE_HOURLY_AFTER=${LK_SNAPSHOT_PRUNE_HOURLY_AFTER-24}
PRUNE_DAILY_AFTER=${LK_SNAPSHOT_PRUNE_DAILY_AFTER:-7}
PRUNE_FAILED_AFTER_DAYS=${LK_SNAPSHOT_PRUNE_FAILED_AFTER_DAYS-28}
PRUNE_WEEKLY_AFTER=${LK_SNAPSHOT_PRUNE_WEEKLY_AFTER-52}

LK_USAGE="\
Usage: ${0##*/} BACKUP_ROOT"

[ $# -ge 1 ] || lk_usage

BACKUP_ROOT=$1

[ -d "$BACKUP_ROOT" ] || lk_die "directory not found: $BACKUP_ROOT"
[ -d "$BACKUP_ROOT/snapshot" ] || {
    lk_console_log "Nothing to prune"
    exit
}

BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
LOCK_FILE=/tmp/${0##*/}-${BACKUP_ROOT//\//_}.lock
LOCK_FD=$(lk_next_fd)
eval "exec $LOCK_FD>\"\$LOCK_FILE\""
flock -n "$LOCK_FD" || lk_die "unable to acquire a lock on $LOCK_FILE"

export TZ=UTC
HN=$(lk_hostname) || HN=localhost
FQDN=$(lk_fqdn) || FQDN=$HN.localdomain
eval "$(lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX)"

lk_log_output

{
    USAGE_START=($(get_usage "$BACKUP_ROOT"))
    lk_console_log "Pruning backups at $BACKUP_ROOT on $FQDN (storage used: ${USAGE_START[0]}/${USAGE_START[1]})"
    lk_mapfile SOURCE_NAMES <(find "$BACKUP_ROOT/snapshot" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | sort)
    for SOURCE_NAME in ${SOURCE_NAMES[@]+"${SOURCE_NAMES[@]}"}; do
        lk_console_message "Checking '$SOURCE_NAME' snapshots"
        SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME

        find_snapshots SNAPSHOTS_CLEAN \
            -exec test -e '{}/.finished' \; \
            ! -exec test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_CLEAN_COUNT" -gt 0 ] ||
            lk_console_warning -r "Skipping $SOURCE_NAME (no clean snapshots)" ||
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

        if [ -n "$PRUNE_FAILED_AFTER_DAYS" ]; then
            PRUNE_FAILED_BEFORE_DATE=$(date \
                -d "$LATEST_CLEAN $PRUNE_FAILED_AFTER_DAYS days ago" +"%F")
            # Add a strict -regex test to keep failed snapshots with
            # non-standard names
            find_snapshots SNAPSHOTS_FAILED \
                -exec test ! -e '{}/.finished' \; \
                -regex ".*/$BACKUP_TIMESTAMP_FINDUTILS_REGEX" \
                -exec sh -c 'test "${1##*/}" \< "$2"' sh \
                '{}' "$PRUNE_FAILED_BEFORE_DATE" \;
            [ "$SNAPSHOTS_FAILED_COUNT" -eq 0 ] ||
                lk_console_detail "Failed >$PRUNE_FAILED_AFTER_DAYS days ago:" \
                    "$SNAPSHOTS_FAILED_COUNT"
        fi

        # Keep the latest snapshot
        KEEP=(
            "${SNAPSHOTS_CLEAN[0]}"
        )

        if [ -n "$PRUNE_HOURLY_AFTER" ]; then
            # Keep one snapshot per hour for the last PRUNE_HOURLY_AFTER hours
            LATEST_CLEAN_HOUR=$(snapshot_hour "${SNAPSHOTS_CLEAN[0]}")
            HOUR=$LATEST_CLEAN_HOUR
            for i in $(seq 0 "$PRUNE_HOURLY_AFTER"); do
                [ "$i" -eq 0 ] ||
                    HOUR=$(date -d "$LATEST_CLEAN_HOUR $i hours ago" +"%F %T")
                SNAPSHOT=$(first_snapshot_in_hour "$HOUR") || continue
                KEEP[${#KEEP[@]}]=$SNAPSHOT
            done
        fi

        # Keep one snapshot per day for the last PRUNE_DAILY_AFTER days
        DAY=$LATEST_CLEAN
        for i in $(seq 0 "$PRUNE_DAILY_AFTER"); do
            [ "$i" -eq 0 ] || DAY=$(date -d "$LATEST_CLEAN $i days ago" +"%F")
            SNAPSHOT=$(first_snapshot_on_date "$DAY") || continue
            KEEP[${#KEEP[@]}]=$SNAPSHOT
        done

        # Keep one snapshot per week for the last PRUNE_WEEKLY_AFTER weeks
        # (indefinitely if PRUNE_WEEKLY_AFTER is the empty string)
        SUNDAY=$(date -d "$(date -d "$LATEST_CLEAN" +"%F %u days ago")" +"%F")
        WEEKS=0
        while { [ "$OLDEST_CLEAN" \< "$SUNDAY" ] ||
            [ "$OLDEST_CLEAN" = "$SUNDAY" ]; } &&
            { [ -z "$PRUNE_WEEKLY_AFTER" ] ||
                [ $((WEEKS++)) -le "$PRUNE_WEEKLY_AFTER" ]; }; do
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
        for SNAPSHOT in "${SNAPSHOTS_CLEAN[@]}"; do
            [[ "$SNAPSHOT" =~ ^$BACKUP_TIMESTAMP_FINDUTILS_REGEX$ ]] ||
                KEEP[${#KEEP[@]}]="$SNAPSHOT"
        done

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
    eval "exec $LOCK_FD>&-"
    rm -f "$LOCK_FILE"
    USAGE_END=($(get_usage "$BACKUP_ROOT"))
    lk_console_success \
        "Pruning complete (storage used: ${USAGE_END[0]}/${USAGE_END[1]})"
    exit
}

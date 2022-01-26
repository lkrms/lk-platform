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
lk_require backup

function find_snapshots() {
    lk_backup_snapshot_list "$1" "$SNAPSHOT_ROOT" "${@:2}"
}

function snapshot_date() {
    lk_backup_snapshot_date "$1"
}

function snapshot_hour() {
    lk_backup_snapshot_hour "$1"
}

function first_snapshot_on_date() {
    lk_echo_array SNAPSHOTS_CLEAN |
        grep "^$1" |
        tail -n1
}

function first_snapshot_in_hour() {
    lk_echo_array SNAPSHOTS_CLEAN |
        grep "^${1:0:10}-${1:11:2}" |
        tail -n1
}

function prune_snapshot() {
    local PRUNE=$SNAPSHOT_ROOT/$1
    lk_tty_print \
        "Pruning (${2:-expired}):" "${PRUNE#"$BACKUP_ROOT/snapshot/"}"
    lk_maybe -p touch "$PRUNE/.pruning" &&
        lk_maybe -p rm -Rf "$PRUNE"
}

function get_usage() {
    gnu_df --sync --output=used,pcent --block-size=M "$@" | sed '1d'
}

function print_max_age() {
    case "$1" in
    "")
        lk_tty_detail "$2 snapshots" \
            "do not expire"
        ;;
    0)
        lk_tty_detail "$2 snapshots" \
            "expire immediately"
        ;;
    *)
        lk_tty_detail "$2 snapshots" \
            "expire after $1 $(lk_plural "$1" "$3" "$4")"
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

LK_USAGE="\
Usage: ${0##*/} [OPTIONS] BACKUP_ROOT

Delete expired snapshots at BACKUP_ROOT.

Options:
  -n, --dry-run     perform a trial run without making any changes"

lk_getopt "n" \
    "dry-run"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -n | --dry-run)
        LK_DRY_RUN=1
        ;;
    --)
        break
        ;;
    esac
done

[ $# -ge 1 ] || lk_usage

BACKUP_ROOT=$1

[ -d "$BACKUP_ROOT" ] || lk_die "directory not found: $BACKUP_ROOT"
[ -d "$BACKUP_ROOT/snapshot" ] || {
    lk_tty_log "Nothing to prune"
    exit
}

BACKUP_ROOT=$(realpath "$BACKUP_ROOT")
LOCK_NAME=${0##*/}-${BACKUP_ROOT//\//_}
lk_lock LOCK_FILE LOCK_FD "$LOCK_NAME"

export TZ=UTC
HN=$(lk_hostname) || HN=localhost
FQDN=$(lk_fqdn) || FQDN=$HN.localdomain
eval "$(lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX)"

lk_log_start

{
    USAGE_START=($(get_usage "$BACKUP_ROOT"))
    lk_tty_log "Pruning backups at $BACKUP_ROOT on $FQDN (storage used: ${USAGE_START[0]}/${USAGE_START[1]})"
    lk_tty_print "Settings:"
    print_max_age "$HOURLY_MAX_AGE" Hourly hour hours
    print_max_age "$DAILY_MAX_AGE" Daily day days
    print_max_age "$WEEKLY_MAX_AGE" Weekly week weeks
    print_max_age "$FAILED_MAX_AGE" Failed day days
    lk_mapfile SOURCE_NAMES <(find "$BACKUP_ROOT/snapshot" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n' | sort)
    for SOURCE_NAME in ${SOURCE_NAMES[@]+"${SOURCE_NAMES[@]}"}; do
        lk_tty_print "Checking '$SOURCE_NAME' snapshots"
        SNAPSHOT_ROOT=$BACKUP_ROOT/snapshot/$SOURCE_NAME

        find_snapshots SNAPSHOTS_CLEAN \
            -execdir test -e '{}/.finished' \; \
            ! -execdir test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_CLEAN_COUNT" -gt 0 ] ||
            lk_tty_warning -r "Skipping $SOURCE_NAME (no clean snapshots)" ||
            continue
        LATEST_CLEAN=$(snapshot_date "${SNAPSHOTS_CLEAN[0]}")
        OLDEST_CLEAN=$(snapshot_date \
            "${SNAPSHOTS_CLEAN[$((SNAPSHOTS_CLEAN_COUNT - 1))]}")
        lk_tty_detail "Clean:" \
            "$SNAPSHOTS_CLEAN_COUNT ($([ "$LATEST_CLEAN" = "$OLDEST_CLEAN" ] ||
                echo "$OLDEST_CLEAN to ")$LATEST_CLEAN)"

        find_snapshots SNAPSHOTS_PRUNING -execdir test -e '{}/.pruning' \;
        [ "$SNAPSHOTS_PRUNING_COUNT" -eq 0 ] ||
            lk_tty_detail \
                "Partially pruned:" "$SNAPSHOTS_PRUNING_COUNT"

        if [ -n "$FAILED_MAX_AGE" ]; then
            PRUNE_FAILED_BEFORE_DATE=$(date \
                -d "$LATEST_CLEAN $FAILED_MAX_AGE days ago" +"%F")
            # Add a strict -regex test to keep failed snapshots with
            # non-standard names
            find_snapshots SNAPSHOTS_FAILED \
                -execdir test ! -e '{}/.finished' \; \
                -regex ".*/$BACKUP_TIMESTAMP_FINDUTILS_REGEX" \
                -execdir sh -c 'test "${1##*/}" \< "$2"' sh \
                '{}' "$PRUNE_FAILED_BEFORE_DATE" \;
            [ "$SNAPSHOTS_FAILED_COUNT" -eq 0 ] ||
                lk_tty_detail "Failed >$FAILED_MAX_AGE days ago:" \
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
        for SNAPSHOT in "${SNAPSHOTS_CLEAN[@]}"; do
            [[ $SNAPSHOT =~ ^$BACKUP_TIMESTAMP_FINDUTILS_REGEX$ ]] ||
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

        lk_tty_detail \
            "Expired:" "$SNAPSHOTS_PRUNE_COUNT"
        lk_tty_detail \
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
    USAGE_END=($(get_usage "$BACKUP_ROOT"))
    lk_tty_success \
        "Pruning complete (storage used: ${USAGE_END[0]}/${USAGE_END[1]})"
    exit
}

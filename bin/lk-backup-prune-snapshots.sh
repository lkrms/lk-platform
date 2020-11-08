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
}

function prune_snapshot() {
    local PRUNE=$SNAPSHOT_ROOT/$1
    lk_console_warning "Pruning ${PRUNE#$BACKUP_ROOT/snapshot/}"
    touch "$PRUNE/.pruning" &&
        rm -Rf "$PRUNE"
}

function get_usage() {
    gnu_df --sync --output=used,pcent --block-size=M "$@" | sed '1d'
}

PRUNE_DAILY_AFTER_DAYS=${LK_SNAPSHOT_PRUNE_DAILY_AFTER_DAYS:-7}
PRUNE_FAILED_AFTER_DAYS=${LK_SNAPSHOT_PRUNE_FAILED_AFTER_DAYS-28}
PRUNE_WEEKLY_AFTER_WEEKS=${LK_SNAPSHOT_PRUNE_WEEKLY_AFTER_WEEKS-52}

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
exec 9>"$LOCK_FILE" &&
    flock -n 9 || lk_die "unable to acquire a lock on $LOCK_FILE"

HN=$(lk_hostname) || HN=localhost
FQDN=$(lk_fqdn) || FQDN=$HN.localdomain
eval "$(LK_VAR_PREFIX='' lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX)"

lk_log_output

{
    TZ=UTC
    lk_console_log "Pruning backups at $BACKUP_ROOT on $FQDN"
    USAGE_START=($(get_usage "$BACKUP_ROOT"))
    lk_console_detail "Storage used on backup volume:" \
        "${USAGE_START[0]} (${USAGE_START[1]})"
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
                    "Removing $SNAPSHOTS_PRUNING_COUNT partially pruned $(
                        lk_maybe_plural \
                            "$SNAPSHOTS_PRUNING_COUNT" snapshot snapshots
                    ):"
            for SNAPSHOT in "${SNAPSHOTS_PRUNING[@]}"; do
                prune_snapshot "$SNAPSHOT" || lk_die
            done
        }

        if [ -n "$PRUNE_FAILED_AFTER_DAYS" ]; then
            PRUNE_FAILED_BEFORE_DATE=$(date \
                -d "$LATEST_CLEAN -$PRUNE_FAILED_AFTER_DAYS day" +"%F")
            ! lk_verbose ||
                lk_console_detail "Checking for failed snapshots before" \
                    "$PRUNE_FAILED_BEFORE_DATE"
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
                        "Removing $SNAPSHOTS_FAILED_COUNT failed $(
                            lk_maybe_plural \
                                "$SNAPSHOTS_FAILED_COUNT" snapshot snapshots
                        ):"
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
        for SNAPSHOT in "${SNAPSHOTS_CLEAN[@]}"; do
            [[ "$SNAPSHOT" =~ ^$BACKUP_TIMESTAMP_FINDUTILS_REGEX$ ]] ||
                KEEP[${#KEEP[@]}]="$SNAPSHOT"
        done

        lk_mapfile <(
            lk_echo_array KEEP | sort -ru
        ) SNAPSHOTS_KEEP
        SNAPSHOTS_KEEP_COUNT=${#SNAPSHOTS_KEEP[@]}
        ! lk_verbose ||
            lk_echo_array SNAPSHOTS_KEEP |
            lk_console_detail_list \
                "Keeping $SNAPSHOTS_KEEP_COUNT $(lk_maybe_plural \
                    "$SNAPSHOTS_KEEP_COUNT" snapshot snapshots):" "$LK_GREEN"

        lk_mapfile <(comm -23 \
            <(lk_echo_array SNAPSHOTS_CLEAN | sort) \
            <(lk_echo_array SNAPSHOTS_KEEP | sort)) \
            SNAPSHOTS_PRUNE
        SNAPSHOTS_PRUNE_COUNT=${#SNAPSHOTS_PRUNE[@]}
        [ "$SNAPSHOTS_PRUNE_COUNT" -eq 0 ] || {
            lk_echo_array SNAPSHOTS_PRUNE | tac |
                lk_console_detail_list \
                    "Removing $SNAPSHOTS_PRUNE_COUNT expired $(lk_maybe_plural \
                        "$SNAPSHOTS_PRUNE_COUNT" snapshot snapshots):"
            for SNAPSHOT in "${SNAPSHOTS_PRUNE[@]}"; do
                prune_snapshot "$SNAPSHOT" || lk_die
            done
        }
    done
    exec 9>&-
    rm -f "$LOCK_FILE"
    lk_console_success "Pruning complete"
    USAGE_END=($(get_usage "$BACKUP_ROOT"))
    lk_console_detail "Storage used on backup volume:" \
        "${USAGE_END[0]} (${USAGE_END[1]})"
    exit
}

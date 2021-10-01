#!/bin/bash

# lk_backup_snapshot_list ARRAY SNAPSHOT_ROOT [FIND_ARG...]
function lk_backup_snapshot_list() {
    [ $# -ge 2 ] && lk_is_identifier "$1" && [ -d "$2" ] || lk_usage "\
Usage: $FUNCNAME ARRAY SNAPSHOT_ROOT [FIND_ARG...]" || return
    eval "$(lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX)"
    lk_mapfile "$1" <(
        find "$2" \
            -mindepth 1 -maxdepth 1 -type d \
            -regex ".*/${BACKUP_TIMESTAMP_FINDUTILS_REGEX}[^/]*" \
            "${@:3}" \
            -printf '%f\n' | sort -r
    )
    eval "$1_COUNT=\${#$1[@]}"
}

# lk_backup_snapshot_list_clean ARRAY SNAPSHOT_ROOT
function lk_backup_snapshot_list_clean() {
    lk_backup_snapshot_list "$1" "$2" \
        -execdir test -e '{}/.finished' \; \
        ! -execdir test -e '{}/.pruning' \;
}

# lk_backup_snapshot_latest SNAPSHOT_ROOT
function lk_backup_snapshot_latest() {
    local SNAPSHOTS
    lk_backup_snapshot_list_clean SNAPSHOTS "$1" &&
        [ ${#SNAPSHOTS[@]} -gt 0 ] &&
        echo "${SNAPSHOTS[0]}"
}

function lk_backup_snapshot_date() {
    echo "${1:0:10}"
}

function lk_backup_snapshot_hour() {
    echo "${1:0:10} ${1:11:2}:00:00"
}

lk_provide backup

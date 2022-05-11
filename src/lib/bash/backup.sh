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

# lk_backup_snapshot_to_archive SNAPSHOT_PATH
function lk_backup_snapshot_to_archive() { (
    shopt -s dotglob nullglob &&
        SNAPSHOT=$(cd "$1" && pwd -P) || return
    eval "$(lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX)"
    [[ $SNAPSHOT =~ (.*)/snapshot/([^/]+)/(${BACKUP_TIMESTAMP_FINDUTILS_REGEX})[^/]*$ ]] ||
        lk_warn "not a snapshot: $1" || return
    SOURCE=${BASH_REMATCH[2]}
    ARCHIVE_ROOT=${BASH_REMATCH[1]}/archive/$SOURCE
    TIMESTAMP=${BASH_REMATCH[3]}
    [ -e "$SNAPSHOT/.finished" ] || lk_warn "snapshot is pending" || return
    [ -e "$ARCHIVE_ROOT" ] ||
        { ADM=$(lk_file_group "${SNAPSHOT%/*/*}") &&
            GROUP=$(lk_file_group "${SNAPSHOT%/*}") &&
            lk_elevate install -d -m 00751 -g "$ADM" "${ARCHIVE_ROOT%/*}" &&
            lk_elevate install -d -m 02770 -g "$GROUP" "$ARCHIVE_ROOT"; } ||
        return
    XZ=$ARCHIVE_ROOT/$SOURCE-$TIMESTAMP.tar.xz
    DB=("$SNAPSHOT/db"/*)
    DB_NEW=(${DB+"${DB[@]/$SNAPSHOT\/db/$ARCHIVE_ROOT}"})
    FILES=("$XZ" ${DB_NEW+"${DB_NEW[@]}"})
    lk_remove_missing FILES
    IFS=$'\n'
    [ ${#FILES[@]} -eq 0 ] ||
        lk_warn "files already exist:$IFS${FILES[*]}" || return
    unset IFS
    cd "$SNAPSHOT/fs" &&
        BYTES=$(gnu_du -bs . | awk '{print $1}') &&
        SIZE=$(gnu_du -hsc . ${DB+"../db"} | awk 'END {print $1}') || return
    lk_tty_print "Creating backup archive"
    lk_tty_detail "From snapshot:" "$SNAPSHOT"
    lk_tty_detail "To directory:" "$ARCHIVE_ROOT"
    lk_tty_detail "Uncompressed size:" "$SIZE"
    lk_confirm "Proceed?" Y || return
    lk_tty_print "Compressing files to" "$XZ"
    [ ${#DB[@]} -eq 0 ] || lk_tty_detail \
        "Database $(lk_plural ${#DB[@]} backup) will be copied separately"
    nice -n 10 tar -c -- * |
        lk_pv -s "$BYTES" |
        nice -n 10 xz -cT1 >"$XZ.pending" &&
        touch -r "$SNAPSHOT/.finished" "$XZ.pending" &&
        mv -n "$XZ"{.pending,} || return
    lk_tty_success "Files compressed successfully"
    [ ${#DB[@]} -eq 0 ] || {
        lk_tty_list DB_NEW "Copying database $(lk_plural ${#DB[@]} backup) to:"
        cp -an "${DB[@]}" "$ARCHIVE_ROOT/" || return
    }
    SIZE=$(gnu_du -hsc "$XZ" ${DB_NEW+"${DB_NEW[@]}"} | awk 'END{print $1}') &&
        lk_tty_success "Archive created successfully" &&
        lk_tty_detail "Compressed size:" "$SIZE"
); }

lk_provide backup

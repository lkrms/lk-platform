#!/bin/bash

function _lk_dirty_check() {
    local DIR=$LK_BASE/var/run/dirty
    [ -d "$DIR" ] && [ -w "$DIR" ] ||
        lk_warn "not a writable directory: $DIR"
}

function _lk_dirty_check_scope() {
    FILE=$LK_BASE/var/run/dirty/$1
    [[ ${1-} =~ ^[^/]+$ ]] ||
        lk_warn "invalid scope: ${1-}"
}

function lk_is_dirty() {
    local FILE
    while [ $# -gt 0 ]; do
        _lk_dirty_check_scope "$1" || return
        shift
        [ -f "$FILE" ] || continue
        return
    done
    false
}

function lk_mark_dirty() {
    _lk_dirty_check || return
    local FILE
    while [ $# -gt 0 ]; do
        _lk_dirty_check_scope "$1" &&
            touch "$FILE" ||
            lk_warn "unable to mark dirty: $1" || return
        shift
    done
}

function lk_mark_clean() {
    _lk_dirty_check || return
    local FILE
    while [ $# -gt 0 ]; do
        _lk_dirty_check_scope "$1" &&
            rm -f "$FILE" ||
            lk_warn "unable to mark clean: $1" || return
        shift
    done
}

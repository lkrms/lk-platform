#!/usr/bin/env bash

function _lk_dirty_check() {
    local DIR=$LK_BASE/var/lib/lk-platform/dirty
    [[ -d $DIR ]] && [[ -w $DIR ]] ||
        lk_warn "not a writable directory: $DIR"
}

function _lk_dirty_check_scope() {
    [[ $1 =~ ^[^/]+$ ]] ||
        lk_warn "invalid scope: $1" || return
    FILE=$LK_BASE/var/lib/lk-platform/dirty/$1
}

# lk_is_dirty SCOPE...
#
# Return true if any SCOPE has been marked dirty.
function lk_is_dirty() {
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" || return
        shift
        [[ -f $FILE ]] || continue
        return
    done
    false
}

# lk_mark_dirty SCOPE...
#
# Mark each SCOPE as dirty.
function lk_mark_dirty() {
    _lk_dirty_check || return
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" &&
            ({ [[ ! -g ${FILE%/*} ]] || umask 002; } && touch "$FILE") ||
            lk_warn "unable to mark dirty: $1" || return
        shift
    done
}

# lk_mark_clean SCOPE...
#
# Mark each SCOPE as clean.
function lk_mark_clean() {
    _lk_dirty_check || return
    local FILE
    while (($#)); do
        _lk_dirty_check_scope "$1" &&
            rm -f "$FILE" ||
            lk_warn "unable to mark clean: $1" || return
        shift
    done
}

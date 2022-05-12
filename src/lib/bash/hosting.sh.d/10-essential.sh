#!/bin/bash

function _lk_hosting_is_quiet() {
    [ -n "${_LK_HOSTING_QUIET-}" ]
}

function _lk_hosting_check() {
    lk_is_ubuntu &&
        lk_dirs_exist /srv/{www/.tmp,backup/{archive,latest,snapshot}} ||
        lk_warn "system not configured for hosting"
}

function lk_hosting_flush_cache() {
    lk_cache_mark_dirty
}

#!/bin/bash

function _lk_hosting_check() {
    lk_is_ubuntu &&
        lk_dirs_exist /srv/www{,/.tmp,/.opcache} ||
        lk_warn "system not configured for hosting"
}

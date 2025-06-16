#!/usr/bin/env bash

function _lk_hosting_httpd_test_config() {
    lk_tty_detail "Testing Apache configuration"
    lk_elevate apachectl configtest ||
        lk_warn "invalid configuration"
}

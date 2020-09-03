#!/bin/bash

function lk_dpkg_installed() {
    local STATUS
    STATUS=$(dpkg-query \
        --show --showformat '${db:Status-Status}' "$1" 2>/dev/null) &&
        [ "$STATUS" = installed ]
}

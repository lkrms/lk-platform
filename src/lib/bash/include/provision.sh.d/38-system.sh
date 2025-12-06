#!/usr/bin/env bash

function lk_system_list_networks() {
    local AWK
    lk_awk_load AWK sh-system-list-networks || return
    if lk_has ip; then
        ip addr
    else
        ifconfig
    fi | awk -f "$AWK" | lk_uniq
}

function lk_system_list_network_ips() {
    lk_system_list_networks | sed -E 's/\/.*//' | lk_uniq
}

function lk_system_list_public_network_ips() {
    lk_system_list_network_ips | sed -E '
/^(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168|127)\./d
/^(f[cd]|fe80::|::1$)/d'
}

function lk_system_get_public_ips() { (
    PIDS=()
    for SERVER in 1.1.1.1 2606:4700:4700::1111; do
        { ! ADDR=$(dig +noall +answer +short "@$SERVER" \
            whoami.cloudflare TXT CH | tr -d '"') || echo "$ADDR"; } &
        PIDS[${#PIDS[@]}]=$!
    done
    STATUS=0
    for PID in "${PIDS[@]}"; do
        wait "$PID" || STATUS=$?
    done
    ((!STATUS)) &&
        lk_system_list_public_network_ips
) | lk_uniq; }

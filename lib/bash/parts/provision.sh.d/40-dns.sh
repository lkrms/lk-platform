#!/bin/bash

# lk_dns_resolve_hosts HOST...
function lk_dns_resolve_hosts() { {
    local HOSTS=()
    while [ $# -gt 0 ]; do
        if lk_is_cidr; then
            echo "$1"
        elif lk_is_fqdn "$1"; then
            HOSTS[${#HOSTS[@]}]=$1
        elif [[ $1 == *\|* ]]; then
            lk_curl "${1%%|*}" | jq -r "${1#*|}" || return
        fi
        shift
    done
    [ -z "${HOSTS+1}" ] ||
        lk_hosts_get_records +VALUE A,AAAA "${HOSTS[@]}"
} | sort -nu; }

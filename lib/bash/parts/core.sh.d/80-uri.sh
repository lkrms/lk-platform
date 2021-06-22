#!/bin/bash

# lk_uri_encode PARAMETER=VALUE...
function lk_uri_encode() {
    local ARGS=()
    while [ $# -gt 0 ]; do
        [[ $1 =~ ^([^=]+)=(.*) ]] || lk_warn "invalid parameter: $1" || return
        ARGS+=(--arg "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
        shift
    done
    [ ${#ARGS[@]} -eq 0 ] ||
        jq -rn "${ARGS[@]}" \
            '[$ARGS.named|to_entries[]|"\(.key)=\(.value|@uri)"]|join("&")'
}

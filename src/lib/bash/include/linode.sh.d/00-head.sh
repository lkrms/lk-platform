#!/usr/bin/env bash

lk_require git provision

function linode-cli() {
    local LINODE_USER=${LINODE_USER-${LK_LINODE_USER-}}
    (IFS=, && [[ ,$*, == *,--as-user,* ]]) ||
        [[ -z $LINODE_USER ]] ||
        set -- --as-user "$LINODE_USER" "$@"
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function _lk_linode_cli_json {
    local PAGE=1 JSON COUNT
    while :; do
        lk_mktemp_with -r JSON \
            linode-cli --json --page "$PAGE" "$@" &&
            COUNT=$(jq -r 'length' "$JSON") &&
            jq '.[]' "$JSON" || return
        ((PAGE++))
        ((COUNT == 100)) || break
    done | jq --slurp
}

function linode-cli-json {
    lk_cache -t 1200 _lk_linode_cli_json "$@"
}

function lk_linode_flush_cache() {
    lk_cache_flush
}

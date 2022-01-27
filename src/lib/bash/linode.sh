#!/bin/bash

lk_require git
lk_require provision

function linode-cli() {
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function _lk_linode_cli_json {
    local JSON PAGE=0 COUNT
    while :; do
        ((++PAGE))
        lk_mktemp_with -r JSON linode-cli --json --page "$PAGE" "$@" &&
            COUNT=$(jq -r 'length' "$JSON") &&
            jq '.[]' "$JSON" || return
        ((COUNT == 100)) || break
    done | jq --slurp
}

function linode-cli-json {
    lk_cache _lk_linode_cli_json "$@"
}

function lk_linode_flush_cache() {
    lk_cache_mark_dirty
}

function _lk_linode_filter() {
    local REGEX=${LK_LINODE_SKIP_REGEX-'^jump\b'}
    if [ -n "$REGEX" ]; then
        jq --arg re "$REGEX" '[ .[] | select(.label | test($re) | not) ]'
    else
        cat
    fi
}

lk_linode_linodes() { linode-cli-json linodes list "$@"; }
lk_linode_ips() { linode-cli-json networking ips-list "$@"; }
lk_linode_domains() { linode-cli-json domains list "$@"; }
lk_linode_domain_records() { linode-cli-json domains records-list "$@"; }
lk_linode_firewalls() { linode-cli-json firewalls list "$@"; }
lk_linode_firewall_devices() { linode-cli-json firewalls devices-list "$@"; }
lk_linode_stackscripts() { linode-cli-json stackscripts list --is_public false "$@"; }

function lk_linode_get_shell_var() {
    lk_json_sh \
        LINODE_ID .id \
        LINODE_LABEL .label \
        LINODE_TAGS .tags \
        LINODE_TYPE .type \
        LINODE_DISK .specs.disk \
        LINODE_VPCUS .specs.vcpus \
        LINODE_MEMORY .specs.memory \
        LINODE_IMAGE .image \
        LINODE_IPV4_PUBLIC '[.ipv4[]|select(test(regex.ipv4PrivateFilter)|not)]|first' \
        LINODE_IPV4_PRIVATE '[.ipv4[]|select(test(regex.ipv4PrivateFilter))]|first' \
        LINODE_IPV6 '.ipv6|split("/")[0]'
}

#### INCLUDE linode.sh.d

lk_provide linode

#### Reviewed: 2022-01-22

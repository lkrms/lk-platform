#!/bin/bash

function lk_linode_filter_linodes() {
    local REGEX=${LK_LINODE_IGNORE_REGEX-}
    if [[ -n $REGEX ]]; then
        jq --arg re "$REGEX" '[ .[] | select(.label | test($re) | not) ]'
    else
        cat
    fi
}

function lk_linode_linode_sh() {
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

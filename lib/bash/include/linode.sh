#!/bin/bash

function linode-cli() {
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function lk_linode_flush_cache() {
    unset "${!LK_LINODE_@}"
}

function _lk_linode_define() {
    local _CACHE_VAR
    _CACHE_VAR=$(lk_upper "$1")
    eval "function $1() {
        $_CACHE_VAR=\${$_CACHE_VAR:-\$(linode-cli --json ${*:2})} &&
            echo \"\$$_CACHE_VAR\"
    }"
}

_lk_linode_define lk_linode_linodes linodes list

# lk_linode_ssh_add
#
# Add an SSH host for each Linode object in the JSON input array.
function lk_linode_ssh_add() {
    local LINODES LINODE SH LINODE_ID LABEL IPV4 IPV4_PUBLIC IPV4_PRIVATE \
        LK_SSH_PRIORITY=${LK_SSH_PRIORITY-45}
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_jq_get_shell_var <<<"$LINODE" \
            LINODE_ID .id \
            LABEL .label) &&
            eval "$SH" &&
            IPV4=$(jq -r ".ipv4[]" <<<"$LINODE") || return
        IPV4_PUBLIC=$(sed <<<"$IPV4" -E \
            '/^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)/d')
        IPV4_PRIVATE=$(sed <<<"$IPV4" -E \
            '/^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)/!d')
        lk_console_item "Adding SSH host:" "$LABEL (#$LINODE_ID)"
        lk_console_detail "Public IPv4 address:" "${IPV4_PUBLIC:-<none>}"
        lk_console_detail "Private IPv4 address:" "${IPV4_PRIVATE:-<none>}"
        [ -z "$IPV4_PUBLIC" ] || lk_ssh_add_host "${LABEL%%.*}" \
            "$IPV4_PUBLIC" "" || return
        [ -z "$IPV4_PRIVATE" ] || lk_ssh_add_host "${LABEL%%.*}-private" \
            "$IPV4_PRIVATE" "" "" "jump" || return
    done
}

function lk_linode_ssh_add_all() {
    local JSON LABELS
    JSON=$(lk_linode_linodes) || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON"
    [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS |
        lk_console_list "Adding to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    lk_linode_ssh_add <<<"$JSON"
}

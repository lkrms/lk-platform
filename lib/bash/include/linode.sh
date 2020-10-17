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
_lk_linode_define lk_linode_stackscripts stackscripts list --is_public false

function lk_linode_get_shell_var() {
    eval "$(lk_get_regex IPV4_PRIVATE_FILTER_REGEX)"
    # shellcheck disable=SC2016
    lk_jq_get_shell_var \
        --arg ipv4Private "$IPV4_PRIVATE_FILTER_REGEX" \
        LINODE_ID .id \
        LINODE_LABEL .label \
        LINODE_TYPE .type \
        LINODE_DISK .specs.disk \
        LINODE_VPCUS .specs.vcpus \
        LINODE_MEMORY .specs.memory \
        LINODE_IMAGE .image \
        LINODE_IPV4_PUBLIC 'first(.ipv4[]|select(test($ipv4Private)==false))' \
        LINODE_IPV4_PRIVATE 'first(.ipv4[]|select(test($ipv4Private)))' \
        LINODE_IPV6 '.ipv6|split("/")[0]'
}

# lk_linode_ssh_add
#
# Add an SSH host for each Linode object in the JSON input array.
function lk_linode_ssh_add() {
    local LINODES LINODE SH LK_SSH_PRIORITY=${LK_SSH_PRIORITY-45}
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH"
        LABEL=${LINODE_LABEL%%.*}
        lk_console_item "Adding SSH host:" \
            "${LK_SSH_PREFIX-$LK_PATH_PREFIX}$LABEL (Linode $LINODE_ID)"
        lk_console_detail "Public IP address:" "${LINODE_IPV4_PUBLIC:-<none>}"
        lk_console_detail "Private IP address:" "${LINODE_IPV4_PRIVATE:-<none>}"
        [ -z "$LINODE_IPV4_PUBLIC" ] || lk_ssh_add_host "$LABEL" \
            "$LINODE_IPV4_PUBLIC" "" || return
        [ -z "$LINODE_IPV4_PRIVATE" ] || lk_ssh_add_host "$LABEL-private" \
            "$LINODE_IPV4_PRIVATE" "" "" "${LK_SSH_JUMP_HOST:+jump}" || return
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

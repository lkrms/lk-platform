#!/bin/bash

function linode-cli() {
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function lk_linode_flush_cache() {
    local _DIR=${TMPDIR:-/tmp}
    _DIR=${_DIR%/}/_lk_linode_cache_$UID
    [ ! -e "$_DIR" ] ||
        rm -Rf "$_DIR"
    [ "$BASH_SUBSHELL" -eq 0 ] ||
        lk_warn "cannot flush cache in subshell" || exit
    unset "${!LK_LINODE_@}"
}

function _lk_linode_maybe_flush_cache() {
    [ -z "${_LK_LINODE_CACHE_DIRTY:-}" ] ||
        lk_linode_flush_cache
}

function _lk_linode_cache() {
    local _CACHE_VAR=$1 _DIR=${TMPDIR:-/tmp} _FILE
    _DIR=${_DIR%/}/_lk_linode_cache_$UID
    _FILE=$_DIR/$1
    if [ -e "$_FILE" ]; then
        cat "$_FILE"
    else
        [ -e "$_DIR" ] ||
            install -d -m 00700 "$_DIR" || return
        "${@:2}" | tee "$_DIR/$1"
    fi
}

function _lk_linode_define() {
    local _CACHE_VAR
    _CACHE_VAR=$(lk_upper "$1")
    eval "function $1() {
    _lk_linode_maybe_flush_cache
    $_CACHE_VAR=\${$_CACHE_VAR:-\$(_lk_linode_cache $_CACHE_VAR linode-cli --json ${*:2} \"\$@\")} &&
        echo \"\$$_CACHE_VAR\" ||
        echo \"\$$_CACHE_VAR\" >&2
}"
}

function _lk_linode_define_indexed() {
    local _CACHE_VAR
    _CACHE_VAR=$(lk_upper "$1")
    eval "function $1() {
    local _LK_VAR
    [ \$# -ge 1 ] && [[ \$1 =~ ^[0-9]+$ ]] || lk_warn \"invalid arguments\" || return
    _lk_linode_maybe_flush_cache
    _LK_VAR=${_CACHE_VAR}_\$1
    eval \"\$_LK_VAR=\\\${\$_LK_VAR:-\\\$(_lk_linode_cache \$_LK_VAR linode-cli --json ${*:2} \\\"\\\$@\\\")}\" &&
        echo \"\${!_LK_VAR}\" ||
        echo \"\${!_LK_VAR}\" >&2
}"
}

_lk_linode_define lk_linode_linodes linodes list
_lk_linode_define lk_linode_ips networking ips-list
_lk_linode_define lk_linode_domains domains list
_lk_linode_define_indexed lk_linode_domain_records domains records-list
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
        [ "${LINODE_IPV4_PRIVATE:+1}${LK_SSH_JUMP_HOST:+1}" != 11 ] ||
            lk_ssh_add_host "$LABEL-private" \
                "$LINODE_IPV4_PRIVATE" "" "" "jump" || return
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

function lk_linode_get_only_domain() {
    local DOMAIN_ID
    DOMAIN_ID=$(lk_linode_domains | jq -r '.[].id') || return
    [ -n "$DOMAIN_ID" ] && [ "$(wc -l <<<"$DOMAIN_ID")" -eq 1 ] ||
        lk_warn "domain count must be 1" || return
    echo "$DOMAIN_ID"
}

function lk_linode_dns_check() {
    local LINODES DOMAIN_ID DOMAIN RECORDS REVERSE_RECORDS \
        NEW_RECORDS NEW_REVERSE_RECORDS LINODE SH LABEL \
        OUTPUT RECORD_ID
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    DOMAIN_ID=${1:-$(lk_linode_get_only_domain)} &&
        DOMAIN=$(lk_linode_domains |
            jq -r --arg domainId "$DOMAIN_ID" \
                '.[]|select(.id==($domainId|tonumber)).domain') &&
        [ -n "$DOMAIN" ] || lk_warn "unable to retrieve domain" || return
    RECORDS=$(lk_linode_domain_records "$DOMAIN_ID" |
        jq -r '.[]|"\(.name)\t\(.type)\t\(.target)"') &&
        REVERSE_RECORDS=$(lk_linode_ips |
            jq -r '.[]|select(.rdns!=null)|"\(.address)\t\(.rdns)"' |
            sed 's/\.$//') || return
    eval "$(lk_get_regex DOMAIN_PART_REGEX)"
    NEW_RECORDS=()
    NEW_REVERSE_RECORDS=()
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH" || return
        LABEL=${LINODE_LABEL%%.*}
        [[ $LABEL =~ ^$DOMAIN_PART_REGEX$ ]] ||
            lk_warn "invalid label: $LINODE_LABEL" || continue
        NEW_RECORDS+=("$(printf '%s\t%s\t%s\n' \
            "$LABEL" "A" "$LINODE_IPV4_PUBLIC" \
            "$LABEL" "AAAA" "$LINODE_IPV6" \
            "$LABEL.private" "A" "$LINODE_IPV4_PRIVATE")")
        NEW_REVERSE_RECORDS+=("$(printf '%s\t%s\n' \
            "$LINODE_IPV4_PUBLIC" "$LABEL.$DOMAIN" \
            "$LINODE_IPV6" "$LABEL.$DOMAIN")")
    done
    while read -r NAME TYPE TARGET; do
        lk_console_item "Adding DNS record:" "$NAME $TYPE $TARGET"
        OUTPUT=$(linode-cli --json domains records-create \
            --type "$TYPE" \
            --name "$NAME" \
            --target "$TARGET" \
            "$DOMAIN_ID") &&
            RECORD_ID=$(jq '.[0].id' <<<"$OUTPUT") ||
            lk_warn "linode-cli failed with: $OUTPUT" || return
        _LK_LINODE_CACHE_DIRTY=1
        lk_console_detail "Record ID:" "$RECORD_ID"
    done < <(comm -23 \
        <(lk_echo_array NEW_RECORDS | sort) \
        <(sort <<<"$RECORDS"))
    while read -r ADDRESS RDNS; do
        lk_console_item "Adding RDNS record:" "$ADDRESS $RDNS"
        OUTPUT=$(linode-cli --json networking ip-update \
            --rdns "$RDNS" \
            "$ADDRESS") ||
            lk_warn "linode-cli failed with: $OUTPUT" || return
        _LK_LINODE_CACHE_DIRTY=1
        lk_console_detail "Record added"
    done < <(comm -23 \
        <(lk_echo_array NEW_REVERSE_RECORDS | sort) \
        <(sort <<<"$REVERSE_RECORDS"))
    ! lk_verbose || {
        RECORDS=$(comm -13 \
            <(lk_echo_array NEW_RECORDS | sort) \
            <(sort <<<"$RECORDS"))
        [ -z "$RECORDS" ] ||
            lk_console_warning0 "No matching Linode:" "$RECORDS"
    }
}

function lk_linode_dns_check_all() {
    local JSON LABELS
    JSON=$(lk_linode_linodes) || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON"
    [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS |
        lk_console_list "Checking DNS and RDNS records for:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    LK_VERBOSE=1 lk_linode_dns_check "$1" <<<"$JSON" || return
    lk_console_success "DNS check complete"
}

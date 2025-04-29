#!/bin/bash

# lk_linode_domain [-s] <DOMAIN_ID|DOMAIN_NAME> [LINODE_ARG...]
#
# If -s is set, assign values to DOMAIN_ID and DOMAIN in the caller's scope,
# otherwise print the JSON-encoded domain object.
function lk_linode_domain() {
    [[ ${1-} != -s ]] || {
        shift
        local SH
        SH=$(lk_linode_domain "$@" |
            _LK_STACK_DEPTH=-1 \
                lk_json_sh DOMAIN_ID .id DOMAIN .domain) && eval "$SH"
        return
    }
    [[ -n ${1-} ]] || lk_warn "invalid arguments" || return
    if [[ $1 =~ ^[1-9][0-9]*$ ]]; then
        linode-cli-json domains view "$@" | jq -e '.[]'
    else
        local IFS=$' \t\n'
        lk_linode_domains "${@:2}" |
            jq -e --arg domain "$1" '.[] | select(.domain == $domain)'
    fi || lk_warn "domain not found in Linode account: $1"
}

function _lk_linode_domain_tsv() {
    jq -r '.[] |
  [ .id, .name, .ttl_sec, .type, .priority, .weight, .port, .target ] | @tsv'
}

# lk_linode_domain_tsv <DOMAIN_ID|DOMAIN_NAME> [LINODE_ARG...]
#
# Print tab-separated values for DNS records in the given Linode domain:
# 1. id
# 2. name
# 3. ttl_sec
# 4. type
# 5. priority
# 6. weight
# 7. port
# 8. target
function lk_linode_domain_tsv() {
    local IFS=$' \t\n' DOMAIN_ID DOMAIN
    lk_linode_domain -s "$@" &&
        lk_linode_domain_records "$DOMAIN_ID" "${@:2}" |
        _lk_linode_domain_tsv
}

# lk_linode_domain_record_create DOMAIN NAME TTL TYPE PRIO WEIGHT PORT TARGET
function lk_linode_domain_record_create() {
    local IFS=$' \t\n' DOMAIN_ID DOMAIN
    lk_linode_domain -s "$1" "${@:9}" &&
        linode-cli --json domains records-create \
            --name "$2" \
            --ttl_sec "${3:-0}" \
            --type "$4" \
            --priority "${5:-0}" \
            --weight "${6:-0}" \
            --port "${7:-0}" \
            --target "$8" \
            "$DOMAIN_ID" \
            "${@:9}" |
        _lk_linode_domain_tsv
}

# lk_linode_domain_record_update DOMAIN ID NAME TTL TYPE PRIO WEIGHT PORT TARGET
function lk_linode_domain_record_update() {
    local IFS=$' \t\n' DOMAIN_ID DOMAIN
    lk_linode_domain -s "$1" "${@:10}" &&
        linode-cli --json domains records-update \
            --name "$3" \
            --ttl_sec "${4:-0}" \
            --priority "${6:-0}" \
            --weight "${7:-0}" \
            --port "${8:-0}" \
            --target "$9" \
            "$DOMAIN_ID" \
            "$2" \
            "${@:10}" |
        _lk_linode_domain_tsv
}

# lk_linode_domain_record_delete DOMAIN ID
function lk_linode_domain_record_delete() {
    local IFS=$' \t\n' DOMAIN_ID DOMAIN
    lk_linode_domain -s "$1" "${@:3}" &&
        linode-cli domains records-delete \
            "$DOMAIN_ID" \
            "$2" \
            "${@:3}"
}

# lk_linode_dump_domains [LINODE_ARG...]
#
# Print tab-separated values for DNS records in every Linode domain:
# 1. id
# 2. name
# 3. ttl_sec
# 4. type
# 5. priority
# 6. weight
# 7. port
# 8. target
# 9. domain id
# 10. domain
function lk_linode_dump_domains() {
    local TEMP DOMAIN_ID DOMAIN
    lk_mktemp_with TEMP &&
        lk_linode_domains "$@" |
        jq -r '.[] | [ .id, .domain ] | @tsv' >"$TEMP" || return
    while IFS=$'\t' read -r DOMAIN_ID DOMAIN; do
        lk_linode_domain_records "$DOMAIN_ID" "$@" |
            _lk_linode_domain_tsv |
            awk -v OFS='\t' -v domain_id="$DOMAIN_ID" -v domain="$DOMAIN" \
                '{ print $0, domain_id, domain }' || return
    done <"$TEMP"
}

#### Reviewed: 2022-05-23

# TODO: break these out into a standalone "apply DNS" utility

function _lk_linode_dns_records() {
    lk_jq -r \
        "$@" \
        --arg domain "$DOMAIN" \
        --argjson tags "$TAGS" \
        -f "$LK_BASE/lib/jq/linode_dns_records.jq" \
        <<<"$LINODES"
}

# lk_linode_dns_check [-t] [LINODES_JSON DOMAIN [LINODE_ARG...]]
#
# For each linode object in LINODES_JSON, check DOMAIN for each of the following
# DNS records, create any that are missing, and if LK_VERBOSE >= 1, report any
# unmatched records. If -t is set, create additional records for each unique
# tag.
#
# - {LABEL}             A       {IPV4_PUBLIC}
# - {LABEL}.PRIVATE     A       {IPV4_PRIVATE}
# - {LABEL}             AAAA    {IPV6}
#
function lk_linode_dns_check() {
    local USE_TAGS LINODES LINODE_COUNT TAGS="[]" DOMAIN_ID DOMAIN \
        RR RECORDS REVERSE _RECORDS _REVERSE RECORD \
        NAME TYPE TARGET JSON ADDRESS RDNS \
        NEW_RECORD_COUNT=0 NEW_REVERSE_RECORD_COUNT=0 \
        _LK_DNS_SERVER
    [ "${1-}" != -t ] || { USE_TAGS=1 && shift; }
    LINODES=${1:-$(lk_linode_linodes "${@:3}")} &&
        LINODE_COUNT=$(jq length <<<"$LINODES") ||
        return
    [ "$LINODE_COUNT" -gt 0 ] || lk_warn "no linode objects" || return
    eval "$(lk_get_regex DOMAIN_PART_REGEX IPV4_PRIVATE_FILTER_REGEX)"
    [ -z "${USE_TAGS-}" ] || TAGS=$(lk_linode_linodes "${@:3}" | lk_jq '
include "core";
"^(?<part>\(regex.domainPart)).*" as $p |
    [ .[].tags[] | select(test($p)) | sub($p; "\(.part)") ] |
    counts |
    [ .[] | select(.[1] == 1) | .[0] ]') || return
    lk_linode_domain -s "${@:2}" || return
    lk_tty_print "Retrieving domain records and Linode IP addresses"
    lk_tty_detail "Domain ID:" "$DOMAIN_ID"
    lk_tty_detail "Domain name:" "$DOMAIN"
    lk_mktemp_with RR lk_linode_domain_records "$DOMAIN_ID" "${@:3}"
    RECORDS=$(jq -r \
        '.[]|"\(.name)\t\(.type)\t\(.target)\t\(.ttl_sec)"' <"$RR") &&
        REVERSE=$(lk_linode_ips "${@:3}" | jq -r \
            '.[]|select(.rdns!=null)|"\(.address)\t\(.rdns|sub("\\.$";""))"') &&
        _RECORDS=$(_lk_linode_dns_records --argjson reverse false) &&
        _REVERSE=$(_lk_linode_dns_records --argjson reverse true) ||
        return
    while IFS=$'\t' read -r NAME TYPE TARGET TTL; do
        if RECORD=($(lk_require_output lk_jq -r \
            --arg name "$NAME" --arg type "$TYPE" '
include "core";
.[] | select((.name == $name) and (.type | in_arr([$type, "CNAME"]))) | .id' \
            <"$RR")); then
            [ ${#RECORD[@]} -eq 1 ] ||
                lk_warn "unable to update existing records: $NAME.$DOMAIN" ||
                continue
            lk_tty_detail "Updating DNS record $RECORD:" "$NAME $TYPE $TARGET"
            JSON=$(linode-cli --json domains records-update \
                --name "$NAME" \
                --target "$TARGET" \
                --ttl_sec "$TTL" \
                "$DOMAIN_ID" \
                "$RECORD" \
                "${@:3}")
        else
            lk_tty_detail "Adding DNS record:" "$NAME $TYPE $TARGET"
            ((++NEW_RECORD_COUNT))
            JSON=$(linode-cli --json domains records-create \
                --type "$TYPE" \
                --name "$NAME" \
                --target "$TARGET" \
                --ttl_sec "$TTL" \
                "$DOMAIN_ID" \
                "${@:3}") &&
                RECORD[0]=$(jq '.[0].id' <<<"$JSON") &&
                lk_tty_detail "Record ID:" "$RECORD"
        fi || lk_warn "unable to add DNS record" || return
        lk_linode_flush_cache
    done < <(comm -23 \
        <(sort -u <<<"$_RECORDS") \
        <(sort -u <<<"$RECORDS"))
    while IFS=$'\t' read -r ADDRESS RDNS; do
        [ "$NEW_RECORD_COUNT" -eq 0 ] ||
            [ "$NEW_REVERSE_RECORD_COUNT" -gt 0 ] || (
            lk_tty_print "Waiting for $RDNS to resolve"
            i=0
            while ((i < 8)); do
                SLEEP=$(((++i) ** 2))
                ((i == 1)) || lk_tty_detail "Trying again in $SLEEP seconds"
                sleep "$SLEEP" || return
                _LK_DNS_SERVER=ns$((RANDOM % 5 + 1)).linode.com
                ! lk_require_output -q lk_dns_resolve_hosts -d "$RDNS" ||
                    exit 0
            done
            exit 1
        ) || lk_warn \
            "cannot add RDNS record for $ADDRESS until $RDNS resolves" ||
            return
        lk_tty_print "Adding RDNS record:" "$ADDRESS $RDNS"
        lk_keep_trying eval "JSON=\$($(lk_quote_args \
            linode-cli --json networking ip-update \
            --rdns "$RDNS" \
            "$ADDRESS" \
            "${@:3}"))" ||
            lk_warn "unable to add RDNS record" || return
        lk_linode_flush_cache
        ((++NEW_REVERSE_RECORD_COUNT))
        lk_tty_detail "Record added"
    done < <(comm -23 \
        <(sort <<<"$_REVERSE") \
        <(sort <<<"$REVERSE"))
    ! lk_verbose || {
        RECORDS=$(lk_linode_domain_records "$DOMAIN_ID" "${@:3}" |
            jq -r '.[]|"\(.name)\t\(.type)\t\(.target)\t\(.ttl_sec)"') || return
        RECORDS=$(comm -13 \
            <(sort -u <<<"$_RECORDS") \
            <(sort -u <<<"$RECORDS"))
        [ -z "$RECORDS" ] ||
            lk_tty_print "Records in '$DOMAIN' with no matching Linode:" \
                $'\n'"$RECORDS" "$LK_BOLD$LK_RED"
    }
}

# lk_linode_dns_check_all [-t] [DOMAIN_ID [LINODE_ARG...]]
function lk_linode_dns_check_all() {
    local USE_TAGS LINODES LABELS
    [ "${1-}" != -t ] || { USE_TAGS=1 && shift; }
    LINODES=$(lk_linode_linodes "${@:2}") || return
    lk_jq_get_array LABELS '.[]|"\(.label) (\(.tags|join(", ")))"' <<<"$LINODES"
    [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS | sort |
        lk_tty_list - "Checking DNS and RDNS records for:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    LK_VERBOSE=1 \
        lk_linode_dns_check ${USE_TAGS:+-t} "$LINODES" "$1" "${@:2}" || return
    lk_tty_success "DNS check complete"
}

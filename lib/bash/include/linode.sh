#!/bin/bash

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
        ((PAGE++, COUNT == 100)) || break
    done | jq --slurp
}

function linode-cli-json {
    lk_cache -t 1200 _lk_linode_cli_json "$@"
}

function lk_linode_flush_cache() {
    lk_cache_mark_dirty
}

lk_linode_linodes() { linode-cli-json linodes list "$@"; }
lk_linode_ips() { linode-cli-json networking ips-list "$@"; }
lk_linode_domains() { linode-cli-json domains list "$@"; }
lk_linode_domain_records() { linode-cli-json domains records-list "$@"; }
lk_linode_firewalls() { linode-cli-json firewalls list "$@"; }
lk_linode_firewall_devices() { linode-cli-json firewalls devices-list "$@"; }
lk_linode_stackscripts() { linode-cli-json stackscripts list --is_public false "$@"; }

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

# lk_linode_ssh_add [NAME [USER]]
#
# Add an SSH host for each Linode object in the JSON input array.
function lk_linode_ssh_add() {
    local LINODES LINODE SH LABEL USERNAME PUBLIC_SUFFIX \
        LK_SSH_PRIORITY=${LK_SSH_PRIORITY-45}
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_linode_sh <<<"$LINODE") &&
            eval "$SH"
        eval "LABEL=${1-}"
        LABEL=${LABEL:-${LINODE_LABEL%%.*}}
        eval "USERNAME=${2-}"
        lk_tty_detail "Adding SSH host:" \
            $'\n'"${LK_SSH_PREFIX-$LK_PATH_PREFIX}$LABEL ($(lk_implode_args \
                " + " \
                ${LINODE_IPV4_PRIVATE:+"$LK_BOLD$LINODE_IPV4_PRIVATE$LK_RESET"} \
                ${LINODE_IPV4_PUBLIC:+"$LINODE_IPV4_PUBLIC"}))"
        PUBLIC_SUFFIX=
        if [ "$(lk_hostname)" = jump ]; then
            lk_ssh_add_host "$LABEL" \
                "$LINODE_IPV4_PRIVATE" "$USERNAME" || return
            PUBLIC_SUFFIX=-public
        elif [ "${LINODE_IPV4_PRIVATE:+1}${LK_SSH_JUMP_HOST:+1}" = 11 ]; then
            lk_ssh_add_host "$LABEL" \
                "$LINODE_IPV4_PRIVATE" "$USERNAME" "" "jump" || return
            PUBLIC_SUFFIX=-direct
        fi
        [ -z "$LINODE_IPV4_PUBLIC" ] || lk_ssh_add_host "$LABEL$PUBLIC_SUFFIX" \
            "$LINODE_IPV4_PUBLIC" "$USERNAME" || return
    done
}

# lk_linode_ssh_add_all [LINODE_ARG...]
function lk_linode_ssh_add_all() {
    local JSON LABELS
    JSON=$(lk_linode_linodes "$@" | lk_linode_filter_linodes) || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON" &&
        [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS | sort |
        lk_tty_list - "Adding to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    lk_linode_ssh_add <<<"$JSON"
    lk_tty_success "SSH configuration complete"
}

# lk_linode_hosting_ssh_add_all [LINODE_ARG...]
function lk_linode_hosting_ssh_add_all() {
    local GET_USERS_SH JSON LINODES LINODE SH IFS USERS USERNAME ALL_USERS=()
    GET_USERS_SH=$(printf '%q\n' \
        "$(declare -f lk_get_users_in_group lk_get_standard_users &&
            lk_quote_args lk_get_standard_users /srv/www)") || return
    JSON=$(lk_linode_linodes "$@" | lk_linode_filter_linodes) &&
        lk_jq_get_array LINODES <<<"$JSON" &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    jq -r '.[].label' <<<"$JSON" | sort | lk_tty_list - \
        "Adding hosting accounts to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_linode_sh <<<"$LINODE") &&
            eval "$SH" || return
        lk_tty_print "Retrieving hosting accounts from" "$LINODE_LABEL"
        IFS=$'\n'
        USERS=($(ssh "${LK_SSH_PREFIX-$LK_PATH_PREFIX}${LINODE_LABEL%%.*}" \
            "bash -c $GET_USERS_SH")) || return
        unset IFS
        for USERNAME in ${USERS[@]+"${USERS[@]}"}; do
            ! lk_in_array "$USERNAME" ALL_USERS || {
                lk_tty_warning "Skipping $USERNAME (already used)"
                continue
            }
            ALL_USERS+=("$USERNAME")
            LK_SSH_PRIORITY='' \
                lk_linode_ssh_add "$USERNAME" "$USERNAME" <<<"[$LINODE]"
            LK_SSH_PRIORITY='' \
                lk_linode_ssh_add "$USERNAME-admin" "" <<<"[$LINODE]"
        done
    done
    lk_tty_success "SSH configuration complete"
}

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
        lk_tty_run_detail linode-cli --json domains records-create \
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
        lk_tty_run_detail linode-cli --json domains records-update \
            --name "$3" \
            --ttl_sec "${4:-0}" \
            --type "$5" \
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
        lk_tty_run_detail linode-cli domains records-delete \
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
                --type "$TYPE" \
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

function lk_linode_hosting_get_stackscript() {
    local STACKSCRIPT
    STACKSCRIPT=$(lk_linode_stackscripts --label hosting.sh "$@" |
        jq -r '.[].id' |
        sort -n) &&
        [ -n "$STACKSCRIPT" ] && {
        [ "$(wc -l <<<"$STACKSCRIPT")" -eq 1 ] ||
            lk_warn "multiple hosting.sh StackScripts found" || true
        echo "$STACKSCRIPT" | tail -n1
    }
}

# lk_linode_hosting_update_stackscript [REPO [REF [LINODE_ARG...]]]
function lk_linode_hosting_update_stackscript() {
    local REPO=${1:-$LK_BASE} REF=${2:-HEAD} HASH BASED_ON \
        SCRIPT STACKSCRIPT ARGS MESSAGE OUTPUT
    cd "$REPO" || return
    HASH=$(git rev-parse --verify "$REF") &&
        BASED_ON=($(LK_GIT_REF=$HASH \
            lk_git_ancestors main develop | head -n1)) ||
        lk_warn "invalid ref: $REF" || return
    SCRIPT=$(git show "$HASH:lib/linode/hosting.sh") || return
    if STACKSCRIPT=$(lk_linode_hosting_get_stackscript "${@:3}"); then
        ARGS=(update "$STACKSCRIPT")
        MESSAGE="updated to"
        lk_tty_print "Updating StackScript" "$STACKSCRIPT"
    else
        ARGS=(create)
        MESSAGE="created with"
        lk_tty_print "Creating StackScript"
    fi
    OUTPUT=$(linode-cli --json stackscripts "${ARGS[@]}" \
        --label hosting.sh \
        --images linode/ubuntu22.04 \
        --images linode/ubuntu20.04 \
        --images linode/ubuntu18.04 \
        --script "$SCRIPT" \
        --description "Provision a new Linode configured for hosting" \
        --is_public false \
        --rev_note "commit: ${HASH:0:7} (based on lk-platform/${BASED_ON[2]}@${BASED_ON[1]:0:7})" \
        "${@:3}") ||
        lk_warn "unable to ${ARGS[0]} StackScript" || return
    lk_linode_flush_cache
    STACKSCRIPT=$(jq -r '.[0].id' <<<"$OUTPUT") &&
        lk_tty_detail "StackScript $STACKSCRIPT $MESSAGE" "${HASH:0:7}:hosting.sh"
}

function lk_linode_provision_hosting() {
    local IFS=$'\n' REBUILD NODE_FQDN NODE_HOSTNAME HOST_DOMAIN HOST_ACCOUNT \
        ROOT_PASS AUTHORIZED_KEYS STACKSCRIPT STACKSCRIPT_DATA \
        ARGS VERBS KEY FILE LINODES EXIT_STATUS LINODE SH
    [ "${1-}" != -r ] || { REBUILD=$2 && shift 2; }
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME [-r LINODE_ID] FQDN DOMAIN [ACCOUNT [DATA_JSON [LINODE_ARG...]]]

Create a new Linode at FQDN and configure it to serve DOMAIN from user ACCOUNT.

\\SSH public keys are added from:
- array variable LK_LINODE_SSH_KEYS
- file LK_LINODE_SSH_KEYS_FILE
- ~/.ssh/authorized_keys (if both LK_LINODE_SSH_KEYS and LK_LINODE_SSH_KEYS_FILE
  are empty or unset)

Example:
  $FUNCNAME syd06.linode.myhosting.com linacreative.com lina" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    lk_is_fqdn "$2" || lk_warn "invalid domain: $2" || return
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    NODE_FQDN=$1
    NODE_HOSTNAME=${1%%.*}
    HOST_DOMAIN=$2
    HOST_ACCOUNT=${3:-${2%%.*}}
    [[ $HOST_ACCOUNT =~ ^$LINUX_USERNAME_REGEX$ ]] ||
        lk_warn "invalid username: $HOST_ACCOUNT" || return
    AUTHORIZED_KEYS=(
        ${LK_LINODE_SSH_KEYS[@]+"${LK_LINODE_SSH_KEYS[@]}"}
        $([ ! -f "${LK_LINODE_SSH_KEYS_FILE-}" ] ||
            cat "$LK_LINODE_SSH_KEYS_FILE")
    )
    [ ${#AUTHORIZED_KEYS[@]} -gt 0 ] ||
        [ ! -f ~/.ssh/authorized_keys ] ||
        AUTHORIZED_KEYS=($(cat ~/.ssh/authorized_keys)) || return
    [ ${#AUTHORIZED_KEYS[@]} -gt 0 ] ||
        lk_warn "at least one authorized SSH key is required" || return
    unset IFS
    STACKSCRIPT=$(lk_linode_hosting_get_stackscript "${@:5}") ||
        lk_warn "hosting.sh StackScript not found" || return
    ARGS=(linodes create)
    VERBS=(Creating created)
    [ -z "${REBUILD-}" ] || {
        ARGS=(linodes rebuild)
        VERBS=(Rebuilding rebuilt)
        lk_linode_flush_cache
        LINODE=$(lk_linode_linodes "${@:5}" |
            jq -e --arg id "$REBUILD" \
                '[.[]|select((.id|tostring==$id) or .label==$id)]|if length==1 then .[0] else empty end') ||
            lk_warn "Linode not found: $REBUILD" || return
        SH=$(lk_linode_linode_sh <<<"$LINODE") &&
            eval "$SH" || return
        lk_tty_print "Rebuilding:" \
            "$LINODE_LABEL ($(lk_implode_arr ", " LINODE_TAGS))"
        lk_tty_detail "Linode ID:" "$LINODE_ID"
        lk_tty_detail "Linode type:" "$LINODE_TYPE"
        lk_tty_detail "CPU count:" "$LINODE_VPCUS"
        lk_tty_detail "Memory:" "$LINODE_MEMORY"
        lk_tty_detail "Storage:" "$((LINODE_DISK / 1024))G"
        lk_tty_detail "IP addresses:" $'\n'"$(lk_echo_args \
            $LINODE_IPV4_PUBLIC $LINODE_IPV6 $LINODE_IPV4_PRIVATE)"
        lk_confirm "Destroy the existing Linode and start over?" N || return
        ARGS+=(--image "$LINODE_IMAGE")
    }
    STACKSCRIPT_DATA=$(jq -n \
        --arg nodeFqdn "$NODE_FQDN" \
        --arg hostDomain "$HOST_DOMAIN" \
        --arg hostAccount "$HOST_ACCOUNT" \
        --arg adminEmail "${LK_ADMIN_EMAIL:-root@$NODE_FQDN}" \
        --arg autoReboot "${LK_AUTO_REBOOT:-Y}" \
        '{
    "LK_NODE_FQDN": $nodeFqdn,
    "LK_HOST_DOMAIN": $hostDomain,
    "LK_HOST_ACCOUNT": $hostAccount,
    "LK_ADMIN_EMAIL": $adminEmail,
    "LK_AUTO_REBOOT": $autoReboot
}'"${4:+ + $4}")
    ROOT_PASS=$(lk_random_password 64)
    ARGS+=(
        --json
        --root_pass "$ROOT_PASS"
        --stackscript_id "$STACKSCRIPT"
        --stackscript_data "$STACKSCRIPT_DATA"
    )
    [ -n "${REBUILD-}" ] || ARGS+=(
        --label "$NODE_HOSTNAME"
        --tags "${HOST_ACCOUNT:-$NODE_HOSTNAME}"
        --private_ip true
    )
    for KEY in "${AUTHORIZED_KEYS[@]}"; do
        ARGS+=(--authorized_keys "$KEY")
    done
    ARGS+=(
        "${@:5}"
        ${REBUILD:+"$LINODE_ID"}
    )
    lk_tty_print "Running:" \
        $'\n'"$(lk_fold_quote_options -120 linode-cli "${ARGS[@]##ssh-??? * }")"
    lk_confirm "Proceed?" Y || return
    lk_tty_print "${VERBS[0]} Linode"
    FILE=/tmp/$FUNCNAME-$1-$(lk_date %s).json
    LINODES=$(linode-cli "${ARGS[@]}" | tee "$FILE") ||
        lk_pass rm -f "$FILE" || return
    lk_linode_flush_cache
    LINODE=$(jq -c '.[0]' <<<"$LINODES")
    lk_tty_print "Linode ${VERBS[1]} successfully"
    lk_tty_detail "Root password:" "$ROOT_PASS"
    lk_tty_detail "Response written to:" "$FILE"
    SH=$(lk_linode_linode_sh <<<"$LINODE") &&
        eval "$SH" || return
    lk_tty_detail "Linode ID:" "$LINODE_ID"
    lk_tty_detail "Linode type:" "$LINODE_TYPE"
    lk_tty_detail "CPU count:" "$LINODE_VPCUS"
    lk_tty_detail "Memory:" "$LINODE_MEMORY"
    lk_tty_detail "Storage:" "$((LINODE_DISK / 1024))G"
    lk_tty_detail "Image:" "$LINODE_IMAGE"
    lk_tty_detail "IP addresses:" $'\n'"$(lk_echo_args \
        $LINODE_IPV4_PUBLIC $LINODE_IPV6 $LINODE_IPV4_PRIVATE)"
    lk_linode_ssh_add <<<"$LINODES"
    [ -z "$HOST_ACCOUNT" ] || {
        LK_SSH_PRIORITY='' \
            lk_linode_ssh_add "$HOST_ACCOUNT" "$HOST_ACCOUNT" <<<"$LINODES"
        LK_SSH_PRIORITY='' \
            lk_linode_ssh_add "$HOST_ACCOUNT-admin" "" <<<"$LINODES"
    }
    lk_linode_dns_check -t "$LINODES" "${NODE_FQDN#*.}" "${@:5}" &&
        LK_LINODE_JSON_FILE=$FILE
}

# lk_linode_hosting_get_meta DIR HOST...
function lk_linode_hosting_get_meta() {
    local DIR=${1-} _DIR HOST SSH_HOST FILE COMMIT EXT \
        FILES _FILES _FILE PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX} s=/
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME DIR HOST..." || return
    [ -d "$DIR" ] || lk_warn "not a directory: $DIR" || return
    DIR=${DIR%/}
    for HOST in "${@:2}"; do
        _DIR=$DIR/$HOST
        lk_install -d -m 00755 "$_DIR" || return
        SSH_HOST=$PREFIX${HOST#"$PREFIX"}
        FILE=$_DIR/StackScript-$HOST
        [ -e "$FILE" ] || {
            ssh "$SSH_HOST" \
                "sudo bash -c 'cp -pv /root/StackScript . && chown \$SUDO_USER: StackScript'" &&
                scp -p "$SSH_HOST":StackScript "$FILE" || return
            ! COMMIT=$(ssh "$SSH_HOST" "bash -c$(printf ' %q' \
                '{ cd "$1" 2>/dev/null || cd /opt/lk-platform; } && git rev-list -g HEAD | tail -n1' \
                bash \
                "/opt/${PREFIX}platform")") ||
                [ -z "$COMMIT" ] || {
                awk -f "$LK_BASE/lib/awk/patch-hosting-script.awk" \
                    -v commit="$COMMIT" <"$FILE" >"$FILE-patched" &&
                    touch -r "$FILE" "$FILE-patched" || return
            }
        }
        for EXT in log out; do
            FILE=$_DIR/install.$EXT-$HOST
            [ -e "$FILE" ] ||
                scp -p "$SSH_HOST:/var/log/lk-platform-install.$EXT" "$FILE" 2>/dev/null ||
                scp -p "$SSH_HOST:/var/log/${PREFIX}install.$EXT" "$FILE" 2>/dev/null || {
                _FILE=/opt/lk-platform/var/log/lk-provision-hosting.sh-0.$EXT
                ssh "$SSH_HOST" \
                    "sudo bash -c 'cp -pv $_FILE . && chown \$SUDO_USER: ${_FILE##*/}'" &&
                    scp -p "$SSH_HOST:${_FILE##*/}" "$FILE.tmp" &&
                    awk '!skip{print}/Shutdown scheduled for/{skip=1}' \
                        "$FILE.tmp" >"$FILE" &&
                    touch -r "$FILE.tmp" "$FILE" &&
                    rm -f "$FILE.tmp"
            } || return
        done
        FILES=$(ssh "$SSH_HOST" realpath -eq \
            /etc/default/lk-platform \
            /opt/{lk-,"$PREFIX"}platform/etc/{{lk-platform/,}"sites/*.conf",lk-platform/lk-platform.conf} \
            /etc/memcached.conf \
            "/etc/apache2/sites-available/*.conf" \
            "/etc/mysql/mariadb.conf.d/*$PREFIX*.cnf" \
            "/etc/php/*/fpm/pool.d/*.conf" \
            2>/dev/null | sort -u) || [ $? -ne 255 ]
        lk_mapfile _FILES <<<"$FILES"
        for _FILE in ${_FILES[@]+"${_FILES[@]}"}; do
            FILE=${_FILE#/}
            FILE=$_DIR/${FILE//"$s"/__}
            scp -p "$SSH_HOST:$_FILE" "$FILE" || return
        done
        awk -f "$LK_BASE/lib/awk/get-install-env.awk" \
            "$_DIR/install.log-$HOST" | { sed -E \
                -e '/^(DEBCONF_NONINTERACTIVE_SEEN|DEBIAN_FRONTEND|HOME|LINODE_.*|PATH|PWD|SHLVL|TERM|_)=/d' \
                -e 's/^((LK_)?NODE_(HOSTNAME|FQDN)=)/\1test-/' \
                -e '/^(LK_)?ADMIN_EMAIL=/d' \
                -e 's/^(CALL_HOME_MX=).*/\1/' &&
                if grep -Eq '<(lk:)?UDF\>.*\<ADMIN_EMAIL\>' \
                    "$_DIR/StackScript-$HOST"; then
                    printf ADMIN_EMAIL
                else
                    printf LK_ADMIN_EMAIL
                fi && echo "=nobody@localhost.localdomain"; } |
            while IFS='=' read -r VAR VALUE; do
                printf '%s=%q\n' "$VAR" "$VALUE"
            done >"$_DIR/StackScript-env-$HOST" &&
            touch -r "$_DIR/install.log-$HOST" \
                "$_DIR/StackScript-env-$HOST" "$_DIR" || return
    done
}

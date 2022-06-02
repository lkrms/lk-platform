#!/bin/bash

# _lk_cpanel_get_url SERVER MODULE FUNC [PARAMETER=VALUE...]
function _lk_cpanel_get_url() {
    [ $# -ge 3 ] || lk_warn "invalid arguments" || return
    local PARAMS
    printf 'https://%s:%s/%s/%s' \
        "$1" \
        "${_LK_CPANEL_PORT:-2083}" \
        "${_LK_CPANEL_ROOT:-execute}" \
        "$2${3:+/$3}"
    shift 3
    PARAMS=$(lk_uri_encode "$@") || return
    [ -z "${PARAMS:+1}" ] || printf "?%s" "$PARAMS"
    echo
}

# _lk_cpanel_via_whm_get_url SERVER USER MODULE FUNC [PARAMETER=VALUE...]
function _lk_cpanel_via_whm_get_url() {
    [[ $# -ge 4 ]] || lk_warn "invalid arguments" || return
    local _USER=$2 MODULE=$3 FUNC=$4 PARAMS
    printf 'https://%s:%s/json-api/cpanel' "$1" 2087
    shift 4
    PARAMS=$(lk_uri_encode \
        "api.version=1" \
        "cpanel_jsonapi_user=$_USER" \
        "cpanel_jsonapi_module=$MODULE" \
        "cpanel_jsonapi_func=$FUNC" \
        "cpanel_jsonapi_apiversion=3" \
        "$@") || return
    printf "?%s\n" "$PARAMS"
}

# _lk_cpanel_token_generate_name PREFIX
function _lk_cpanel_token_generate_name() {
    local HOSTNAME=${HOSTNAME-} NAME
    HOSTNAME=${HOSTNAME:-$(lk_hostname)} &&
        NAME=$1-${LK_PATH_PREFIX:-lk-}$USER@$HOSTNAME-$(lk_timestamp) &&
        NAME=$(printf '%s' "$NAME" | tr -Cs '[:alnum:]-_' '-') &&
        echo "$NAME"
}

# lk_cpanel_server_set SERVER [USER]
function lk_cpanel_server_set() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME SERVER [USER]" || return
    unset "${!_LK_CPANEL_@}"
    _LK_CPANEL_SERVER=$1
    if lk_ssh_host_exists "$1"; then
        _LK_CPANEL_METHOD=ssh
        [ $# -eq 1 ] || _LK_CPANEL_SERVER=$2@$1
    else
        _LK_CPANEL_METHOD=curl
        [ $# -ge 2 ] || lk_warn "username required for curl access" || return
    fi
    local FILE
    lk_check_user_config FILE \
        token "cpanel-${_LK_CPANEL_METHOD}-${2+$2@}$1" 00600 00700 &&
        . "$FILE" || return
    [ -s "$FILE" ] ||
        case "$_LK_CPANEL_METHOD" in
        curl)
            local NAME URL
            NAME=$(_lk_cpanel_token_generate_name "$2") &&
                URL=$(_lk_cpanel_get_url "$1" Tokens create_full_access \
                    "name=$NAME") || return
            _LK_CPANEL_TOKEN=$2:$(curl -fsSL --insecure --user "$2" "$URL" |
                jq -r '.data.token') ||
                lk_warn "unable to create API token" || return
            ;;
        esac
    lk_file_replace "$FILE" < <(lk_var_sh "${!_LK_CPANEL_@}") &&
        lk_symlink "${FILE##*/}" "${FILE%/*}/cpanel-current"
}

# _lk_cpanel_server_do_check METHOD_VAR SERVER_VAR TOKEN_VAR PREFIX
function _lk_cpanel_server_do_check() {
    local i=0 FILE _LK_STACK_DEPTH=2
    while :; do
        case "${!1-}" in
        ssh)
            [ "${!2:+1}" != 1 ] ||
                return 0
            ;;
        curl)
            [ "${!2:+1}${!3:+1}" != 11 ] ||
                return 0
            ;;
        esac
        ! ((i++)) &&
            lk_check_user_config -n FILE token "$4-current" &&
            [ -f "$FILE" ] &&
            . "$FILE" || break
    done
    lk_warn "lk_$4_server_set must be called first"
    false
}

function _lk_cpanel_server_check() {
    _lk_cpanel_server_do_check \
        _LK_CPANEL_METHOD _LK_CPANEL_SERVER _LK_CPANEL_TOKEN cpanel
}

# lk_cpanel_get MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_get() {
    [[ $# -ge 2 ]] || lk_usage "\
Usage: $FUNCNAME MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_cpanel_server_check || return
    local IFS
    unset IFS
    case "$_LK_CPANEL_METHOD" in
    ssh)
        # {"result":{"data":{}}}
        ssh "$_LK_CPANEL_SERVER" \
            uapi --output=json "$1" "$2" "${@:3}" |
            jq -cM '.result'
        ;;
    curl)
        # {"data":{}}
        local URL
        URL=$(_lk_cpanel_get_url "$_LK_CPANEL_SERVER" "$1" "$2" "${@:3}") &&
            curl -fsSL --insecure \
                -H "Authorization: cpanel $_LK_CPANEL_TOKEN" \
                "$URL"
        ;;
    esac
}

# lk_cpanel_post MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_post() {
    [[ $# -ge 2 ]] || lk_usage "\
Usage: $FUNCNAME MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_cpanel_server_check || return
    [[ $_LK_CPANEL_METHOD == curl ]] || {
        lk_cpanel_get "$@"
        return
    }
    local IFS URL ARGS
    unset IFS
    URL=$(_lk_cpanel_get_url "$_LK_CPANEL_SERVER" "$1" "$2") &&
        lk_curl_get_form_args ARGS "${@:3}" &&
        curl -fsS --insecure "${ARGS[@]}" \
            -H "Authorization: cpanel $_LK_CPANEL_TOKEN" \
            "$URL"
}

# _lk_whm_get_url SERVER FUNC [PARAMETER=VALUE...]
function _lk_whm_get_url() {
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    local SERVER=$1 FUNC=$2 \
        _LK_CPANEL_PORT=2087 _LK_CPANEL_ROOT=json-api
    shift 2
    _lk_cpanel_get_url "$SERVER" "$FUNC" "" "api.version=1" "$@"
}

# lk_whm_server_set SERVER [USER]
function lk_whm_server_set() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME SERVER [USER]" || return
    unset "${!_LK_WHM_@}"
    _LK_WHM_SERVER=$1
    if lk_ssh_host_exists "$1"; then
        _LK_WHM_METHOD=ssh
        [ $# -eq 1 ] || _LK_WHM_SERVER=$2@$1
    else
        _LK_WHM_METHOD=curl
        [ $# -ge 2 ] || lk_warn "username required for curl access" || return
    fi
    local FILE
    lk_check_user_config FILE \
        token "whm-${_LK_WHM_METHOD}-${2+$2@}$1" 00600 00700 &&
        . "$FILE" || return
    [ -s "$FILE" ] ||
        case "$_LK_WHM_METHOD" in
        curl)
            local NAME URL
            NAME=$(_lk_cpanel_token_generate_name "whm-$2") &&
                URL=$(_lk_whm_get_url "$1" api_token_create \
                    "token_name=$NAME") || return
            _LK_WHM_TOKEN=$2:$(curl -fsSL --insecure --user "$2" "$URL" |
                jq -r '.data.token') ||
                lk_warn "unable to create API token" || return
            ;;
        esac
    lk_file_replace "$FILE" < <(lk_var_sh "${!_LK_WHM_@}") &&
        lk_symlink "${FILE##*/}" "${FILE%/*}/whm-current"
}

function _lk_whm_server_check() {
    _lk_cpanel_server_do_check \
        _LK_WHM_METHOD _LK_WHM_SERVER _LK_WHM_TOKEN whm
}

# lk_whm_get FUNC [PARAMETER=VALUE...]
function lk_whm_get() {
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    local IFS
    unset IFS
    case "$_LK_WHM_METHOD" in
    ssh)
        # {"data":{}}
        ssh "$_LK_WHM_SERVER" \
            whmapi1 --output=json "$1" "${@:2}"
        ;;
    curl)
        # {"data":{}}
        local URL
        URL=$(_lk_whm_get_url "$_LK_WHM_SERVER" "$1" "${@:2}") &&
            curl -fsSL --insecure \
                -H "Authorization: whm $_LK_WHM_TOKEN" \
                "$URL"
        ;;
    esac
}

# lk_whm_post FUNC [PARAMETER=VALUE...]
function lk_whm_post() {
    [[ $# -ge 1 ]] || lk_usage "\
Usage: $FUNCNAME FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    [[ $_LK_WHM_METHOD == curl ]] || {
        lk_whm_get "$@"
        return
    }
    local IFS URL ARGS
    unset IFS
    URL=$(_lk_whm_get_url "$_LK_WHM_SERVER" "$1")
    lk_curl_get_form_args ARGS "${@:2}" &&
        curl -fsS --insecure "${ARGS[@]}" \
            -H "Authorization: whm $_LK_WHM_TOKEN" \
            "$URL"
}

# lk_cpanel_get_via_whm USER MODULE FUNC [PARAMETER=VALUE...]
function lk_cpanel_get_via_whm() {
    [[ $# -ge 3 ]] || lk_usage "\
Usage: $FUNCNAME USER MODULE FUNC [PARAMETER=VALUE...]" || return
    _lk_whm_server_check || return
    local IFS
    unset IFS
    case "$_LK_WHM_METHOD" in
    ssh)
        # Output schema TBC
        ssh "$_LK_WHM_SERVER" \
            whmapi1 --output=json \
            uapi_cpanel \
            cpanel.user="$1" \
            cpanel.module="$2" \
            cpanel.function="$3" \
            "${@:4}"
        ;;
    curl)
        # {"result":{"data":{}}}
        local URL
        URL=$(_lk_cpanel_via_whm_get_url "$_LK_WHM_SERVER" "$1" "$2" "$3" "${@:4}") &&
            curl -fsSL --insecure \
                -H "Authorization: whm $_LK_WHM_TOKEN" \
                "$URL" |
            jq -cM '.result'
        ;;
    esac
}

# lk_cpanel_domain_list
function lk_cpanel_domain_list() {
    _lk_cpanel_server_check || return
    lk_cpanel_get DomainInfo domains_data format=list |
        jq -r '.data[] | (.domain, .serveralias) | select(. != null)' |
        tr -s '[:space:]' '\n' |
        sort -u
}

function _lk_cpanel_domain_tsv() {
    lk_jq -r 'include "core";
[ (.data.payload? // .data? // cpanel_error)[] |
    select(.type == "record" and (.record_type | in_arr(["SOA", "NS", "CAA"]) | not)) |
    .name = (.dname_b64 | @base64d) ] |
  sort_by(.record_type, .name)[] |
  [.data_b64[] | @base64d] as $data |
  if   .record_type == "MX"  then . += {"priority": $data[0], "target": $data[1]}
  elif .record_type == "SRV" then . += {"priority": $data[0], "weight": $data[1], "port": $data[2], "target": $data[3]}
  else $data[] as $data | .target = $data end |
  [.line_index, .name, .ttl, .record_type, .priority, .weight, .port, .target] | @tsv'
}

# lk_cpanel_domain_tsv DOMAIN
#
# Print tab-separated values for DNS records in the given cPanel DOMAIN:
# 1. line_index
# 2. name
# 3. ttl
# 4. record_type
# 5. priority
# 6. weight
# 7. port
# 8. target
function lk_cpanel_domain_tsv() {
    _lk_cpanel_server_check &&
        lk_cpanel_post DNS parse_zone zone="$1" | _lk_cpanel_domain_tsv
}

# lk_whm_domain_tsv DOMAIN
#
# Print tab-separated values for DNS records in the given WHM DOMAIN:
# 1. line_index
# 2. name
# 3. ttl
# 4. record_type
# 5. priority
# 6. weight
# 7. port
# 8. target
function lk_whm_domain_tsv() {
    _lk_whm_server_check &&
        lk_whm_get parse_dns_zone zone="$1" | _lk_cpanel_domain_tsv
}

# lk_cpanel_ssl_get_for_domain DOMAIN [TARGET_DIR]
function lk_cpanel_ssl_get_for_domain() {
    lk_is_fqdn "${1-}" && { [ $# -lt 2 ] || [ -d "$2" ]; } ||
        lk_usage "Usage: $FUNCNAME DOMAIN [DIR]" || return
    _lk_cpanel_server_check || return
    local DIR=${2-$PWD} JSON CERT CA KEY
    [ -w "$DIR" ] || lk_warn "directory not writable: $DIR" || return
    lk_tty_print "Retrieving TLS certificate for" "$1"
    lk_tty_detail "cPanel server:" "$_LK_CPANEL_SERVER"
    lk_mktemp_with JSON lk_cpanel_get SSL fetch_best_for_domain domain="$1" &&
        lk_mktemp_with CERT jq -r '.data.crt' "$JSON" &&
        lk_mktemp_with CA jq -r '.data.cab' "$JSON" &&
        lk_mktemp_with KEY jq -r '.data.key' "$JSON" ||
        lk_warn "unable to retrieve TLS certificate" || return
    lk_tty_print "Verifying certificate"
    lk_ssl_verify_cert "$CERT" "$KEY" "$CA" || return
    lk_tty_print "Writing certificate files"
    lk_tty_detail "Certificate and CA bundle:" "$(lk_tty_path "$DIR/$1.cert")"
    lk_tty_detail "Private key:" "$(lk_tty_path "$DIR/$1.key")"
    lk_install -m 00644 "$DIR/$1.cert" &&
        lk_install -m 00640 "$DIR/$1.key" &&
        lk_file_replace -b "$DIR/$1.cert" < <(cat "$CERT" "$CA") &&
        lk_file_replace -bf "$KEY" "$DIR/$1.key"
}

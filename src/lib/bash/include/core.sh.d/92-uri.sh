#!/usr/bin/env bash

# lk_uri_encode PARAMETER=VALUE...
function lk_uri_encode() {
    local ARGS=()
    while [ $# -gt 0 ]; do
        [[ $1 =~ ^([^=]+)=(.*) ]] || lk_err "invalid parameter: $1" || return
        ARGS+=(--arg "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
        shift
    done
    [ ${#ARGS[@]} -eq 0 ] ||
        jq -rn "${ARGS[@]}" \
            '[$ARGS.named|to_entries[]|"\(.key)=\(.value|@uri)"]|join("&")'
}

# lk_curl_get_form_args ARRAY [PARAMETER=VALUE...]
function lk_curl_get_form_args() {
    (($#)) || lk_err "invalid arguments" || return
    eval "$1=()" || return
    local _NEXT="$1[\${#$1[@]}]"
    shift
    # If there are no parameters, -F will not be present to trigger a POST
    (($#)) || eval "$_NEXT=-X; $_NEXT=POST"
    while (($#)); do
        [[ $1 =~ ^([^=]+)=(.*) ]] || lk_err "invalid parameter: $1" || return
        eval "$_NEXT=-F; $_NEXT=\$1"
        shift
    done
}

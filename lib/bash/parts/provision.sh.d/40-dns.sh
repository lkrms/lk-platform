#!/bin/bash

# lk_dns_get_records [+FIELD[,FIELD...]] TYPE[,TYPE...] NAME...
#
# For each NAME, print space-delimited resource records that match one of the
# given record types, optionally limiting the output to one more fields.
#
# FIELD must be one of 'NAME', 'TTL', 'CLASS', 'TYPE', 'RDATA' or 'VALUE'.
# 'RDATA' and 'VALUE' are equivalent. If multiple fields are specified, they are
# printed in resource record order.
function lk_dns_get_records() {
    local FIELDS='$1, $2, $3, $4, $5' IFS TYPES TYPE NAME COMMAND=(
        dig +noall +answer
        ${LK_DIG_OPTIONS+"${LK_DIG_OPTIONS[@]}"}
        ${LK_DIG_SERVER:+@"$LK_DIG_SERVER"}
    )
    [[ ${1-} != +* ]] || {
        FIELDS=$(tr ',' '\n' <<<"${1:1}" | awk '
BEGIN { t["NAME"] = 1; t["TTL"] = 2; t["CLASS"] = 3; t["TYPE"] = 4; t["RDATA"] = 5; t["VALUE"] = 5 }
t[$0] { f[t[$0]] = 1; next }
      { exit 1 }
END   { for (i = 1; i < 6; i++)
        if (f[i]) printf "%s", (j++ ? ", " : "") "$" i }') &&
            [ -n "$FIELDS" ] || lk_warn "invalid field list: $1" || return
        shift
    }
    IFS=,
    TYPES=($(lk_upper "$1"))
    [ ${#TYPES[@]} -gt 0 ] || lk_warn "invalid record type list: $1" || return
    for TYPE in "${TYPES[@]}"; do
        [[ $TYPE =~ ^[A-Z]+$ ]] ||
            lk_warn "invalid record type: $TYPE" || return
        for NAME in "${@:2}"; do
            COMMAND+=("$NAME" "$TYPE")
        done
    done
    "${COMMAND[@]}" | awk -v "r=^$(lk_regex_implode "${TYPES[@]}")\$" \
        "\$4 ~ r { print $FIELDS }"
}

# lk_dns_get_records_first_parent TYPE[,TYPE...] DOMAIN
function lk_dns_get_records_first_parent() {
    lk_is_fqdn "$2" || lk_warn "invalid domain: $2" || return
    local DOMAIN=$2 ANSWER
    while :; do
        ANSWER=$(lk_dns_get_records "$1" "$DOMAIN") || return
        [ -z "$ANSWER" ] || {
            echo "$ANSWER"
            break
        }
        DOMAIN=${DOMAIN#*.}
        lk_is_fqdn "$DOMAIN" || lk_warn "$1 lookup failed: $2" || return
    done
}

# lk_dns_resolve_hosts HOST...
function lk_dns_resolve_hosts() { {
    local HOSTS=()
    while [ $# -gt 0 ]; do
        if lk_is_cidr "$1"; then
            echo "$1"
        elif lk_is_fqdn "$1"; then
            HOSTS[${#HOSTS[@]}]=$1
        elif [[ $1 == *\|* ]]; then
            lk_curl "${1%%|*}" | jq -r "${1#*|}" || return
        fi
        shift
    done
    [ -z "${HOSTS+1}" ] ||
        lk_dns_get_records +VALUE A,AAAA "${HOSTS[@]}"
} | sort -nu; }

#### Reviewed: 2021-09-03

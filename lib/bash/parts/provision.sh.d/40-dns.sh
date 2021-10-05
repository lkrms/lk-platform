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
        ${_LK_DIG_OPTIONS+"${_LK_DIG_OPTIONS[@]}"}
        ${_LK_DNS_SERVER:+@"$_LK_DNS_SERVER"}
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

# lk_dns_resolve_names [-d] FQDN...
#
# Print one or more "ADDRESS HOST" lines for each FQDN. If -d is set, use DNS
# instead of host lookups.
function lk_dns_resolve_names() {
    local USE_DNS
    unset USE_DNS
    [ "${1-}" != -d ] || { USE_DNS= && shift; }
    case "${USE_DNS-$(lk_first_command getent dscacheutil)}" in
    getent)
        getent ahosts "$@" | awk '
$3          { host = $3 }
!a[$1,host] { print $1, host; a[$1,host] = 1 }'
        ;;
    dscacheutil)
        printf '%s\n' "$@" | xargs -n1 \
            dscacheutil -q host -a name | awk '
/^name:/                            { host = $2 }
/^ip(v6)?_address:/ && !a[$2,host]  { print $2, host; a[$2,host] = 1 }'
        ;;
    *)
        lk_dns_get_records +NAME,VALUE A,AAAA "$@" |
            awk '{ sub("\\.$", "", $1); print $2, $1 }'
        ;;
    esac
}

# lk_dns_resolve_hosts [-d] HOST...
#
# Resolve each HOST to one or more IP addresses, where HOST is an IP address,
# CIDR, FQDN or URL|JQ_FILTER, printing each IP and CIDR as-is and ignoring each
# invalid host. If -d is set, use DNS instead of host lookups.
function lk_dns_resolve_hosts() { {
    local USE_DNS HOSTS=()
    [ "${1-}" != -d ] || { USE_DNS=1 && shift; }
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
        lk_dns_resolve_names ${USE_DNS:+-d} "${HOSTS[@]}" | awk '{print $1}'
} | sort -u; }

#### Reviewed: 2021-10-05

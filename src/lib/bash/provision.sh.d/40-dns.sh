#!/bin/bash

# lk_dns_get_records [+FIELD[,FIELD...]] [-TYPE[,TYPE...]] NAME...
#
# For each NAME, print space-delimited resource records, optionally matching one
# or more record types and limiting the output to one or more fields.
#
# FIELD must be one of 'NAME', 'TTL', 'CLASS', 'TYPE', 'RDATA' or 'VALUE'.
# 'RDATA' and 'VALUE' are equivalent. Fields are printed in the specified order.
function lk_dns_get_records() {
    local IFS FIELDS= TYPES=("") i TYPE NAME COMMAND=(
        dig +noall +answer
        ${_LK_DIG_OPTIONS+"${_LK_DIG_OPTIONS[@]}"}
        ${_LK_DNS_SERVER:+@"$_LK_DNS_SERVER"}
    )
    [[ ${1-} != +* ]] || { FIELDS=${1:1} && shift; }
    [[ ${1-} != -* ]] || { IFS=, && TYPES=($(lk_upper "${1:1}")) && shift; }
    unset IFS
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    for i in "${!TYPES[@]}"; do
        TYPE=${TYPES[i]}
        [ "$TYPE" != ANY ] || TYPES[i]=
        for NAME in "$@"; do
            COMMAND+=("$NAME" ${TYPE:+"$TYPE"})
        done
    done
    "${COMMAND[@]}" | awk \
        -v fields="$FIELDS" \
        -v type_re="$(lk_ere_implode_arr -e TYPES)" '
BEGIN { f["NAME"]  = 1;     f["CLASS"] = 3;     f["RDATA"] = 5
        f["TTL"]   = 2;     f["TYPE"]  = 4;     f["VALUE"] = 5
        k = split(fields, a, ",")
        for (i = 1; i <= k; i++) {
          if (field = f[a[i]]) { col[++cols] = field; v = v || (field > 4) }
        } }
!cols { print
        next }
!type_re || $4 ~ "^" type_re "$" {
  if (v) {
    l = $0; for (i = 1; i < 5; i++) { $i = "" } _v = substr($0, 5); $0 = l }
  for (i = 1; i <= cols; i++) {
    j = col[i]; if ($j) { printf (i > 1 ? " %s" : "%s"), (j > 4 ? _v : $j) } }
  print "" }'
}

# lk_dns_get_records_first_parent [+FIELD[,FIELD...]] [-TYPE[,TYPE...]] NAME
function lk_dns_get_records_first_parent() {
    local IFS DOMAIN=${*: -1} ANSWER
    unset IFS
    lk_is_fqdn "$DOMAIN" || lk_warn "invalid domain: $DOMAIN" || return
    while :; do
        ANSWER=$(lk_dns_get_records "${@:1:$#-1}" "$DOMAIN") || return
        [ -z "${ANSWER:+1}" ] || {
            echo "$ANSWER"
            break
        }
        DOMAIN=${DOMAIN#*.}
        lk_is_fqdn "$DOMAIN" || lk_warn "$1 lookup failed: $2" || return
    done
}

# lk_dns_soa NAME
function lk_dns_soa() {
    local _LK_DIG_OPTIONS=(+nssearch)
    lk_require_output lk_dns_get_records_first_parent "$1" ||
        lk_warn "SOA lookup failed: ${*: -1}"
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
        { getent ahosts "$@" || [ $# -eq 2 ]; } | awk '
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
        lk_dns_get_records +NAME,VALUE -A,AAAA "$@" |
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

#### Reviewed: 2021-11-17

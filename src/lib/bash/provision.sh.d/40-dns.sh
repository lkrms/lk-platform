#!/usr/bin/env bash

# lk_dns_get_records [-TYPE[,TYPE...]] [+FIELD[,FIELD...]] NAME...
#
# For each NAME, look up DNS resource records of the given TYPE (default: `A`)
# and if any matching records are found, print whitespace-delimited values for
# each requested FIELD (default: `NAME,TTL,CLASS,TYPE,RDATA`).
#
# CNAMEs are followed recursively, but intermediate records are not printed
# unless CNAME is one of the requested record types.
#
# Field names (not case-sensitive):
# - `NAME`
# - `TTL`
# - `CLASS`
# - `TYPE`
# - `RDATA`
# - `VALUE` (alias for `RDATA`)
#
# Returns false only if an error occurs.
function lk_dns_get_records() {
    local IFS=$' \t\n' FIELDS TYPES TYPE NAME QUERY=() NAMES_REGEX AWK
    while [[ ${1-} == [+-]* ]]; do
        [[ ${1-} != -* ]] || {
            TYPES=($(IFS=, && lk_upper ${1:1} | sort -u)) || return
        }
        [[ ${1-} != +* ]] || {
            FIELDS=$(IFS=, && lk_upper ${1:1} |
                awk -v caller="$FUNCNAME" '
function toexpr(var) { expr = expr (expr ? ", " : "") var }
/^NAME$/ { toexpr("$1"); next }
/^TTL$/ { toexpr("$2"); next }
/^CLASS$/ { toexpr("$3"); next }
/^TYPE$/ { toexpr("$4"); next }
/^(RDATA|VALUE)$/ { toexpr("rdata()"); next }
{ print caller ": invalid field: " $0 > "/dev/stderr"; status = 1 }
END { if (status) { exit status } print expr }') || return
        }
        shift
    done
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    for TYPE in "${TYPES[@]-}"; do
        for NAME in "$@"; do
            QUERY[${#QUERY[@]}]=$NAME
            [[ -z $TYPE ]] ||
                QUERY[${#QUERY[@]}]=$TYPE
        done
    done
    NAMES_REGEX="^$(lk_ere_implode_args -e -- "$@")\\.?\$"
    lk_awk_load AWK sh-dns-get-records || return
    dig +noall +answer \
        ${_LK_DIG_ARGS+"${_LK_DIG_ARGS[@]}"} \
        ${_LK_DNS_SERVER:+@"$_LK_DNS_SERVER"} \
        "${QUERY[@]}" |
        awk -f "$AWK" |
        awk -v S="$S" \
            -v NS="$NS" \
            -v types=${TYPES+"^$(lk_ere_implode_arr -e TYPES)\$"} \
            -v names="${NAMES_REGEX//\\/\\\\}" '
function rdata(r, i) {
  r = $0
  for (i = 0; i < 4; i++) { sub("^" S "*" NS "+" S "+", "", r) }
  return r
}
((! types && $4 != "CNAME") || (types && $4 ~ types)) && ($1 ~ names || "CNAME" ~ types) {
  print '"${FIELDS-}"'
}'
}

# lk_dns_get_records_first_parent [-TYPE[,TYPE...]] [+FIELD[,FIELD...]] NAME
#
# Same as `lk_dns_get_records`, but if no matching records are found, replace
# NAME with its parent domain and retry, continuing until matching records are
# found or there are no more parent domains to try.
#
# Returns false if no matching records are found.
function lk_dns_get_records_first_parent() {
    local IFS=$' \t\n' NAME=${*:$#} DOMAIN
    lk_is_fqdn "$NAME" || lk_warn "invalid domain: $NAME" || return
    DOMAIN=$NAME
    set -- "${@:1:$#-1}"
    while :; do
        lk_dns_get_records "$@" "$NAME" | grep . && break ||
            [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == 01 ]] || return
        NAME=${NAME#*.}
        lk_is_fqdn "$NAME" || lk_warn "lookup failed: $DOMAIN" || return
    done
}

# lk_dns_resolve_name_from_ns NAME
#
# Look up IP addresses for NAME from its primary nameserver and print them if
# found, otherwise return false.
function lk_dns_resolve_name_from_ns() {
    local IFS=$' \t\n' NAMESERVER IP CNAME _LK_DIG_ARGS _LK_DNS_SERVER
    NAMESERVER=$(lk_dns_get_records_first_parent -SOA "$1" |
        awk 'NR == 1 { sub(/\.$/, "", $5); print $5 }') || return
    _LK_DIG_ARGS=(+norecurse)
    _LK_DNS_SERVER=$NAMESERVER
    ! lk_verbose 2 || {
        lk_tty_detail "Using name server:" "$NAMESERVER"
        lk_tty_detail "Looking up A and AAAA records for:" "$1"
    }
    IP=($(lk_dns_get_records +VALUE -A,AAAA "$1")) || return
    if [[ ${#IP[@]} -eq 0 ]]; then
        ! lk_verbose 2 || {
            lk_tty_detail "No A or AAAA records returned"
            lk_tty_detail "Looking up CNAME record for:" "$1"
        }
        CNAME=($(lk_dns_get_records +VALUE -CNAME "$1")) || return
        if [[ ${#CNAME[@]} -eq 1 ]]; then
            ! lk_verbose 2 ||
                lk_tty_detail "CNAME value from $NAMESERVER for $1:" "$CNAME"
            unset _LK_DIG_ARGS _LK_DNS_SERVER
            IP=($(lk_dns_get_records +VALUE -A,AAAA "${CNAME%.}")) || return
        fi
    fi
    [[ ${#IP[@]} -gt 0 ]] ||
        lk_warn "could not resolve $1${_LK_DNS_SERVER+: $NAMESERVER}" || return
    ! lk_verbose 2 ||
        lk_tty_detail \
            "A and AAAA values${_LK_DNS_SERVER+ from $NAMESERVER} for $1:" \
            "$(lk_arr IP)"
    lk_arr IP
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

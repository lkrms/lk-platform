#!/bin/bash

function add_regex() {
    eval "$1=\$2"
    ALL[${#ALL[@]}]=$1
}

function quote() {
    if [[ "$1" =~ [^[:print:]] ]]; then
        printf '%q\n' "$1"
    else
        local r="'\\''"
        echo "'${1//"'"/$r}'"
    fi
}

ALL=()

add_regex DOMAIN_PART_REGEX "[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?"
add_regex DOMAIN_NAME_REGEX "$DOMAIN_PART_REGEX(\\.$DOMAIN_PART_REGEX)+"
add_regex EMAIL_ADDRESS_REGEX "[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~]([-a-zA-Z0-9.!#\$%&'*+/=?^_\`{|}~]{,62}[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~])?@$DOMAIN_NAME_REGEX"

_O="(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])"
add_regex IPV4_REGEX "($_O\\.){3}$_O"
add_regex IPV4_OPT_PREFIX_REGEX "$IPV4_REGEX(/(3[0-2]|[12][0-9]|[1-9]))?"

_H="[0-9a-fA-F]{1,4}"
_P="/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])"
add_regex IPV6_REGEX "(($_H:){7}(:|$_H)|($_H:){6}(:|:$_H)|($_H:){5}(:|(:$_H){1,2})|($_H:){4}(:|(:$_H){1,3})|($_H:){3}(:|(:$_H){1,4})|($_H:){2}(:|(:$_H){1,5})|$_H:(:|(:$_H){1,6})|:(:|(:$_H){1,7}))"
add_regex IPV6_OPT_PREFIX_REGEX "$IPV6_REGEX($_P)?"

add_regex IP_REGEX "($IPV4_REGEX|$IPV6_REGEX)"
add_regex IP_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX)"
add_regex HOST_NAME_REGEX "($DOMAIN_PART_REGEX(\\.$DOMAIN_PART_REGEX)*)"
add_regex HOST_REGEX "($IPV4_REGEX|$IPV6_REGEX|$HOST_NAME_REGEX)"
add_regex HOST_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX|$HOST_NAME_REGEX)"

# https://en.wikipedia.org/wiki/Uniform_Resource_Identifier
_S="[a-zA-Z][-a-zA-Z0-9+.]*"                               # scheme
_U="[-a-zA-Z0-9._~%!\$&'()*+,;=]+"                         # username
_P="[-a-zA-Z0-9._~%!\$&'()*+,;=]*"                         # password
_H="([-a-zA-Z0-9._~%!\$&'()*+,;=]+|\\[([0-9a-fA-F:]+)\\])" # host
_O="[0-9]+"                                                # port
_A="[-a-zA-Z0-9._~%!\$&'()*+,;=:@/]+"                      # path
_Q="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]+"                     # query
_F="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]*"                     # fragment
add_regex URI_REGEX "(($_S):)?(//(($_U)(:($_P))?@)?$_H(:($_O))?)?($_A)?(\\?($_Q))?(#($_F))?"
add_regex URI_REGEX_REQ_SCHEME_HOST "(($_S):)(//(($_U)(:($_P))?@)?$_H(:($_O))?)($_A)?(\\?($_Q))?(#($_F))?"

add_regex HTTP_HEADER_NAME "[-a-zA-Z0-9!#\$%&'*+.^_\`|~]+"

add_regex LINUX_USERNAME_REGEX "[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\\\$)"
add_regex MYSQL_USERNAME_REGEX "[a-zA-Z0-9_]+"

# https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source
add_regex DPKG_SOURCE_REGEX "[a-z0-9][-a-z0-9+.]+"

add_regex IDENTIFIER_REGEX "[a-zA-Z_][a-zA-Z0-9_]*"
add_regex PHP_SETTING_NAME_REGEX "$IDENTIFIER_REGEX(\\.$IDENTIFIER_REGEX)*"
add_regex PHP_SETTING_REGEX "$PHP_SETTING_NAME_REGEX=.*"

add_regex READLINE_NON_PRINTING_REGEX $'\x01[^\x02]*\x02'
add_regex CONTROL_SEQUENCE_REGEX $'\x1b\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]'
add_regex ESCAPE_SEQUENCE_REGEX $'\x1b[\x20-\x2f]*[\x30-\x7e]'
add_regex NON_PRINTING_REGEX $'(\x01[^\x02]*\x02|\x1b(\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]|[\x20-\x2f]*[\x30-\x5a\\\x5c-\x7e]))'

# *_FILTER_REGEX expressions are:
# 1. anchored
# 2. not intended for validation
add_regex IPV4_PRIVATE_FILTER_REGEX "^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|127\\.)"

# *_FINDUTILS_REGEX expressions work with `find` commands that don't recognise
# the -regextype primary (e.g. BSD/macOS `find`)
_1="[0-9]"
_2="$_1$_1"
_4="$_2$_2"
_6="$_2$_2$_2"
add_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX "$_4-$_2-$_2-$_6"

case "${1+${1:-null}}" in
"") ;;
-j | --json)
    for REGEX in "${ALL[@]}"; do
        printf '%s\n' "${REGEX%_REGEX}" "${!REGEX}"
    done | jq -Rn '[[inputs] | . as $stdin | keys[] | select(. % 2 == 0) | {($stdin[.] | ascii_downcase | gsub("_(?<a>[a-z])"; .a | ascii_upcase)): $stdin[. + 1]}] | add'
    exit
    ;;
*)
    echo "Usage: ${0##*/} [-j|--json]" >&2
    exit 1
    ;;
esac

printf '# lk_grep_regex [-v] REGEX
function lk_grep_regex() {
    local v SH
    [ "${1-}" != -v ] || { v=1 && shift; }
    [ $# -eq 1 ] || lk_err "invalid arguments" || return 2
    SH=$(lk_get_regex "$1") && eval "$SH" || return 2
    grep -Ex${v:+v} "${!1}"
}\n\n'

printf '# lk_is_regex REGEX VALUE
function lk_is_regex() {
    local SH
    SH=$(lk_get_regex "$1") && eval "$SH" || return 2
    [[ $2 =~ ^${!1}$ ]]
}\n\n'

FUNCTIONS=(
    #lk_is_ip
    #lk_is_host
    lk_is_cidr
    lk_is_fqdn
    lk_is_email
    lk_is_uri
    lk_is_identifier
)
PATTERNS=(
    #IP_REGEX
    #HOST_REGEX
    IP_OPT_PREFIX_REGEX
    DOMAIN_NAME_REGEX
    EMAIL_ADDRESS_REGEX
    URI_REGEX_REQ_SCHEME_HOST
    IDENTIFIER_REGEX
)
DESCRIPTIONS=(
    #"IP address"
    #"IP address, hostname or domain name"
    "IP address or CIDR"
    "domain name"
    "email address"
    "URI with a scheme and host"
    "Bash identifier"
)
for i in "${!FUNCTIONS[@]}"; do
    FUNCTION=${FUNCTIONS[i]}
    REGEX=${PATTERNS[i]}
    DESC=${DESCRIPTIONS[i]}
    printf '# %s VALUE
#
# Return true if VALUE is a valid %s.
function %s() {\n    lk_is_regex %s "$@"\n}\n\n' \
        "$FUNCTION" "$DESC" "$FUNCTION" "$REGEX"
done

FUNCTIONS=(
    lk_filter_ipv4
    lk_filter_ipv6
    lk_filter_cidr
    lk_filter_fqdn
)
PATTERNS=(
    IPV4_OPT_PREFIX_REGEX
    IPV6_OPT_PREFIX_REGEX
    IP_OPT_PREFIX_REGEX
    DOMAIN_NAME_REGEX
)
DESCRIPTIONS=(
    "dotted-decimal IPv4 address or CIDR"
    "8-hextet IPv6 address or CIDR"
    "IP address or CIDR"
    "domain name"
)

for i in "${!FUNCTIONS[@]}"; do
    FUNCTION=${FUNCTIONS[i]}
    REGEX=${PATTERNS[i]}
    DESC=$(printf \
        'Print each input line that is a valid %s. If -v is set, print each line that is not valid.\n' \
        "${DESCRIPTIONS[i]}" | fold -s -w 78 |
        sed -E 's/^/# /; s/[[:blank:]]+$//')
    printf '# %s [-v]
#
%s
function %s() {\n    _LK_STACK_DEPTH=1 lk_grep_regex "$@" %s || true\n}\n\n' \
        "$FUNCTION" "$DESC" "$FUNCTION" "$REGEX"
done

printf '# lk_get_regex [REGEX...]
#
# Print a Bash variable assignment for each REGEX. If no REGEX is specified,
# print all available regular expressions.
function lk_get_regex() {
    [ $# -gt 0 ] || set -- %s
    local STATUS=0 PREFIX=
    [[ ${FUNCNAME[1]-} =~ ^(main|source)?$ ]] || PREFIX="local "
    while [ $# -gt 0 ]; do
        [ -z "$PREFIX" ] || printf '\''%%s'\'' "$PREFIX"
        case "$1" in' \
    "${ALL[*]}"
for REGEX in "${ALL[@]}"; do
    printf "
        %s)
            printf '%%s=%%q\\\\n' %s %s
            ;;" \
        "$REGEX" "$REGEX" "$(quote "${!REGEX}")"
done
printf '
        *)
            lk_err "regex not found: $1"
            STATUS=1
            ;;
        esac
        shift
    done
    return "$STATUS"
}\n'

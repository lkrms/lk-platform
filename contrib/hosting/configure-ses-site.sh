#!/bin/bash

. lk-bash-load.sh || exit

function __usage() {
    cat <<EOF
Configure a hosting server to send email from the given domain via Amazon SES.

Usage:
  ${0##*/} <SSH_HOST> <SMTP_USER> <DOMAIN> <SOURCE_IP>...

Environment:
  AWS_PROFILE must contain the name of an AWS CLI profile with a default region
  and access to Amazon SES (see \`aws help configure\`).
EOF
}

lk_assert_command_exists aws

lk_getopt
eval "set -- $LK_GETOPT"

[ $# -ge 4 ] || lk_usage
lk_is_fqdn "$3" || lk_usage -e "invalid domain: $3"
lk_is_regex IP_REGEX "${@:4}" &&
    ! printf '%s\n' "${@:4}" |
    lk_grep_regex IP_PRIVATE_FILTER_REGEX >/dev/null ||
    lk_usage -e "invalid source IP"

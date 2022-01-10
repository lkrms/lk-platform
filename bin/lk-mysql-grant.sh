#!/bin/bash

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

. "$LK_BASE/lib/bash/common.sh"
lk_require mysql

lk_log_start
lk_start_trace

USERNAME="${SUDO_USER:-$USER}"

LK_USAGE="\
Usage: sudo ${0##*/} DB_NAME DB_USER DB_PASSWORD

Create MySQL database DB_NAME if it does not already exist, grant all privileges
on it to new or existing MySQL account DB_USER, and set DB_USER's account
password to DB_PASSWORD.

Access will not be granted if DB_NAME or DB_USER are set to any value other than
the invoking user's login name, optionally followed by a suffix with a leading
underscore. Examples of DB_NAME and DB_USER values allowed for the current user:
  - ${USERNAME}
  - ${USERNAME}_blog
  - ${USERNAME}_backup"

lk_getopt
eval "set -- $LK_GETOPT"
[ $# -eq 3 ] || lk_usage

# Validate DB_NAME and DB_USER against SUDO_USER if:
# 1. Running as root;
# 2. SUDO_USER is set (`sudo` only allows privileged users to set SUDO_USER);
#    and
# 3. SUDO_USER is not "root"
#
# Otherwise, assume the invoking user has root access to MySQL
REGEX='^[-a-zA-Z0-9_]+$'
if lk_root && [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
    [[ $USERNAME =~ $REGEX ]] ||
        lk_die "$USERNAME: not a valid database identifier"
    REGEX="^$USERNAME(_[-a-zA-Z0-9_]*)?\$"
fi

[[ $1 =~ $REGEX ]] || lk_usage
[[ $2 =~ $REGEX ]] || lk_usage
[ -n "$3" ] || lk_die "password cannot be empty"

HOST="${LK_MYSQL_HOST:-localhost}"

lk_console_message "Setting MySQL credentials and granting privileges"
lk_console_detail "MySQL database:" "$1"
lk_console_detail "MySQL account:" "$2"
lk_console_detail "MySQL server:" "$HOST"

LK_MYSQL_USERNAME="${LK_MYSQL_USERNAME-root}"
lk_elevate mysql ${LK_MYSQL_USERNAME+-u"$LK_MYSQL_USERNAME"} <<EOF
CREATE DATABASE IF NOT EXISTS \`$1\`;

GRANT ALL PRIVILEGES ON \`$1\`.*
TO '$(lk_mysql_escape "$2")'@'$(lk_mysql_escape "$HOST")'
IDENTIFIED BY '$(lk_mysql_escape "$3")';
EOF

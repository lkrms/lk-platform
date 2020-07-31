#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015

set -euo pipefail
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && false || exit $s; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "realpath: command not found"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR/.." 2>/dev/null) &&
    [ -d "$LK_BASE/lib/bash" ] && export LK_BASE || lk_die "LK_BASE: not found"

include= . "$LK_BASE/lib/bash/common.sh"

[ "$#" -eq 3 ] || lk_usage "\
Usage:
  sudo $(basename "$0") DB_NAME DB_USER DB_PASSWORD

Grant all privileges on MySQL database DB_NAME to account DB_USER and set the
password of MySQL account DB_USER to DB_PASSWORD, where the values of both
DB_NAME and DB_USER are the calling user's login name followed by an optional
suffix. The first character of the optional suffix must be an underscore."

lk_assert_is_root

USERNAME="${SUDO_USER:-root}"
[ "$USERNAME" != "root" ] ||
    lk_die "must be executed via sudo by a standard user"

REGEX="^$(lk_escape_ere "$USERNAME")(_[a-zA-Z0-9_]*)?\$"

[[ "$1" =~ $REGEX ]] || lk_die "$1: invalid database name"
[[ "$2" =~ $REGEX ]] || lk_die "$2: invalid account name"
[ -n "$3" ] || lk_die "password cannot be empty"

HOST="${LK_MYSQL_HOST:-localhost}"

lk_console_message "Setting MySQL credentials and granting privileges"
lk_console_detail "Login name:" "$USERNAME"
lk_console_detail "MySQL database:" "$1"
lk_console_detail "MySQL account:" "$2"
lk_console_detail "MySQL server:" "$HOST"

LK_MYSQL_USERNAME="${LK_MYSQL_USERNAME-root}"
mysql ${LK_MYSQL_USERNAME+-u"$LK_MYSQL_USERNAME"} <<EOF
CREATE DATABASE IF NOT EXISTS \`$1\`;

GRANT ALL PRIVILEGES ON \`$1\`.*
TO '$(lk_escape "$2" "\\" "'")'@'$(lk_escape "$HOST" "\\" "'")'
IDENTIFIED BY '$(lk_escape "$3" "\\" "'")';
EOF

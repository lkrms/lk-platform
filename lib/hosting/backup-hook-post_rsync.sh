#!/bin/bash

[ "$EXIT_STATUS" -eq 0 ] || lk_console_warning0 \
    "WARNING: because rsync failed to complete, database backups may only be \
useful for diagnostic purposes"

OWNER=$(lk_file_owner "$SOURCE") &&
    MYSQL_DATABASES=$(lk_mysql_list -h"${LK_MYSQL_HOST:-localhost}" \
        <<<"SHOW DATABASES" |
        lk_mysql_batch_unescape |
        sed -E "/^$(lk_escape_ere "$OWNER")(_[a-zA-Z0-9_]*)?\$/!d") || return

#!/bin/bash

# shellcheck disable=SC2207

[ "$EXIT_STATUS" -eq 0 ] || lk_console_warning0 \
    "WARNING: because rsync failed to complete, database backups may only be \
useful for diagnostic purposes"

OWNER=$(lk_file_owner "$SOURCE") &&
    lk_mysql_mapfile MYSQL_DATABASES -h"${LK_MYSQL_HOST:-localhost}" \
        <<<"SHOW DATABASES LIKE '$(lk_mysql_escape_like "$OWNER")%'" || return

if [ ${#MYSQL_DATABASES[@]} -gt 0 ]; then
    lk_echo_array MYSQL_DATABASES |
        lk_console_detail_list \
            "MySQL databases found for user '$OWNER':" database databases
    # Add the current time to each dump's file name to
    # 1. simplify cataloguing, and
    # 2. prevent overwriting if there are multiple attempts to create the same
    #    snapshot (e.g. after an rsync failure)
    LK_BACKUP_TIMESTAMP='' \
        "$LK_BASE/bin/lk-mysql-dump.sh" \
        --dest "$LK_SNAPSHOT_DB_ROOT" \
        ${SNAPSHOT_GROUP:+--group "$SNAPSHOT_GROUP"} \
        "${MYSQL_DATABASES[@]}" || return
    lk_console_message \
        "Running rsync again in case of filesystem changes since first rsync"
    run_rsync || return
else
    lk_console_detail "No MySQL databases found for user '$OWNER'"
fi

#!/bin/bash

# shellcheck disable=SC2207

[ "$EXIT_STATUS" -eq 0 ] || lk_console_warning \
    "WARNING: because rsync failed to complete, database backups may only be \
useful for diagnostic purposes"

# If SOURCE_NAME is root, exclude databases already dumped in this batch,
# otherwise look up databases to dump based on the source owner's username
if [ "$SOURCE_NAME" = root ]; then
    shopt -s nullglob
    MYSQL_DUMP_ARGS=(--exclude)
    for FILE in "$BACKUP_ROOT/snapshot"/*/"$LK_BACKUP_TIMESTAMP/db"/*; do
        [[ ! $FILE =~ .*/([^/]+)-[0-9]{4}(-[0-9]{2}){2}-[0-9]{6}\.sql(\.[[:alnum:]]+){,2}$ ]] ||
            MYSQL_DUMP_ARGS+=("${BASH_REMATCH[1]}")
    done
else
    OWNER=$(lk_file_owner "$SOURCE") &&
        lk_mysql_mapfile MYSQL_DUMP_ARGS -h"${LK_MYSQL_HOST:-localhost}" \
            <<<"SHOW DATABASES LIKE '$(lk_mysql_escape_like "$OWNER")%'" || return

    if [ ${#MYSQL_DUMP_ARGS[@]} -gt 0 ]; then
        lk_echo_array MYSQL_DUMP_ARGS |
            lk_console_detail_list \
                "MySQL databases found for user '$OWNER':" database databases
    else
        lk_console_detail "No MySQL databases found for user '$OWNER'"
        return
    fi
fi

# Add the current time to each dump's file name to
# 1. simplify cataloguing, and
# 2. prevent overwriting if there are multiple attempts to create the same
#    snapshot (e.g. after an rsync failure)
LK_BACKUP_TIMESTAMP='' \
    "$LK_BASE/bin/lk-mysql-dump.sh" \
    --no-log \
    --dest "$LK_SNAPSHOT_DB_ROOT" \
    ${SNAPSHOT_GROUP:+--group "$SNAPSHOT_GROUP"} \
    "${MYSQL_DUMP_ARGS[@]}" || return
lk_console_message \
    "Running rsync again in case of filesystem changes since first rsync"
run_rsync || return

#!/bin/bash
# shellcheck disable=SC1091,SC2015,SC2029

function lk_safe_wp() {
    wp "$@" --skip-plugins --skip-themes
}

# lk_wp_db_config [wp_config_path]
#   Output DB_NAME, DB_USER, DB_PASSWORD and DB_HOST values configured in
#   wp-config.php as KEY="VALUE" pairs without calling `wp config`.
#   If not specified, WP_CONFIG_PATH is assumed to be "./wp-config.php".
function lk_wp_db_config() {
    local WP_CONFIG="${1:-wp-config.php}" PHP
    [ -e "$WP_CONFIG" ] || lk_warn "file not found: $WP_CONFIG" || return
    # 1. remove comments and whitespace from wp-config.php (php --strip)
    # 2. extract the relevant "define(...);" calls, one per line (grep -Po)
    # 3. add any missing semicolons (sed -E)
    # 4. add code to output each value as a shell expression (cat)
    # 5. run the code (php <<<"$PHP")
    PHP="$(
        echo '<?php'
        php --strip "$WP_CONFIG" |
            grep -Po "(?<=<\?php|;|^)\s*define\s*\(\s*(['\"])DB_(NAME|USER|PASSWORD|HOST)\1\s*,\s*('([^']+|\\\\')*'|\"([^\"\$]+|\\\\(\"|\\\$))*\")\s*\)\s*(;|\$)" |
            sed -E 's/[^;]$/&;/' || exit
        cat <<EOF
\$vals = array_map(function (\$v) { return addslashes(\$v); }, [DB_NAME, DB_USER, DB_PASSWORD, DB_HOST]);
printf("DB_NAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\nDB_HOST=%s\n", \$vals[0], \$vals[1], \$vals[2], \$vals[3]);
EOF
    )" || return
    php <<<"$PHP"
}

# _lk_get_my_cnf [user [password [host]]]
function _lk_get_my_cnf() {
    cat <<EOF
# Generated by ${FUNCNAME[1]:-${FUNCNAME[0]}}
[client]
user="$(lk_escape "${1:-$DB_USER}" "\\" '"')"
password="$(lk_escape "${2:-$DB_PASSWORD}" "\\" '"')"
host="$(lk_escape "${3:-${DB_HOST:-${LK_MYSQL_HOST:-localhost}}}" "\\" '"')"
EOF
}

# lk_wp_db_dump_remote ssh_host [remote_path]
function lk_wp_db_dump_remote() {
    local REMOTE_PATH="${2:-public_html}" WP_CONFIG DB_CONFIG \
        DB_NAME="${DB_NAME:-}" DB_USER="${DB_USER:-}" DB_PASSWORD="${DB_PASSWORD:-}" DB_HOST="${DB_HOST:-}" \
        OUTPUT_FILE EXIT_STATUS=0
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    [ ! -t 1 ] || [ -w "$PWD" ] || lk_warn "cannot write to current directory" || return
    [ -n "$DB_NAME" ] &&
        [ -n "$DB_USER" ] &&
        [ -n "$DB_PASSWORD" ] &&
        [ -n "$DB_HOST" ] || {
        REMOTE_PATH="${REMOTE_PATH%/}"
        lk_console_message "Getting credentials"
        lk_console_detail "Retrieving" "$1:$REMOTE_PATH/wp-config.php"
        WP_CONFIG="$(ssh "$1" cat "$REMOTE_PATH/wp-config.php")" || return
        lk_console_detail "Parsing WordPress configuration"
        DB_CONFIG="$(lk_wp_db_config <(echo "$WP_CONFIG"))" || return
        . /dev/stdin <<<"$DB_CONFIG" || return
    }
    lk_console_message "Creating temporary mysqldump configuration file"
    lk_console_detail "Adding credentials for user" "$DB_USER"
    lk_console_detail "Writing" "$1:.lk_mysqldump.cnf"
    _lk_get_my_cnf | ssh "$1" "bash -c 'cat >\".lk_mysqldump.cnf\"'" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE="./$DB_NAME-$1-$(lk_date_ymdhms).sql.gz"
        exec 6>&1 >"$OUTPUT_FILE"
    }
    lk_console_message "Dumping remote database"
    lk_console_detail "Database:" "$DB_NAME"
    lk_console_detail "Host:" "$DB_HOST"
    [ -z "${OUTPUT_FILE:-}" ] || lk_console_detail "Writing compressed SQL to" "$OUTPUT_FILE"
    ssh "$1" "bash -c 'mysqldump --defaults-file=\".lk_mysqldump.cnf\" --single-transaction --skip-lock-tables \"$DB_NAME\" | gzip; exit \"\${PIPESTATUS[0]}\"'" | pv || EXIT_STATUS="$?"
    [ -z "${OUTPUT_FILE:-}" ] || exec 1>&6 6>&-
    lk_console_message "Deleting mysqldump configuration file"
    ssh "$1" "bash -c 'rm -f \".lk_mysqldump.cnf\"'" &&
        lk_console_detail "Deleted" "$1:.lk_mysqldump.cnf" ||
        lk_console_error "Error deleting mysqldump configuration file"
    return "$EXIT_STATUS"
}

# lk_wp_db_restore_local sql_path [db_name [db_user]]
function lk_wp_db_restore_local() {
    local DB_CONFIG FILE_OWNER SQL EXIT_STATUS=0 \
        LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD LOCAL_DB_HOST="${LK_MYSQL_HOST:-localhost}" \
        DB_NAME DB_USER DB_PASSWORD DB_HOST \
        LK_MY_CNF="${LK_MY_CNF:-$HOME/.lk_mysql.cnf}"
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_item "Preparing to restore WordPress database from" "$1"
    DB_CONFIG="$(lk_wp_db_config)" || return
    . /dev/stdin <<<"$DB_CONFIG" || return
    FILE_OWNER="$(gnu_stat --printf '%U' "$1")" || return
    LOCAL_DB_NAME="${2-$FILE_OWNER}"              # 1. use FILE_OWNER unless specified
    LOCAL_DB_NAME="${LOCAL_DB_NAME:-$DB_NAME}"    # 2. if user value is "", replace with wp-config.php value
    LOCAL_DB_NAME="${LOCAL_DB_NAME:-$FILE_OWNER}" # 3. if wp-config.php value is "", use FILE_OWNER
    LOCAL_DB_USER="${3-$FILE_OWNER}"
    LOCAL_DB_USER="${LOCAL_DB_USER:-$DB_USER}"
    LOCAL_DB_USER="${LOCAL_DB_USER:-$FILE_OWNER}"
    LOCAL_DB_PASSWORD="$DB_PASSWORD"
    _lk_get_my_cnf \
        "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" \
        >"$LK_MY_CNF" || return
    mysql --defaults-file="$LK_MY_CNF" --execute="\\q" "$LOCAL_DB_NAME" 2>/dev/null || {
        LOCAL_DB_PASSWORD="$(openssl rand -base64 32)" &&
            _lk_get_my_cnf \
                "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" \
                >"$LK_MY_CNF"
    } || return
    SQL=(
        "DROP DATABASE IF EXISTS $LOCAL_DB_NAME"
        "CREATE DATABASE $LOCAL_DB_NAME"
        "GRANT ALL PRIVILEGES ON $LOCAL_DB_NAME.*
TO '$(lk_escape "$LOCAL_DB_USER" "\\" "'")'@'$(lk_escape "$LOCAL_DB_HOST" "\\" "'")'
IDENTIFIED BY @db_password"
    )
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_console_detail "DB_NAME will be updated to" "$LOCAL_DB_NAME"
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_console_detail "DB_USER will be updated to" "$LOCAL_DB_USER"
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_console_detail "DB_HOST will be updated to" "$LOCAL_DB_HOST"
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_console_detail "DB_PASSWORD will be reset"
    lk_console_detail "Local database will be reset with SQL commands" \
        "$(printf '%s;\n' "${SQL[@]}")"
    echo >&2
    if lk_confirm "All data in local database '$LOCAL_DB_NAME' will be permanently destroyed. Proceed?" N; then
        lk_console_message "Restoring WordPress database to local system"
        lk_console_detail "Checking wp-config.php"
        [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
            lk_safe_wp config set DB_NAME "$LOCAL_DB_NAME" --type=constant || return
        [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
            lk_safe_wp config set DB_USER "$LOCAL_DB_USER" --type=constant || return
        [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
            lk_safe_wp config set DB_HOST "$LOCAL_DB_HOST" --type=constant || return
        [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
            lk_safe_wp config set DB_PASSWORD "$LOCAL_DB_PASSWORD" --type=constant || return
        lk_console_detail "Preparing database" "$LOCAL_DB_NAME"
        printf '%s;\n' \
            "SET @db_password = '$(lk_escape "$LOCAL_DB_PASSWORD" "\\" "'")'" \
            "${SQL[@]}" |
            sudo mysql -uroot || return
        lk_console_detail "Restoring from" "$1"
        if [[ "$1" =~ \.gz(ip)?$ ]]; then
            pv "$1" | gunzip
        else
            pv "$1"
        fi | mysql --defaults-file="$LK_MY_CNF" "$LOCAL_DB_NAME" || EXIT_STATUS="$?"
        [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Database restored successfully" ||
            lk_console_message "Restore operation failed (exit status $EXIT_STATUS)" "$LK_BOLD$LK_RED"
        return "$EXIT_STATUS"
    fi
}

# lk_wp_file_sync_remote ssh_host [remote_path [local_path]]
function lk_wp_file_sync_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH="${3:-$HOME/public_html}" \
        ARGS=(-vrlptH -x --delete ${RSYNC_ARGS[@]+"${RSYNC_ARGS[@]}"}) EXIT_STATUS=0
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    lk_console_message "Preparing to sync WordPress files"
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    lk_console_detail "Source:" "$1:$REMOTE_PATH"
    lk_console_detail "Destination:" "$LOCAL_PATH"
    [ ! -f "$LOCAL_PATH/wp-config.php" ] || ARGS+=(--exclude="/wp-config.php")
    [ ! -d "$LOCAL_PATH/.git" ] || ARGS+=(--exclude="/.git")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    lk_console_detail "Local files will be overwritten with command" \
        "rsync ${ARGS[*]}"
    ! lk_confirm "Perform a trial run first?" Y ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_confirm "All local changes in '$LOCAL_PATH' will be permanently lost. Proceed?" N || return
    rsync "${ARGS[@]}" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Sync completed successfully" ||
        lk_console_message "Sync operation failed (exit status $EXIT_STATUS)" "$LK_BOLD$LK_RED"
    return "$EXIT_STATUS"
}

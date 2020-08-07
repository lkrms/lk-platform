#!/bin/bash
# shellcheck disable=SC1091,SC2015,SC2029,SC2207,SC2119,SC2120,SC2206

lk_bash_at_least 4 ||
    lk_warn "Bash version 4 or higher required" ||
    return

function lk_wp() {
    wp --skip-plugins --skip-themes "$@"
}

function lk_wp_get_site_root() {
    local SITE_ROOT
    SITE_ROOT="$(lk_wp eval "echo ABSPATH;" --skip-wordpress)" &&
        { [ "$SITE_ROOT" != "/" ] ||
            lk_warn "WordPress installation not found"; } &&
        echo "${SITE_ROOT%/}"
}

function lk_wp_get_site_address() {
    lk_wp option get home
}

function lk_wp_get_table_prefix() {
    lk_wp config get table_prefix
}

function _lk_wp_replace() {
    local TABLE_PREFIX SKIP_TABLES
    TABLE_PREFIX="$(lk_wp_get_table_prefix)" || return
    SKIP_TABLES=(
        "*_log"
        "*_logs"
        redirection_404

        # new Gravity Forms
        gf_form_view
        gf_draft_submissions
        gf_entry*

        # old Gravity Forms
        rg_form_view
        rg_incomplete_submissions
        rg_lead*
    )
    SKIP_TABLES=("${SKIP_TABLES[@]/#/$TABLE_PREFIX}")
    lk_console_detail "Replacing:" "$1 -> $2"
    "${LK_WP_REPLACE_COMMAND:-lk_wp}" search-replace "$1" "$2" --no-report \
        --all-tables-with-prefix \
        --skip-tables="$(lk_implode "," "${SKIP_TABLES[@]}")" \
        --skip-columns="guid"
}

function lk_wp_flush() {
    lk_console_detail "Flushing WordPress object cache"
    lk_wp cache flush
    lk_console_detail "Deleting transients"
    lk_wp transient delete --all
    lk_console_detail "Flushing rewrite rules"
    wp rewrite flush
    if wp cli has-command 'w3-total-cache flush'; then
        lk_console_detail "Flushing W3 Total Cache"
        wp w3-total-cache flush all
    fi
}

function lk_wp_url_encode() {
    php --run 'echo urlencode(trim(stream_get_contents(STDIN)));' <<<"$1"
}

function lk_wp_json_encode() {
    php --run 'echo substr(json_encode(trim(stream_get_contents(STDIN))), 1, -1);' <<<"$1"
}

# lk_wp_rename_site NEW_URL
#   Change the WordPress site address to NEW_URL.
#
# Environment variables:
#   LK_WP_OLD_URL=OLD_URL
#     Override `wp option get home`, e.g. to replace instances of OLD_URL in
#     database tables after changing the site address
#   LK_WP_REPLACE=<1|0|Y|N> (default: 1)
#     Perform URL replacement in database tables
#   LK_WP_REPLACE_WITHOUT_SCHEME=<1|0|Y|N> (default: 0)
#     Replace instances of the previous URL without a scheme component
#     ("http*://" or "//"), e.g. if renaming "http://domain.com" to
#     "https://new.domain.com", replace "domain.com" with "new.domain.com"
function lk_wp_rename_site() {
    local NEW_URL="${1:-}" OLD_URL="${LK_WP_OLD_URL:-}" \
        SITE_ROOT OLD_SITE_URL NEW_SITE_URL REPLACE DELIM=$'\t' IFS r s
    lk_is_uri "$NEW_URL" ||
        lk_warn "not a valid URL: $NEW_URL" || return
    [ -n "$OLD_URL" ] ||
        OLD_URL="$(lk_wp_get_site_address)" || return
    [ "$NEW_URL" != "$OLD_URL" ] ||
        lk_warn "site address not changed (set LK_WP_OLD_URL to override)" || return
    SITE_ROOT="$(lk_wp_get_site_root)" || return
    OLD_SITE_URL="$(lk_wp option get siteurl)" || return
    NEW_SITE_URL="$(lk_replace "$OLD_URL" "$NEW_URL" "$OLD_SITE_URL")"
    lk_console_item "Renaming WordPress installation at" "$SITE_ROOT"
    lk_console_detail "Site address:" "$OLD_URL -> $LK_BOLD$NEW_URL$LK_RESET"
    lk_console_detail "WordPress address:" "$OLD_SITE_URL -> $LK_BOLD$NEW_SITE_URL$LK_RESET"
    lk_no_input || lk_confirm "Proceed?" Y || return
    lk_wp option update home "$NEW_URL"
    lk_wp option update siteurl "$NEW_SITE_URL"
    if lk_is_true "${LK_WP_REPLACE:-1}" &&
        { lk_no_input || lk_confirm "Replace the previous URL in all tables?" Y; }; then
        lk_console_message "Performing WordPress search/replace"
        REPLACE=(
            "$OLD_URL$DELIM$NEW_URL"
            "${OLD_URL#http*:}$DELIM${NEW_URL#http*:}"
            "$(lk_wp_url_encode "$OLD_URL")$DELIM$(lk_wp_url_encode "$NEW_URL")"
            "$(lk_wp_url_encode "${OLD_URL#http*:}")$DELIM$(lk_wp_url_encode "${NEW_URL#http*:}")"
            "$(lk_wp_json_encode "$OLD_URL")$DELIM$(lk_wp_json_encode "$NEW_URL")"
            "$(lk_wp_json_encode "${OLD_URL#http*:}")$DELIM$(lk_wp_json_encode "${NEW_URL#http*:}")"
        )
        ! lk_is_true "${LK_WP_REPLACE_WITHOUT_SCHEME:-0}" ||
            REPLACE+=(
                "${OLD_URL#http*://}$DELIM${NEW_URL#http*://}"
                "$(lk_wp_url_encode "${OLD_URL#http*://}")$DELIM$(lk_wp_url_encode "${NEW_URL#http*://}")"
            )
        lk_remove_repeated REPLACE
        for r in "${REPLACE[@]}"; do
            IFS="$DELIM"
            s=($r)
            unset IFS
            _lk_wp_replace "${s[@]}"
        done
    fi
    if lk_no_input ||
        lk_confirm "\
OK to flush rewrite rules, caches and transients? \
Plugin code will be allowed to run." Y; then
        lk_wp_flush
    else
        lk_console_detail "To flush rewrite rules:" "wp rewrite flush"
        lk_console_detail "To flush everything:" "lk_wp_flush"
    fi
    lk_console_message "Site renamed successfully" "$LK_GREEN"
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
\$vals = array_map(function (\$v) { return escapeshellarg(\$v); }, [DB_NAME, DB_USER, DB_PASSWORD, DB_HOST]);
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

function _lk_write_my_cnf() {
    LK_MY_CNF="${LK_MY_CNF:-$HOME/.lk_mysql.cnf}"
    _lk_get_my_cnf "$@" >"$LK_MY_CNF"
}

function _lk_mysql() {
    [ -n "${LK_MY_CNF:-}" ] || lk_warn "LK_MY_CNF not set" || return
    [ -f "$LK_MY_CNF" ] || lk_warn "file not found: $LK_MY_CNF" || return
    mysql --defaults-file="$LK_MY_CNF" "$@"
}

function _lk_mysql_connects() {
    _lk_mysql --execute="\\q" ${1+"$1"}
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
        DB_CONFIG="$(lk_wp_db_config <<<"$WP_CONFIG")" || return
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
        lk_console_detail "Error deleting" "$1:.lk_mysqldump.cnf" "$LK_RED"
    [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Database dump completed successfully" "$LK_GREEN" ||
        lk_console_message "Database dump failed (exit status $EXIT_STATUS)" "$LK_RED"
    return "$EXIT_STATUS"
}

# lk_wp_db_restore_local sql_path [db_name [db_user]]
function lk_wp_db_restore_local() {
    local SITE_ROOT DEFAULT_IDENTIFIER SQL _SQL COMMAND EXIT_STATUS=0 \
        LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD \
        LOCAL_DB_HOST="${LK_MYSQL_HOST:-localhost}" \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    SITE_ROOT="$(lk_wp_get_site_root)" || return
    lk_console_message "Preparing to restore WordPress database"
    lk_console_detail "Backup file:" "$1"
    lk_console_detail "WordPress installation:" "$SITE_ROOT"
    DB_NAME="$(lk_wp config get DB_NAME)" &&
        DB_USER="$(lk_wp config get DB_USER)" &&
        DB_PASSWORD="$(lk_wp config get DB_PASSWORD)" &&
        DB_HOST="$(lk_wp config get DB_HOST)" &&
        _lk_write_my_cnf "$DB_USER" "$DB_PASSWORD" "$LOCAL_DB_HOST" || return
    LOCAL_DB_NAME="$DB_NAME"
    LOCAL_DB_USER="$DB_USER"
    LOCAL_DB_PASSWORD="$DB_PASSWORD"
    # keep existing credentials if they work
    _lk_mysql_connects "" 2>/dev/null || {
        if [[ "$SITE_ROOT" =~ ^/srv/www/([^./]+)/public_html$ ]]; then
            DEFAULT_IDENTIFIER="${BASH_REMATCH[1]}"
        elif [[ "$SITE_ROOT" =~ ^/srv/www/([^./]+)/([^./]+)/public_html$ ]]; then
            DEFAULT_IDENTIFIER="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"
        elif [[ "$SITE_ROOT" =~ ^/srv/http/([^./]+)\.localhost/(public_)?html$ ]]; then
            DEFAULT_IDENTIFIER="${BASH_REMATCH[1]}"
        elif [[ ! "$SITE_ROOT" =~ ^/srv/(www|http)(/.*)?$ ]] && [ "${SITE_ROOT:0:${#HOME}}" = "$HOME" ]; then
            DEFAULT_IDENTIFIER="$(basename "$SITE_ROOT")"
        else
            DEFAULT_IDENTIFIER="$(gnu_stat --printf '%U' "$SITE_ROOT")" || return
        fi
        LOCAL_DB_NAME="${2:-$DEFAULT_IDENTIFIER}"
        LOCAL_DB_USER="${3:-$DEFAULT_IDENTIFIER}"
        _lk_write_my_cnf "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        # try existing password with new DB_USER before changing DB_PASSWORD
        _lk_mysql_connects "" 2>/dev/null || {
            LOCAL_DB_PASSWORD="$(openssl rand -base64 32)" &&
                _lk_write_my_cnf "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST"
        } || return
    }
    SQL=(
        "DROP DATABASE IF EXISTS \`$LOCAL_DB_NAME\`"
        "CREATE DATABASE \`$LOCAL_DB_NAME\`"
    )
    _SQL="$(printf '%s;\n' "${SQL[@]}")"
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_console_detail "DB_NAME will be updated to" "$LOCAL_DB_NAME"
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_console_detail "DB_USER will be updated to" "$LOCAL_DB_USER"
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_console_detail "DB_HOST will be updated to" "$LOCAL_DB_HOST"
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_console_detail "DB_PASSWORD will be reset"
    lk_console_detail "Local database will be reset with:" "$_SQL"
    lk_no_input ||
        lk_confirm "All data in local database '$LOCAL_DB_NAME' will be permanently destroyed. Proceed?" Y || return
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] || {
        COMMAND=(lk_elevate "$LK_BASE/bin/lk-mysql-grant.sh"
            "$LOCAL_DB_NAME" "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD")
        [[ "$USER" =~ ^[a-zA-Z0-9_]+$ ]] && [[ "$LOCAL_DB_NAME" =~ ^$USER(_[a-zA-Z0-9_]*)?$ ]] ||
            unset "COMMAND[0]"
        "${COMMAND[@]}" || return
    }
    lk_console_message "Restoring WordPress database to local system"
    lk_console_detail "Checking wp-config.php"
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_wp config set DB_NAME "$LOCAL_DB_NAME" --type=constant --quiet || return
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_wp config set DB_USER "$LOCAL_DB_USER" --type=constant --quiet || return
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_wp config set DB_HOST "$LOCAL_DB_HOST" --type=constant --quiet || return
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_wp config set DB_PASSWORD "$LOCAL_DB_PASSWORD" --type=constant --quiet || return
    lk_console_detail "Preparing database" "$LOCAL_DB_NAME"
    echo "$_SQL" | _lk_mysql || return
    lk_console_detail "Restoring from" "$1"
    if [[ "$1" =~ \.gz(ip)?$ ]]; then
        pv "$1" | gunzip
    else
        pv "$1"
    fi | _lk_mysql "$LOCAL_DB_NAME" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Database restored successfully" "$LK_GREEN" ||
        lk_console_message "Restore operation failed (exit status $EXIT_STATUS)" "$LK_RED"
    return "$EXIT_STATUS"
}

# lk_wp_sync_files_from_remote ssh_host [remote_path [local_path]]
function lk_wp_sync_files_from_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH \
        ARGS=(-vrlptH -x --delete ${RSYNC_ARGS[@]+"${RSYNC_ARGS[@]}"}) \
        KEEP_LOCAL EXCLUDE EXIT_STATUS=0
    # files that already exist on the local system will be added to --exclude
    KEEP_LOCAL=(
        "wp-config.php"
        ".git"
        ${LK_WP_SYNC_KEEP_LOCAL[@]+"${LK_WP_SYNC_KEEP_LOCAL[@]}"}
    )
    EXCLUDE=(
        "/.maintenance"
        "/*.code-workspace"
        "/.vscode"
        ${LK_WP_SYNC_EXCLUDE[@]+"${LK_WP_SYNC_EXCLUDE[@]}"}
    )
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    LOCAL_PATH="${3:-$(lk_wp_get_site_root 2>/dev/null)}" ||
        LOCAL_PATH="$HOME/public_html"
    lk_console_message "Preparing to sync WordPress files"
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    lk_console_detail "Source:" "$1:$REMOTE_PATH"
    lk_console_detail "Destination:" "$LOCAL_PATH"
    for FILE in "${KEEP_LOCAL[@]}"; do
        [ ! -e "$LOCAL_PATH/$FILE" ] || EXCLUDE+=("/$FILE")
    done
    ARGS+=("${EXCLUDE[@]/#/--exclude=}")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    lk_console_detail "Local files will be overwritten with command" \
        "rsync ${ARGS[*]}"
    lk_no_input || ! lk_confirm "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_no_input ||
        lk_confirm "LOCAL CHANGES WILL BE PERMANENTLY LOST. Proceed?" Y ||
        return
    [ -d "$LOCAL_PATH" ] || mkdir -p "$LOCAL_PATH" || return
    rsync "${ARGS[@]}" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq "0" ] &&
        lk_console_message "Sync completed successfully" \
            "$LK_GREEN" ||
        lk_console_message "Sync operation failed (exit status $EXIT_STATUS)" \
            "$LK_RED"
    return "$EXIT_STATUS"
}

function _lk_wp_get_cron_path() {
    local WP_CRON_PATH
    lk_command_exists crontab || lk_warn "crontab required" || return
    WP_CRON_PATH="$(lk_wp_get_site_root)/wp-cron.php" || return
    [ -f "$WP_CRON_PATH" ] || lk_warn "file not found: $WP_CRON_PATH" || return
    echo "$WP_CRON_PATH"
}

# lk_wp_enable_system_cron [interval_minutes]
function lk_wp_enable_system_cron() {
    local INTERVAL="${1:-5}" WP_CRON_PATH CRON_COMMAND CRONTAB
    WP_CRON_PATH="$(_lk_wp_get_cron_path)" || return
    lk_console_item "Scheduling with crontab:" "$WP_CRON_PATH"
    lk_console_detail "Setting DISABLE_WP_CRON in wp-config.php"
    lk_wp config set DISABLE_WP_CRON true --type=constant --raw --quiet || return
    CRON_COMMAND="$(type -P php) $WP_CRON_PATH"
    [ "$INTERVAL" -lt "60" ] &&
        CRON_COMMAND="*/$INTERVAL * * * * $CRON_COMMAND" ||
        CRON_COMMAND="0 1 * * * $CRON_COMMAND"
    lk_console_detail "Adding cron job:" "$CRON_COMMAND"
    CRONTAB="$(crontab -l 2>/dev/null |
        sed -E "/ $(lk_escape_ere "$WP_CRON_PATH")\$/d")" || CRONTAB=
    {
        [ -z "$CRONTAB" ] || echo "$CRONTAB"
        echo "$CRON_COMMAND"
    } | crontab -
}

# lk_wp_disable_cron
function lk_wp_disable_cron() {
    local WP_CRON_PATH CRON_COMMAND CRONTAB
    WP_CRON_PATH="$(_lk_wp_get_cron_path)" || return
    lk_console_item "Disabling:" "$WP_CRON_PATH"
    lk_console_detail "Setting DISABLE_WP_CRON in wp-config.php"
    lk_wp config set DISABLE_WP_CRON true --type=constant --raw --quiet || return
    if CRON_COMMAND="$({ crontab -l 2>/dev/null || true; } |
        grep -E " $(lk_escape_ere "$WP_CRON_PATH")\$")"; then
        lk_console_detail "Removing from crontab:" "$CRON_COMMAND"
        CRONTAB="$(crontab -l 2>/dev/null |
            grep -Ev " $(lk_escape_ere "$WP_CRON_PATH")\$")" || CRONTAB=
        if [ -n "$CRONTAB" ]; then
            crontab - <<<"$CRONTAB"
        else
            crontab -r 2>/dev/null || true
        fi
    fi
}

# lk_wp_set_permissions [SITE_ROOT]
function lk_wp_set_permissions() {
    local SITE_ROOT OWNER \
        LK_DIR_MODE="${LK_DIR_MODE:-0750}" \
        LK_FILE_MODE="${LK_FILE_MODE:-0640}" \
        LK_WRITABLE_DIR_MODE="${LK_WRITABLE_DIR_MODE:-2770}" \
        LK_WRITABLE_FILE_MODE="${LK_WRITABLE_FILE_MODE:-0660}"
    SITE_ROOT="${1:-$(lk_wp_get_site_root)}" &&
        SITE_ROOT="$(realpath "$SITE_ROOT")" &&
        OWNER="$(gnu_stat --printf '%U' "$SITE_ROOT/..")" || return
    lk_dir_set_permissions \
        "$SITE_ROOT" \
        ".*/wp-content/(cache|uploads|w3tc-config)" \
        "$OWNER:"
}

# [LOCAL_DB_NAME=db_name] [LOCAL_DB_USER=db_user] \
#   lk_wp_migrate_remote ssh_host [remote_path local_path [exclude_pattern...]]
function lk_wp_migrate_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH="${3:-$HOME/public_html}" \
        EXCLUDE=("${@:4}") LOCAL_DB_NAME="${LOCAL_DB_NAME:-$USER}" \
        RSYNC_ARGS DB_FILE MAINTENANCE='<?php $upgrading = time(); ?>'
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    [ -d "$LOCAL_PATH" ] || lk_warn "not a local directory: $LOCAL_PATH"

    lk_console_message "Enabling maintenance mode"
    lk_console_detail "Creating" "$LOCAL_PATH/.maintenance"
    echo -n "$MAINTENANCE" >"$LOCAL_PATH/.maintenance" || return
    lk_console_detail \
        "If this is the final sync before DNS cutover, maintenance mode should be
enabled on the remote site"
    lk_console_detail \
        "To minimise downtime, complete an initial sync without enabling
maintenance mode, then sync again"
    if lk_confirm "Enable maintenance mode on remote site?" N; then
        lk_console_detail "Creating" "$1:$REMOTE_PATH/.maintenance"
        ssh "$1" \
            "bash -c 'echo -n \"\$1\" >\"\$2/.maintenance\"'" "bash" \
            "$MAINTENANCE" "$REMOTE_PATH" || return
    fi

    # migrate files
    RSYNC_ARGS=(${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"})
    lk_wp_sync_files_from_remote "$1" "$REMOTE_PATH" "$LOCAL_PATH" || return

    # migrate database
    DB_FILE=~/"$1-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz"
    lk_wp_db_dump_remote "$1" "$REMOTE_PATH" >"$DB_FILE" &&
        cd "$LOCAL_PATH" &&
        lk_wp_db_restore_local "$DB_FILE" \
            "$LOCAL_DB_NAME" "${LOCAL_DB_USER:-$LOCAL_DB_NAME}" &&
        lk_wp_flush || return

    lk_console_message "Disabling maintenance mode (local only)"
    rm "$LOCAL_PATH/.maintenance" || {
        lk_console_error "Error deleting $LOCAL_PATH/.maintenance
Maintenance mode may have been disabled early by another process"
        return 1
    }

    lk_console_message "Migration completed successfully" "$LK_GREEN"
}

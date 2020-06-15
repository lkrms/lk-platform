#!/bin/bash
# shellcheck disable=SC1091,SC2015,SC2029,SC2207,SC2119,SC2120

function lk_wp() {
    wp --skip-plugins --skip-themes "$@"
}

function lk_wp_replace() {
    local TABLE_PREFIX SKIP_TABLES
    TABLE_PREFIX="$(lk_wp config get table_prefix)" || return
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
    lk_console_message "Running WordPress search/replace command"
    lk_console_detail "Searching for" "$1"
    lk_console_detail "Replacing with" "$2"
    "${LK_WP_REPLACE_COMMAND:-lk_wp}" search-replace "$1" "$2" --no-report \
        --all-tables-with-prefix \
        --skip-tables="$(lk_implode "," "${SKIP_TABLES[@]}")" \
        --skip-columns="guid"
}

# lk_wp_rename_site new_url
function lk_wp_rename_site() {
    local NEW_URL="${1:-}" OLD_URL="${OLD_URL:-}"
    lk_is_uri "$NEW_URL" ||
        lk_warn "not a valid URL: $NEW_URL" || return
    [ -n "$OLD_URL" ] ||
        OLD_URL="$(lk_wp option get siteurl)" || return
    [ "$NEW_URL" != "$OLD_URL" ] ||
        lk_warn "site URL not changed (set OLD_URL to override)" || return
    lk_console_item "Setting site URL to" "$NEW_URL"
    lk_console_detail "Previous site URL:" "$OLD_URL"
    lk_no_input || lk_confirm "Proceed?" Y || return
    lk_wp option update siteurl "$NEW_URL"
    lk_wp option update home "$NEW_URL"
    if lk_is_false "${LK_WP_NO_REPLACE:-0}" &&
        { lk_no_input || lk_confirm "Search and replace the previous URL in all tables?" Y; }; then
        lk_wp_replace "$OLD_URL" "$NEW_URL"
        lk_wp_replace "${OLD_URL#http*:}" "${NEW_URL#http*:}"
        lk_wp_replace "$(echo "$OLD_URL" | php -r 'echo urlencode(trim(fgets(STDIN)));')" \
            "$(echo "$NEW_URL" | php -r 'echo urlencode(trim(fgets(STDIN)));')"
        lk_wp_replace "$(echo "${OLD_URL#http*:}" | php -r 'echo urlencode(trim(fgets(STDIN)));')" \
            "$(echo "${NEW_URL#http*:}" | php -r 'echo urlencode(trim(fgets(STDIN)));')"
        lk_wp_replace "$(echo "$OLD_URL" | php -r 'echo substr(json_encode(trim(fgets(STDIN))), 1, -1);')" \
            "$(echo "$NEW_URL" | php -r 'echo substr(json_encode(trim(fgets(STDIN))), 1, -1);')"
        lk_wp_replace "$(echo "${OLD_URL#http*://}" | php -r 'echo urlencode(trim(fgets(STDIN)));')" \
            "$(echo "${NEW_URL#http*://}" | php -r 'echo urlencode(trim(fgets(STDIN)));')"
        [ "${OLD_URL#http*://}" = "$(
            echo "${OLD_URL#http*://}" |
                php -r 'echo urlencode(trim(fgets(STDIN)));'
        )" ] && [ "${NEW_URL#http*://}" = "$(
            echo "${NEW_URL#http*://}" |
                php -r 'echo urlencode(trim(fgets(STDIN)));'
        )" ] ||
            lk_wp_replace "${OLD_URL#http*://}" "${NEW_URL#http*://}"
    fi
    lk_no_input ||
        lk_confirm "OK to flush rewrite rules? Plugin code will be allowed to run." Y || {
        lk_console_detail "To flush rewrite rules manually:" "wp rewrite flush"
        return
    }
    wp rewrite flush
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

function _lk_mysql_privileged() {
    local LK_MYSQL_USERNAME="${LK_MYSQL_USERNAME-root}"
    lk_can_sudo &&
        sudo -H mysql ${LK_MYSQL_USERNAME+-u"$LK_MYSQL_USERNAME"} "$@"
}

function _lk_mysql_connects() {
    _lk_mysql --execute="\\q" "${1:-$DB_NAME}"
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
        lk_console_detail "Error deleting" "$1:.lk_mysqldump.cnf" "$LK_RED"
    [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Database dump completed successfully" "$LK_GREEN" ||
        lk_console_message "Database dump failed (exit status $EXIT_STATUS)" "$LK_RED"
    return "$EXIT_STATUS"
}

# lk_wp_db_restore_local sql_path [db_name [db_user]]
function lk_wp_db_restore_local() {
    local FILE_OWNER SQL _SQL EXIT_STATUS=0 \
        LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD \
        LOCAL_DB_HOST="${LK_MYSQL_HOST:-localhost}" \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_item "Preparing to restore from" "$1"
    DB_NAME="$(lk_wp config get DB_NAME)" &&
        DB_USER="$(lk_wp config get DB_USER)" &&
        DB_PASSWORD="$(lk_wp config get DB_PASSWORD)" &&
        DB_HOST="$(lk_wp config get DB_HOST)" &&
        _lk_write_my_cnf "$DB_USER" "$DB_PASSWORD" "$LOCAL_DB_HOST" || return
    LOCAL_DB_NAME="$DB_NAME"
    LOCAL_DB_USER="$DB_USER"
    LOCAL_DB_PASSWORD="$DB_PASSWORD"
    # keep existing credentials if they work
    _lk_mysql_connects 2>/dev/null || {
        FILE_OWNER="$(gnu_stat --printf '%U' "$1")" || return
        LOCAL_DB_NAME="${2:-$FILE_OWNER}"
        LOCAL_DB_USER="${3:-$FILE_OWNER}"
        _lk_write_my_cnf "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        # try existing password with new DB_NAME and DB_USER before changing DB_PASSWORD
        _lk_mysql_connects "$LOCAL_DB_NAME" 2>/dev/null || {
            LOCAL_DB_PASSWORD="$(openssl rand -base64 32)" &&
                _lk_write_my_cnf "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST"
        } || return
    }
    SQL=(
        "DROP DATABASE IF EXISTS $LOCAL_DB_NAME"
        "CREATE DATABASE $LOCAL_DB_NAME"
    )
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        SQL+=(
            "GRANT ALL PRIVILEGES ON $LOCAL_DB_NAME.* \
TO '$(lk_escape "$LOCAL_DB_USER" "\\" "'")'@'$(lk_escape "$LOCAL_DB_HOST" "\\" "'")' \
IDENTIFIED BY {{DB_PASSWORD}}"
        )
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_console_detail "DB_NAME will be updated to" "$LOCAL_DB_NAME"
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_console_detail "DB_USER will be updated to" "$LOCAL_DB_USER"
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_console_detail "DB_HOST will be updated to" "$LOCAL_DB_HOST"
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_console_detail "DB_PASSWORD will be reset"
    lk_console_detail "Local database will be reset with:" \
        "$(printf '%s;\n' "${SQL[@]}" |
            lk_replace '{{DB_PASSWORD}}' "'<random>'")"
    lk_no_input ||
        lk_confirm "All data in local database '$LOCAL_DB_NAME' will be permanently destroyed. Proceed?" Y || return
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
    _SQL="$(printf '%s;\n' "${SQL[@]}" |
        lk_replace '{{DB_PASSWORD}}' "'$(lk_escape "$LOCAL_DB_PASSWORD" "\\" "'")'")" || return
    echo "$_SQL" | _lk_mysql_privileged ||
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

function lk_wp_reset_local() {
    local SITE_URL ADMIN_EMAIL TO_DEACTIVATE \
        DB_NAME DB_USER DB_PASSWORD DB_HOST TABLE_PREFIX \
        ACTIVE_PLUGINS DEACTIVATE_PLUGINS=(
            # /wp-admin blockers
            hide_my_wp
            wordfence
            wp-admin-no-show

            # caching
            w3-total-cache
            wp-rocket

            #
            zopim-live-chat
        )

    DB_NAME="$(lk_wp config get DB_NAME)" &&
        DB_USER="$(lk_wp config get DB_USER)" &&
        DB_PASSWORD="$(lk_wp config get DB_PASSWORD)" &&
        DB_HOST="$(lk_wp config get DB_HOST)" &&
        TABLE_PREFIX="$(lk_wp config get table_prefix)" &&
        _lk_write_my_cnf &&
        _lk_mysql_connects &&
        SITE_URL="$(lk_wp option get siteurl)" || return
    SITE_URL="${SITE_URL#http*://}"
    lk_no_input ||
        lk_confirm "Reset local instance of '$SITE_URL' for development?" Y || return
    lk_console_item "Configuring WordPress in" "$PWD"
    ADMIN_EMAIL="${SITE_URL#www.}"
    ADMIN_EMAIL="$USER@${ADMIN_EMAIL%%.*}.localhost"
    lk_console_detail "Resetting admin email addresses to" "$ADMIN_EMAIL"
    lk_console_detail "Anonymizing email addresses for other users"
    _lk_mysql "$DB_NAME" <<SQL || return
UPDATE ${TABLE_PREFIX}options
SET option_value = '$ADMIN_EMAIL'
WHERE option_name IN ('admin_email', 'woocommerce_email_from_address', 'woocommerce_stock_email_recipient');

DELETE
FROM ${TABLE_PREFIX}options
WHERE option_name = 'new_admin_email';

UPDATE ${TABLE_PREFIX}users
SET user_email = CONCAT (
        SUBSTRING_INDEX(user_email, '@', 1)
        ,'_'
        ,ID
        ,'@${SITE_URL%%.*}.localhost'
        )
WHERE ID <> 1;
SQL
    lk_wp user update 1 --user_email="$ADMIN_EMAIL" --skip-email &&
        lk_wp user meta update 1 billing_email "$ADMIN_EMAIL" || return
    ACTIVE_PLUGINS=($(lk_wp plugin list --status=active --field=name)) &&
        TO_DEACTIVATE=($(comm -12 <(printf '%s\n' ${ACTIVE_PLUGINS[@]+"${ACTIVE_PLUGINS[@]}"} | sort | uniq) <(printf '%s\n' "${DEACTIVATE_PLUGINS[@]}" | sort | uniq))) || return
    if [ "${#TO_DEACTIVATE[@]}" -gt "0" ]; then
        lk_console_detail "Disabling ${#TO_DEACTIVATE[@]} $(lk_maybe_plural "${#TO_DEACTIVATE[@]}" plugin plugins) known to disrupt local development:" "$(lk_echo_array "${TO_DEACTIVATE[@]}")"$'\n'
        lk_wp plugin deactivate "${TO_DEACTIVATE[@]}" || return
    fi
    if lk_wp config has WP_CACHE --type=constant; then
        lk_console_detail "Disabling caching"
        lk_wp config set WP_CACHE false --type=constant --raw || return
    fi
    lk_console_detail "Disabling all email sending"
    if ! lk_wp plugin is-installed wp-mail-smtp; then
        lk_wp plugin install wp-mail-smtp --activate || return
    else
        lk_wp plugin is-active wp-mail-smtp ||
            lk_wp plugin activate wp-mail-smtp || return
    fi
    lk_wp option patch insert wp_mail_smtp general '{
  "do_not_send": true,
  "am_notifications_hidden": false,
  "uninstall": false
}' --format=json
    if lk_wp plugin is-installed coming-soon; then
        lk_console_detail "Disabling maintenance mode"
        lk_wp option patch update seed_csp4_settings_content status 0
    fi
    if lk_wp plugin is-active woocommerce; then
        ACTIVE_PLUGINS=($(lk_wp plugin list --status=active --field=name)) || return
        lk_console_message "Plugin code will be allowed to run while final changes are applied"
        lk_no_input || lk_confirm "Proceed?" Y || return
        lk_console_detail "WooCommerce: disabling live payments for known gateways"
        lk_wp option patch update woocommerce_paypal_settings testmode yes || return
        if lk_wp plugin is-active woocommerce-gateway-stripe; then
            lk_wp option patch update woocommerce_stripe_settings testmode yes || return
        fi
        if wp cli has-command 'wc webhook list'; then
            TO_DEACTIVATE=($(wp wc webhook list --user=1 --field=id --status=active)) || return
            [ "${#TO_DEACTIVATE[@]}" -eq "0" ] || {
                lk_console_detail "WooCommerce: deleting active webhooks"
                for WEBHOOK_ID in "${TO_DEACTIVATE[@]}"; do
                    # TODO: deactivate instead?
                    wp wc webhook delete "$WEBHOOK_ID" --user=1 --force=true || return
                done
            }
        fi
    fi
    lk_console_message "Local instance of '$SITE_URL' successfully reset for development" "$LK_GREEN"
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
    lk_no_input || ! lk_confirm "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_no_input || lk_confirm "All local changes in '$LOCAL_PATH' will be permanently lost. Proceed?" N || return
    rsync "${ARGS[@]}" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq "0" ] && lk_console_message "Sync completed successfully" "$LK_GREEN" ||
        lk_console_message "Sync operation failed (exit status $EXIT_STATUS)" "$LK_RED"
    return "$EXIT_STATUS"
}

# lk_wp_use_cron [interval_minutes]
function lk_wp_use_cron() {
    local INTERVAL="${1:-15}" WP_CRON_PATH CRON_COMMAND CRONTAB
    lk_command_exists crontab || lk_warn "crontab required" || return
    WP_CRON_PATH="$(lk_wp eval "echo ABSPATH;")wp-cron.php" || return
    [ -f "$WP_CRON_PATH" ] || lk_warn "file not found: $WP_CRON_PATH" || return
    lk_console_item "Scheduling with crontab:" "$WP_CRON_PATH"
    lk_console_detail "Setting DISABLE_WP_CRON in wp-config.php"
    lk_wp config set DISABLE_WP_CRON true --type=constant --raw || return
    CRON_COMMAND="$(command -v php) $WP_CRON_PATH"
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

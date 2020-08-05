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
    lk_console_message "Running WordPress search/replace command"
    lk_console_detail "Searching for" "$1"
    lk_console_detail "Replacing with" "$2"
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

# [LK_WP_OLD_URL=old_url] lk_wp_rename_site new_url
function lk_wp_rename_site() {
    local NEW_URL="${1:-}" OLD_URL="${LK_WP_OLD_URL:-}" \
        REPLACE DELIM=$'\t' IFS r s
    lk_is_uri "$NEW_URL" ||
        lk_warn "not a valid URL: $NEW_URL" || return
    [ -n "$OLD_URL" ] ||
        OLD_URL="$(lk_wp option get siteurl)" || return
    [ "$NEW_URL" != "$OLD_URL" ] ||
        lk_warn "site URL not changed (set LK_WP_OLD_URL to override)" || return
    lk_console_item "Setting site URL to" "$NEW_URL"
    lk_console_detail "Previous site URL:" "$OLD_URL"
    lk_no_input || lk_confirm "Proceed?" Y || return
    lk_wp option update siteurl "$NEW_URL"
    lk_wp option update home "$NEW_URL"
    if lk_is_false "${LK_WP_NO_REPLACE:-0}" &&
        { lk_no_input || lk_confirm "Replace the previous URL in all tables?" Y; }; then
        REPLACE=(
            "$OLD_URL$DELIM$NEW_URL"
            "${OLD_URL#http*:}$DELIM${NEW_URL#http*:}"
            "$(lk_wp_url_encode "$OLD_URL")$DELIM$(lk_wp_url_encode "$NEW_URL")"
            "$(lk_wp_url_encode "${OLD_URL#http*:}")$DELIM$(lk_wp_url_encode "${NEW_URL#http*:}")"
            "$(lk_wp_json_encode "$OLD_URL")$DELIM$(lk_wp_json_encode "$NEW_URL")"
            "$(lk_wp_json_encode "${OLD_URL#http*:}")$DELIM$(lk_wp_json_encode "${NEW_URL#http*:}")"
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
    lk_console_item "Preparing to restore WordPress database"
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
    _lk_mysql_connects 2>/dev/null || {
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
        # try existing password with new DB_NAME and DB_USER before changing DB_PASSWORD
        _lk_mysql_connects "$LOCAL_DB_NAME" 2>/dev/null || {
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

function lk_wp_reset_local() {
    local DB_NAME DB_USER DB_PASSWORD DB_HOST TABLE_PREFIX SITE_URL _HOST \
        DOMAIN SITE_ROOT ACTIVE_PLUGINS TO_DEACTIVATE ADMIN_EMAIL \
        PLUGIN_CODE DEACTIVATE_PLUGINS=(
            #
            hide_my_wp
            wordfence
            wp-admin-no-show

            #
            all-in-one-redirection

            #
            w3-total-cache
            wp-rocket

            #
            zopim-live-chat
        )

    lk_console_message "Checking WordPress"
    DB_NAME="$(lk_wp config get DB_NAME)" &&
        DB_USER="$(lk_wp config get DB_USER)" &&
        DB_PASSWORD="$(lk_wp config get DB_PASSWORD)" &&
        DB_HOST="$(lk_wp config get DB_HOST)" &&
        TABLE_PREFIX="$(lk_wp_get_table_prefix)" &&
        _lk_write_my_cnf &&
        _lk_mysql_connects &&
        SITE_URL="$(lk_wp option get siteurl)" &&
        _HOST="$(lk_uri_parts "$SITE_URL" "_HOST")" &&
        eval "$_HOST" &&
        DOMAIN="$(
            sed -E 's/^(www[^.]*|local|staging)\.(.+)$/\2/' <<<"$_HOST"
        )" &&
        SITE_ROOT="$(lk_wp eval "echo ABSPATH;")" &&
        ACTIVE_PLUGINS=($(lk_wp plugin list --status=active --field=name)) &&
        TO_DEACTIVATE=($(
            [ "${#ACTIVE_PLUGINS[@]}" -eq "0" ] ||
                [ "${#DEACTIVATE_PLUGINS[@]}" -eq "0" ] ||
                comm -12 \
                    <(printf '%s\n' "${ACTIVE_PLUGINS[@]}" | sort | uniq) \
                    <(printf '%s\n' "${DEACTIVATE_PLUGINS[@]}" | sort | uniq)
        )) || return
    [ -n "$DOMAIN" ] || DOMAIN="$_HOST"
    ADMIN_EMAIL="admin@$DOMAIN"
    lk_console_detail "Site URL:" "$SITE_URL"
    lk_console_detail "Domain:" "$DOMAIN"
    lk_console_detail "Installed at:" "$SITE_ROOT"
    [ "${#ACTIVE_PLUGINS[@]}" -eq "0" ] &&
        lk_console_detail "Active plugins:" "<none>" ||
        lk_echo_array "${ACTIVE_PLUGINS[@]}" |
        lk_console_detail_list "Active $(
            lk_maybe_plural "${#ACTIVE_PLUGINS[@]}" \
                "plugin" "plugins (${#ACTIVE_PLUGINS[@]})"
        ):"
    lk_console_message \
        "Preparing to reset for local development"
    lk_console_detail "Salts in wp-config.php will be refreshed"
    lk_console_detail "Admin email address will be updated to:" "$ADMIN_EMAIL"
    lk_console_detail "User addresses will be updated to:" "user_<ID>@$DOMAIN"
    [ "${#TO_DEACTIVATE[@]}" -eq "0" ] ||
        lk_echo_array "${TO_DEACTIVATE[@]}" |
        lk_console_detail_list "Production-only $(
            lk_maybe_plural "${#TO_DEACTIVATE[@]}" \
                "plugin" "plugins"
        ) will be deactivated:"
    ! lk_wp config has WP_CACHE --type=constant ||
        lk_console_detail \
            "WP_CACHE in wp-config.php will be set to:" "false"
    lk_console_detail \
        "wp-mail-smtp will be configured to disable outgoing email"
    if lk_wp plugin is-active woocommerce; then
        PLUGIN_CODE=1
        printf '%s\n' \
            "PayPal" \
            "Stripe" |
            lk_console_detail_list \
                "Test mode will be enabled for known WooCommerce gateways:"
        lk_console_detail "Active WooCommerce webhooks will be deleted"
    fi
    [ "${PLUGIN_CODE:-0}" -eq "0" ] || lk_console_warning \
        "Plugin code will be allowed to run where necessary"

    lk_no_input ||
        lk_confirm "Proceed?" Y || return

    lk_console_message "Resetting WordPress for local development"
    lk_console_detail "Refreshing salts defined in wp-config.php"
    lk_wp config shuffle-salts || return
    lk_console_detail "Updating email addresses"
    _lk_mysql "$DB_NAME" <<SQL || return
UPDATE ${TABLE_PREFIX}options
SET option_value = '$ADMIN_EMAIL'
WHERE option_name IN ('admin_email', 'woocommerce_email_from_address', 'woocommerce_stock_email_recipient');

DELETE
FROM ${TABLE_PREFIX}options
WHERE option_name = 'new_admin_email';

UPDATE ${TABLE_PREFIX}users
SET user_email = CONCAT (
        'user_'
        ,ID
        ,'@$DOMAIN'
        )
WHERE ID <> 1;
SQL
    lk_wp user update 1 --user_email="$ADMIN_EMAIL" --skip-email &&
        lk_wp user meta update 1 billing_email "$ADMIN_EMAIL" || return
    if [ "${#TO_DEACTIVATE[@]}" -gt "0" ]; then
        lk_echo_array "${TO_DEACTIVATE[@]}" |
            lk_console_detail_list \
                "Deactivating ${#TO_DEACTIVATE[@]} $(
                    lk_maybe_plural "${#TO_DEACTIVATE[@]}" plugin plugins
                ):"
        lk_wp plugin deactivate "${TO_DEACTIVATE[@]}" || return
    fi
    if lk_wp config has WP_CACHE --type=constant; then
        lk_console_detail "Setting value of WP_CACHE in wp-config.php"
        lk_wp config set WP_CACHE false --type=constant --raw || return
    fi
    lk_console_detail "Checking that wp-mail-smtp is installed and enabled"
    if ! lk_wp plugin is-installed wp-mail-smtp; then
        lk_wp plugin install wp-mail-smtp --activate || return
    else
        lk_wp plugin is-active wp-mail-smtp ||
            lk_wp plugin activate wp-mail-smtp || return
    fi
    lk_console_detail "Disabling outgoing email"
    lk_wp option patch insert wp_mail_smtp general '{
  "do_not_send": true,
  "am_notifications_hidden": false,
  "uninstall": false
}' --format=json || return
    if lk_wp plugin is-active woocommerce; then
        lk_console_detail \
            "WooCommerce: disabling live payments for known gateways"
        lk_wp option patch update \
            woocommerce_paypal_settings testmode yes || return
        if lk_wp plugin is-active woocommerce-gateway-stripe; then
            lk_wp option patch update \
                woocommerce_stripe_settings testmode yes || return
        fi
        if wp cli has-command 'wc webhook list'; then
            TO_DEACTIVATE=($(
                wp wc webhook list --user=1 --field=id --status=active
            )) || return
            [ "${#TO_DEACTIVATE[@]}" -eq "0" ] || {
                lk_console_detail "WooCommerce: deleting active webhooks"
                for WEBHOOK_ID in "${TO_DEACTIVATE[@]}"; do
                    # TODO: deactivate instead?
                    wp wc webhook delete "$WEBHOOK_ID" --user=1 --force=true ||
                        return
                done
            }
        fi
    fi
    lk_wp_flush
    lk_console_message "WordPress successfully reset for local development" "$LK_GREEN"
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
    for FILE in "wp-config.php" ".git" ".vscode"; do
        [ ! -e "$LOCAL_PATH/$FILE" ] || ARGS+=(--exclude="$FILE")
    done
    # TODO: move standard exclusions to a file
    ARGS+=(--exclude="/.maintenance" --exclude="/*.code-workspace")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    lk_console_detail "Local files will be overwritten with command" \
        "rsync ${ARGS[*]}"
    lk_no_input || ! lk_confirm "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_no_input || lk_confirm "ALL LOCAL CHANGES IN '$LOCAL_PATH' WILL BE PERMANENTLY LOST. Proceed?" Y || return
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

# lk_wp_fix_permissions [local_path]
function lk_wp_fix_permissions() {
    local LOCAL_PATH LOG_DIR OWNER WRITABLE TYPE MODE ARGS \
        SUDO_OR_NOT="${SUDO_OR_NOT:-0}" \
        DIR_MODE="${DIR_MODE:-0750}" \
        FILE_MODE="${FILE_MODE:-0640}" \
        WRITABLE_DIR_MODE="${WRITABLE_DIR_MODE:-2770}" \
        WRITABLE_FILE_MODE="${WRITABLE_FILE_MODE:-0660}" \
        WRITABLE_REGEX="${WRITABLE_REGEX:-.*/wp-content/(cache|uploads|w3tc-config)}"
    LOCAL_PATH="${1:-$HOME/public_html}"
    [ -f "$LOCAL_PATH/wp-config.php" ] ||
        lk_warn "not a WordPress installation: $LOCAL_PATH" || return
    LOCAL_PATH="$(realpath "$LOCAL_PATH")" &&
        LOG_DIR="$(lk_mktemp_dir)" &&
        OWNER="$(gnu_stat --printf '%U' "$LOCAL_PATH/..")" || return
    lk_console_item "Setting file permissions on WordPress at" \
        "$LOCAL_PATH"
    lk_console_detail "Log directory:" "$LOG_DIR"
    lk_is_root || lk_is_true "$SUDO_OR_NOT" ||
        ! lk_can_sudo || SUDO_OR_NOT=1
    if lk_is_root || lk_is_true "$SUDO_OR_NOT"; then
        lk_console_detail "Setting owner to" "$OWNER"
        lk_maybe_sudo chown -Rhc "$OWNER:" "$LOCAL_PATH" >"$LOG_DIR/chown.log" || return
        lk_console_detail "File ownership changes:" "$(wc -l <"$LOG_DIR/chown.log")"
    else
        lk_console_warning "Unable to set owner (not running as root)"
    fi
    lk_console_detail "Setting file mode"
    for WRITABLE in "" w; do
        for TYPE in d f; do
            case "$WRITABLE$TYPE" in
            d)
                MODE="$DIR_MODE"
                ;;&
            f)
                MODE="$FILE_MODE"
                ;;&
            wd)
                MODE="$WRITABLE_DIR_MODE"
                ;;&
            wf)
                MODE="$WRITABLE_FILE_MODE"
                ;;&
            *)
                ARGS=(-type "$TYPE" ! -perm "$MODE")
                ;;&
            d | f)
                # exclude writable directories and their descendants
                ARGS=(! \( -type d -regex "$WRITABLE_REGEX" -prune \) "${ARGS[@]}")
                ;;&
            f)
                # exclude writable files (i.e. not just files in writable directories)
                ARGS+=(! -regex "$WRITABLE_REGEX")
                ;;
            w*)
                ARGS+=(-regex "$WRITABLE_REGEX(/.*)?")
                ;;
            esac
            find "$LOCAL_PATH" -regextype posix-egrep "${ARGS[@]}" -print0 |
                lk_maybe_sudo gnu_xargs -0r chmod -c "0$MODE" >>"$LOG_DIR/chmod.log" || return
        done
    done
    lk_console_detail "File mode changes:" "$(wc -l <"$LOG_DIR/chmod.log")"
    lk_console_message "Setting file permissions completed successfully" "$LK_GREEN"
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
    if lk_confirm "Enable maintenance mode on remote site?"; then
        lk_console_detail "Creating" "$1:$REMOTE_PATH/.maintenance"
        ssh "$1" \
            "bash -c 'echo -n \"\$1\" >\"\$2/.maintenance\"'" "bash" \
            "$MAINTENANCE" "$REMOTE_PATH" || return
    fi

    # migrate files
    RSYNC_ARGS=(${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"})
    lk_wp_file_sync_remote "$1" "$REMOTE_PATH" "$LOCAL_PATH" || return

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

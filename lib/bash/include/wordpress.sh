#!/bin/bash

# shellcheck disable=SC2002,SC2015,SC2016,SC2029,SC2034,SC2120,SC2207

lk_include mysql provision

function lk_wp() {
    wp --skip-plugins --skip-themes "$@"
}

function lk_wp_is_quiet() {
    [ -n "${LK_WP_QUIET:-}" ]
}

function lk_wp_get_site_root() {
    local SITE_ROOT
    SITE_ROOT=$(lk_wp eval "echo ABSPATH;" --skip-wordpress) &&
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
    TABLE_PREFIX=$(lk_wp_get_table_prefix) || return
    SKIP_TABLES=(
        "*_log"
        "*_logs"
        redirection_404

        # New Gravity Forms
        gf_form_view
        gf_draft_submissions
        "gf_entry*"

        # Old Gravity Forms
        rg_form_view
        rg_incomplete_submissions
        "rg_lead*"
    )
    SKIP_TABLES=("${SKIP_TABLES[@]/#/$TABLE_PREFIX}")
    lk_console_detail "Replacing:" "$1 -> $2"
    "${LK_WP_REPLACE_COMMAND:-lk_wp}" search-replace "$1" "$2" --no-report \
        --all-tables-with-prefix \
        --skip-tables="$(lk_implode "," SKIP_TABLES)" \
        --skip-columns="guid"
}

function lk_wp_package_install() {
    local PACKAGES
    PACKAGES=($(lk_wp package list --format=ids)) || return
    lk_in_array "$1" PACKAGES || {
        lk_console_detail "Installing WP-CLI package:" "$1"
        lk_wp package install "$1"
    }
}

function lk_wp_flush() {
    lk_console_message "Flushing WordPress rewrite rules and caches"
    lk_console_detail "Flushing object cache"
    wp cache flush || return
    lk_console_detail "Deleting transients"
    wp transient delete --all || return
    lk_console_detail "Flushing rewrite rules"
    wp rewrite flush || return
    if wp cli has-command "w3-total-cache flush"; then
        lk_console_detail "Flushing W3 Total Cache"
        wp w3-total-cache flush all
    fi
    if lk_wp plugin is-active wp-rocket; then
        lk_console_detail "Clearing WP Rocket cache"
        wp cli has-command "rocket clean" ||
            lk_wp_package_install wp-media/wp-rocket-cli || return
        wp rocket clean --confirm || return
    fi
}

function lk_wp_url_encode() {
    php --run \
        'echo urlencode(trim(stream_get_contents(STDIN)));' \
        <<<"$1"
}

function lk_wp_json_encode() {
    php --run \
        'echo substr(json_encode(trim(stream_get_contents(STDIN))), 1, -1);' \
        <<<"$1"
}

# lk_wp_rename_site NEW_URL
#
# Change the WordPress site address to NEW_URL.
#
# Variables:
# - LK_WP_OLD_URL: override `wp option get home`, e.g. to replace instances of
#   OLD_URL in database tables after changing the site address
# - LK_WP_REPLACE: perform URL replacement in database tables (default: 1)
# - LK_WP_REPLACE_WITHOUT_SCHEME (DANGEROUS): replace instances of the previous
#   URL without a scheme component ("http*://" or "//"), e.g. if renaming
#   "http://domain.com" to "https://new.domain.com", replace "domain.com" with
#   "new.domain.com" (default: 0)
# - LK_WP_REAPPLY: regenerate configuration files and rebuild indexes after
#   renaming (default: 1)
# - LK_WP_FLUSH: flush rewrite rules, caches and transients after renaming
#   (default: 1)
function lk_wp_rename_site() {
    local NEW_URL OLD_URL=${LK_WP_OLD_URL:-} PLUGIN_WARNING \
        SITE_ROOT OLD_SITE_URL NEW_SITE_URL REPLACE i SEARCH HASH HASHES=
    [ $# -eq 1 ] || lk_usage "\
Usage: $(lk_myself -f) NEW_URL" || return
    NEW_URL=$1
    lk_is_uri "$NEW_URL" ||
        lk_warn "not a valid URL: $NEW_URL" || return
    [ -n "$OLD_URL" ] ||
        OLD_URL=$(lk_wp_get_site_address) || return
    [ "$NEW_URL" != "$OLD_URL" ] ||
        lk_warn "site address not changed (set LK_WP_OLD_URL to override)" ||
        return
    SITE_ROOT=$(lk_wp_get_site_root) &&
        OLD_SITE_URL=$(lk_wp option get siteurl) || return
    NEW_SITE_URL=$(lk_replace "$OLD_URL" "$NEW_URL" "$OLD_SITE_URL")
    lk_console_item "Renaming WordPress installation at" "$SITE_ROOT"
    lk_console_detail \
        "Site address:" "$OLD_URL -> $LK_BOLD$NEW_URL$LK_RESET"
    lk_console_detail \
        "WordPress address:" "$OLD_SITE_URL -> $LK_BOLD$NEW_SITE_URL$LK_RESET"
    lk_wp_is_quiet || lk_confirm "Proceed?" Y || return
    lk_wp option update home "$NEW_URL" &&
        lk_wp option update siteurl "$NEW_SITE_URL" || return
    if lk_is_true LK_WP_REPLACE || { [ -z "${LK_WP_REPLACE+1}" ] &&
        lk_confirm "Replace the previous URL in all tables?" Y; }; then
        lk_console_message "Performing WordPress search/replace"
        REPLACE=(
            "$OLD_URL"
            "$NEW_URL"
            "${OLD_URL#http*:}"
            "${NEW_URL#http*:}"
            "$(lk_wp_url_encode "$OLD_URL")"
            "$(lk_wp_url_encode "$NEW_URL")"
            "$(lk_wp_url_encode "${OLD_URL#http*:}")"
            "$(lk_wp_url_encode "${NEW_URL#http*:}")"
            "$(lk_wp_json_encode "$OLD_URL")"
            "$(lk_wp_json_encode "$NEW_URL")"
            "$(lk_wp_json_encode "${OLD_URL#http*:}")"
            "$(lk_wp_json_encode "${NEW_URL#http*:}")"
        )
        ! lk_is_true LK_WP_REPLACE_WITHOUT_SCHEME ||
            REPLACE+=(
                "${OLD_URL#http*://}"
                "${NEW_URL#http*://}"
                "$(lk_wp_url_encode "${OLD_URL#http*://}")"
                "$(lk_wp_url_encode "${NEW_URL#http*://}")"
            )
        for i in $(seq 0 2 $((${#REPLACE[@]} - 1))); do
            SEARCH=("${REPLACE[@]:$i:2}")
            HASH=$(lk_hash "${SEARCH[@]}")
            [[ ,$HASHES, != *,$HASH,* ]] || continue
            HASHES=${HASHES:+$HASHES,}$HASH
            _lk_wp_replace "${SEARCH[@]}" || return
        done
    fi
    PLUGIN_WARNING=" Plugin code will be allowed to run."
    if lk_is_true LK_WP_REAPPLY ||
        { [ -z "${LK_WP_REAPPLY+1}" ] &&
            lk_confirm \
                "OK to regenerate configuration files and rebuild indexes?$PLUGIN_WARNING" Y &&
            PLUGIN_WARNING=; }; then
        lk_wp_reapply_config
    fi
    if lk_is_true LK_WP_FLUSH ||
        { [ -z "${LK_WP_FLUSH+1}" ] &&
            lk_confirm "OK to flush rewrite rules, caches and transients?$PLUGIN_WARNING" Y; }; then
        lk_wp_flush
    elif [ -z "${LK_WP_FLUSH+1}" ]; then
        lk_console_detail "To flush rewrite rules:" "wp rewrite flush"
        lk_console_detail "To flush everything:" "lk_wp_flush"
    fi
    lk_console_success "Site renamed successfully"
}

# lk_wp_db_config [WP_CONFIG]
#
# Read a wp-config.php file and output Bash-compatible variable assignments for
# DB_NAME, DB_USER, DB_PASSWORD and DB_HOST. If WP_CONFIG is not given, read
# wp-config.php from standard input.
function lk_wp_db_config() {
    local PHP
    PHP=$(
        echo '<?php'
        cat ${1+"$1"} |
            # 1. Remove comments and whitespace from wp-config.php
            php --strip |
            # 2. Extract the relevant "define(...);" calls, one per line
            gnu_grep -Po "\
(?<=<\?php|;|^)$S*define$S*\($S*(['\"])DB_(NAME|USER|PASSWORD|HOST)\1$S*,\
$S*('([^']+|\\\\')*'|\"([^\"\$]+|\\\\(\"|\\\$))*\")$S*\)$S*(;|\$)" |
            # 3. Add any missing semicolons
            sed -E 's/[^;]$/&;/' || exit
        # 4. Add code to output each value as a shell expression
        cat <<"EOF"
foreach (["DB_NAME", "DB_USER", "DB_PASSWORD", "DB_HOST"] as $const)
    printf("%s=%s\n", $const, escapeshellarg(constant($const)));
EOF
    ) || return
    # 5. Run the code
    php <<<"$PHP"
}

# lk_wp_db_dump_remote SSH_HOST [REMOTE_PATH]
function lk_wp_db_dump_remote() {
    local REMOTE_PATH=${2:-public_html} WP_CONFIG SH \
        DB_NAME=${DB_NAME:-} DB_USER=${DB_USER:-} \
        DB_PASSWORD=${DB_PASSWORD:-} DB_HOST=${DB_HOST:-} \
        OUTPUT_FILE
    [ $# -ge 1 ] || lk_usage "\
Usage: $(lk_myself -f) SSH_HOST [REMOTE_PATH]" || return
    [ -n "$1" ] || lk_warn "no ssh host" || return
    REMOTE_PATH=${REMOTE_PATH%/}
    lk_console_message "Preparing to dump remote WordPress database"
    [ -n "$DB_NAME" ] &&
        [ -n "$DB_USER" ] &&
        [ -n "$DB_PASSWORD" ] &&
        [ -n "$DB_HOST" ] || {
        lk_console_message "Getting credentials"
        lk_console_detail "Retrieving" "$1:$REMOTE_PATH/wp-config.php"
        WP_CONFIG=$(ssh "$1" cat "$REMOTE_PATH/wp-config.php") || return
        lk_console_detail "Parsing WordPress configuration"
        SH=$(lk_wp_db_config <<<"$WP_CONFIG") &&
            eval "$SH" || return
    }
    if [ ! -t 1 ]; then
        lk_mysql_dump_remote "$1" "$DB_NAME"
    else
        OUTPUT_FILE=~/.lk-platform/cache/db/$1-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
        lk_console_item "Initiating MySQL dump to" "$OUTPUT_FILE"
        install -d -m 00700 "${OUTPUT_FILE%/*}" &&
            lk_mysql_dump_remote "$1" "$DB_NAME" >"$OUTPUT_FILE"
    fi
}

# lk_wp_db_dump [SITE_ROOT]
function lk_wp_db_dump() {
    local SITE_ROOT OUTPUT_FILE \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || lk_usage "\
Usage: $(lk_myself -f) [SITE_ROOT]" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=$(lk_replace ~/ "" "$SITE_ROOT")
        OUTPUT_FILE=localhost-${OUTPUT_FILE//\//_}-$(lk_date_ymdhms).sql.gz
        ! lk_in_string "$SITE_ROOT" "$PWD" &&
            OUTPUT_FILE=$PWD/$OUTPUT_FILE || {
            OUTPUT_FILE=~/.lk-platform/cache/db/$OUTPUT_FILE
            install -d -m 00700 "${OUTPUT_FILE%/*}" || return
        }
        [ -w "${OUTPUT_FILE%/*}" ] ||
            lk_warn "cannot write to ${OUTPUT_FILE%/*}" || return
    }
    lk_console_message "Preparing to dump WordPress database"
    lk_console_detail "Getting credentials"
    DB_NAME=$(lk_wp config get DB_NAME) &&
        DB_USER=$(lk_wp config get DB_USER) &&
        DB_PASSWORD=$(lk_wp config get DB_PASSWORD) &&
        DB_HOST=$(lk_wp config get DB_HOST) || return
    if [ ! -t 1 ]; then
        lk_mysql_dump "$DB_NAME"
    else
        lk_console_item "Initiating MySQL dump to" "$OUTPUT_FILE"
        lk_mysql_dump "$DB_NAME" >"$OUTPUT_FILE"
    fi
}

# lk_wp_db_get_vars [-p PREFIX] [SITE_ROOT]
function lk_wp_db_get_vars() {
    local SITE_ROOT SH PREFIX=
    [ "${1:-}" != -p ] || { PREFIX=$2 && shift 2 || return; }
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    SH=$(
        for OPTION in DB_NAME DB_USER DB_PASSWORD DB_HOST; do
            VALUE=$(lk_wp --path="$SITE_ROOT" config get "$OPTION") || exit
            [ "${FUNCNAME[1]:-}" = lk_wp_db_set_local ] ||
                _lk_var_prefix
            printf '%s=%q\n' "$PREFIX$OPTION" "$VALUE"
        done
    ) && echo "$SH"
}

# lk_wp_db_set_local [SITE_ROOT [DB_NAME [DB_USER]]]
#
# Set LOCAL_DB_NAME, LOCAL_DB_USER, LOCAL_DB_PASSWORD and LOCAL_DB_HOST to
# current or recommended values for the WordPress installation at SITE_ROOT or
# in the current directory, using DB_NAME and/or DB_USER instead of the default
# directory-, owner- or user-based identifier if current values are not accepted
# by the local MySQL server.
#
# If new credentials are generated, they are not applied to the MySQL server.
function lk_wp_db_set_local() {
    local SITE_ROOT SH DEFAULT_IDENTIFIER
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    LOCAL_DB_NAME=
    LOCAL_DB_USER=
    LOCAL_DB_PASSWORD=
    ! SH=$(lk_wp_db_get_vars -p LOCAL_ "$SITE_ROOT") || eval "$SH"
    LOCAL_DB_HOST=${LK_MYSQL_HOST:-localhost}
    if [ "${LOCAL_DB_NAME:+1}\
${LOCAL_DB_USER:+1}${LOCAL_DB_PASSWORD:+1}" = 111 ]; then
        lk_mysql_write_cnf \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        # Keep current credentials if they work
        ! lk_mysql_connects 2>/dev/null || return 0
    fi
    if [[ $SITE_ROOT =~ ^/srv/www/([^./]+)/public_html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[1]}
    elif [[ $SITE_ROOT =~ ^/srv/www/([^./]+)/([^./]+)/public_html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
    elif [[ $SITE_ROOT =~ ^/srv/(www|httpd?)/(([^./]+)\.local(host)?|local\.([^./]+)(\.[^./]+)+)/(public_)?html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[3]}${BASH_REMATCH[5]}
    elif [[ ! $SITE_ROOT =~ ^/srv/(www|httpd?)(/.*)?$ ]] && [ "${SITE_ROOT#~}" != "$SITE_ROOT" ]; then
        DEFAULT_IDENTIFIER=${SITE_ROOT##*/}
    elif [ -e "$SITE_ROOT" ]; then
        DEFAULT_IDENTIFIER=$(lk_file_owner "$SITE_ROOT") || return
    else
        DEFAULT_IDENTIFIER=$USER
    fi
    LOCAL_DB_NAME=${2:-$DEFAULT_IDENTIFIER}
    LOCAL_DB_USER=${3:-$DEFAULT_IDENTIFIER}
    # Try existing password with new LOCAL_DB_USER before generating a new one
    [ -z "$LOCAL_DB_PASSWORD" ] || {
        lk_mysql_write_cnf \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        ! lk_mysql_connects 2>/dev/null || return 0
    }
    LOCAL_DB_PASSWORD=$(lk_random_password 24) &&
        lk_mysql_write_cnf \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST"
}

# lk_wp_db_restore_local SQL_PATH [DB_NAME [DB_USER]]
function lk_wp_db_restore_local() {
    local SITE_ROOT SH SQL _SQL COMMAND \
        LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD LOCAL_DB_HOST
    [ -f "$1" ] || lk_usage "\
Usage: $(lk_myself -f) SQL_PATH [DB_NAME [DB_USER]]" || return
    SITE_ROOT=$(lk_wp_get_site_root) || return
    lk_console_message "Preparing to restore WordPress database"
    lk_wp_is_quiet || {
        lk_console_detail "Backup file:" "$1"
        lk_console_detail "WordPress installation:" "$SITE_ROOT"
    }
    SH=$(lk_wp_db_get_vars "$SITE_ROOT") && eval "$SH" || return
    lk_wp_db_set_local "$SITE_ROOT" "${@:2}" || return
    SQL=(
        "DROP DATABASE IF EXISTS $(lk_mysql_quote_identifier "$LOCAL_DB_NAME")"
        "CREATE DATABASE $(lk_mysql_quote_identifier "$LOCAL_DB_NAME")"
    )
    _SQL=$(printf '%s;\n' "${SQL[@]}")
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_console_detail "DB_NAME will be updated to" "$LOCAL_DB_NAME"
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_console_detail "DB_USER will be updated to" "$LOCAL_DB_USER"
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_console_detail "DB_HOST will be updated to" "$LOCAL_DB_HOST"
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_console_detail "DB_PASSWORD will be reset"
    lk_console_detail "Local database will be reset with:" "$_SQL"
    lk_confirm "\
All data in local database '$LOCAL_DB_NAME' will be permanently destroyed.
Proceed?" Y || return
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] || {
        COMMAND=(lk_elevate "${LK_INST:-$LK_BASE}/bin/lk-mysql-grant.sh"
            "$LOCAL_DB_NAME" "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD")
        [[ $USER =~ ^[a-zA-Z0-9_]+$ ]] &&
            [[ $LOCAL_DB_NAME =~ ^$USER(_[a-zA-Z0-9_]*)?$ ]] ||
            unset "COMMAND[0]"
        "${COMMAND[@]}" || return
    }
    lk_console_message "Restoring WordPress database to local system"
    lk_console_detail "Checking wp-config.php"
    [ "$DB_NAME" = "$LOCAL_DB_NAME" ] ||
        lk_wp config set \
            DB_NAME "$LOCAL_DB_NAME" --type=constant --quiet || return
    [ "$DB_USER" = "$LOCAL_DB_USER" ] ||
        lk_wp config set \
            DB_USER "$LOCAL_DB_USER" --type=constant --quiet || return
    [ "$DB_HOST" = "$LOCAL_DB_HOST" ] ||
        lk_wp config set \
            DB_HOST "$LOCAL_DB_HOST" --type=constant --quiet || return
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] ||
        lk_wp config set \
            DB_PASSWORD "$LOCAL_DB_PASSWORD" --type=constant --quiet || return
    lk_console_detail "Resetting database" "$LOCAL_DB_NAME"
    echo "$_SQL" | lk_mysql || return
    lk_console_detail "Restoring from" "$1"
    if [[ $1 =~ \.gz(ip)?$ ]]; then
        lk_log_bypass_stderr pv "$1" | gunzip
    else
        lk_log_bypass_stderr pv "$1"
    fi | lk_mysql "$LOCAL_DB_NAME" ||
        lk_console_error -r "Restore operation failed" || return
    lk_console_success "Database restored successfully"
}

# lk_wp_sync_files_from_remote SSH_HOST [REMOTE_PATH [LOCAL_PATH]]
function lk_wp_sync_files_from_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH \
        ARGS=(-vrlptH -x --delete
            ${RSYNC_ARGS[@]+"${RSYNC_ARGS[@]}"}
            ${LK_RSYNC_ARGS:+"$LK_RSYNC_ARGS"}) \
        KEEP_LOCAL EXCLUDE EXIT_STATUS=0
    [ $# -ge 1 ] || lk_usage "\
Usage: $(lk_myself -f) SSH_HOST [REMOTE_PATH [LOCAL_PATH]]" || return
    # files that already exist on the local system will be added to --exclude
    KEEP_LOCAL=(
        "wp-config.php"
        ".git"
        ${LK_WP_SYNC_KEEP_LOCAL[@]+"${LK_WP_SYNC_KEEP_LOCAL[@]}"}
    )
    EXCLUDE=(
        /.maintenance
        "php_error*.log"
        {"error*",debug}"?log"
        /wp-content/{backup,cache,upgrade,updraft}/
        ${LK_WP_SYNC_EXCLUDE[@]+"${LK_WP_SYNC_EXCLUDE[@]}"}
    )
    LOCAL_PATH="${3:-$(lk_wp_get_site_root 2>/dev/null)}" ||
        LOCAL_PATH=~/public_html
    lk_console_message "Preparing to sync WordPress files"
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    lk_wp_is_quiet || {
        lk_console_detail "Source:" "$1:$REMOTE_PATH"
        lk_console_detail "Destination:" "$LOCAL_PATH"
    }
    for FILE in "${KEEP_LOCAL[@]}"; do
        [ ! -e "$LOCAL_PATH/$FILE" ] || EXCLUDE+=("/$FILE")
    done
    ARGS+=("${EXCLUDE[@]/#/--exclude=}")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    lk_console_detail "Local files will be overwritten with command:" \
        "rsync ${ARGS[*]}"
    lk_wp_is_quiet || ! lk_confirm "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_confirm "LOCAL CHANGES WILL BE PERMANENTLY LOST. Proceed?" Y ||
        return
    [ -d "$LOCAL_PATH" ] || mkdir -p "$LOCAL_PATH" || return
    rsync "${ARGS[@]}" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq 0 ] &&
        lk_console_success "File sync completed successfully" ||
        lk_console_error "File sync failed"
    return "$EXIT_STATUS"
}

# lk_wp_reapply_config
#
# Regenerate configuration files and rebuild indexes. Recommended after
# migrating WordPress.
function lk_wp_reapply_config() {
    local FILE
    if lk_wp plugin is-active wp-rocket; then
        lk_console_detail "Regenerating WP Rocket files"
        wp cli has-command "rocket regenerate" ||
            lk_wp_package_install wp-media/wp-rocket-cli || return
        for FILE in htaccess advanced-cache config; do
            wp rocket regenerate --file="$FILE"
        done
    fi
    if lk_wp plugin is-active email-log; then
        lk_console_detail "Re-activating Email Log"
        lk_wp plugin deactivate email-log
        lk_wp plugin activate email-log
    fi
    if wp cli has-command "yoast index"; then
        lk_console_detail "Building Yoast index"
        wp yoast index
    fi
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
    [ "$INTERVAL" -lt 60 ] &&
        CRON_COMMAND="*/$INTERVAL * * * * $CRON_COMMAND" ||
        CRON_COMMAND="$((RANDOM % 60)) * * * * $CRON_COMMAND"
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

function lk_wp_get_maintenance_php() {
    echo '<?php $upgrading = time(); ?>'
}

# lk_wp_enable_maintenance [SITE_ROOT]
function lk_wp_enable_maintenance() {
    local SITE_ROOT MAINTENANCE_PHP
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    MAINTENANCE_PHP=$(lk_wp_get_maintenance_php)
    echo "$MAINTENANCE_PHP" >"$SITE_ROOT/.maintenance"
}

# lk_wp_disable_maintenance [SITE_ROOT]
function lk_wp_disable_maintenance() {
    local SITE_ROOT
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    [ ! -e "$SITE_ROOT/.maintenance" ] ||
        rm "$SITE_ROOT/.maintenance"
}

# lk_wp_set_permissions [SITE_ROOT]
function lk_wp_set_permissions() {
    local SITE_ROOT OWNER LOG_FILE CHANGES
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} &&
        SITE_ROOT=$(realpath "$SITE_ROOT") || return
    if lk_will_elevate; then
        OWNER=$(lk_file_owner "$SITE_ROOT/..") &&
            LOG_FILE=$(lk_mktemp_file) || return
        lk_console_item "Setting file ownership in" "$SITE_ROOT"
        lk_console_detail "Owner:" "$OWNER"
        CHANGES=$(lk_maybe_sudo gnu_chown -Rhc "$OWNER" "$SITE_ROOT" |
            tee -a "$LOG_FILE" | wc -l) || return
        lk_console_detail "Changes:" "$CHANGES"
        lk_console_log "Changes have been logged to" "$LOG_FILE"
    else
        lk_console_warning "Unable to set owner (not running as root)"
    fi
    lk_dir_set_modes "$SITE_ROOT" \
        "" \
        "${LK_DIR_MODE:-0750}" "${LK_FILE_MODE:-0640}" \
        ".*/wp-content/(cache|uploads|w3tc-config)" \
        "${LK_WRITABLE_DIR_MODE:-2770}" "${LK_WRITABLE_FILE_MODE:-0660}" \
        ".*/\\.git/objects/([0-9a-f]{2}|pack)/.*" \
        0555 0444
}

lk_provide wordpress

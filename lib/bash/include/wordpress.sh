#!/bin/bash
# shellcheck disable=SC1091,SC2015,SC2029,SC2207,SC2119,SC2120,SC2206

lk_include provision mysql

function lk_wp() {
    wp --skip-plugins --skip-themes "$@"
}

function lk_wp_quiet() {
    [ "${LK_WP_QUIET:-0}" -ne 0 ]
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
        --skip-tables="$(lk_implode "," SKIP_TABLES)" \
        --skip-columns="guid"
}

function lk_wp_flush() {
    lk_console_message "Flushing WordPress rewrite rules and caches"
    lk_console_detail "Flushing object cache"
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
#
# Change the WordPress site address to NEW_URL.
#
# Environment variables:
#
# - LK_WP_OLD_URL=OLD_URL: override `wp option get home`, e.g. to replace
#   instances of OLD_URL in database tables after changing the site address
# - LK_WP_REPLACE=<1|0|Y|N>: perform URL replacement in database tables
#   (default: 1)
# - LK_WP_REPLACE_WITHOUT_SCHEME=<1|0|Y|N> (DANGEROUS): replace instances of the
#   previous URL without a scheme component ("http*://" or "//"), e.g. if
#   renaming "http://domain.com" to "https://new.domain.com", replace
#   "domain.com" with "new.domain.com" (default: 0)
# - LK_WP_FLUSH=<1|0|Y|N>: flush WordPress rewrite rules, caches and transients
#   after renaming (default: 1)
function lk_wp_rename_site() {
    local NEW_URL=${1:-} OLD_URL=${LK_WP_OLD_URL:-} \
        SITE_ROOT OLD_SITE_URL NEW_SITE_URL REPLACE DELIM=$'\t' IFS r s
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
    lk_wp_quiet || lk_confirm "Proceed?" Y || return
    lk_wp option update home "$NEW_URL" &&
        lk_wp option update siteurl "$NEW_SITE_URL" || return
    if lk_is_true "${LK_WP_REPLACE:-}" || { [ -z "${LK_WP_REPLACE:-}" ] &&
        lk_confirm "Replace the previous URL in all tables?" Y; }; then
        lk_console_message "Performing WordPress search/replace"
        REPLACE=(
            "$OLD_URL$DELIM$NEW_URL"
            "${OLD_URL#http*:}$DELIM${NEW_URL#http*:}"
            "$(
                lk_wp_url_encode "$OLD_URL"
            )$DELIM$(
                lk_wp_url_encode "$NEW_URL"
            )"
            "$(
                lk_wp_url_encode "${OLD_URL#http*:}"
            )$DELIM$(
                lk_wp_url_encode "${NEW_URL#http*:}"
            )"
            "$(
                lk_wp_json_encode "$OLD_URL"
            )$DELIM$(
                lk_wp_json_encode "$NEW_URL"
            )"
            "$(
                lk_wp_json_encode "${OLD_URL#http*:}"
            )$DELIM$(
                lk_wp_json_encode "${NEW_URL#http*:}"
            )"
        )
        ! lk_is_true "${LK_WP_REPLACE_WITHOUT_SCHEME:-0}" ||
            REPLACE+=(
                "${OLD_URL#http*://}$DELIM${NEW_URL#http*://}"
                "$(
                    lk_wp_url_encode "${OLD_URL#http*://}"
                )$DELIM$(
                    lk_wp_url_encode "${NEW_URL#http*://}"
                )"
            )
        lk_remove_repeated REPLACE
        for r in "${REPLACE[@]}"; do
            IFS=$DELIM
            s=($r)
            unset IFS
            _lk_wp_replace "${s[@]}" || return
        done
    fi
    if lk_is_true "${LK_WP_FLUSH:-}" ||
        { [ -z "${LK_WP_FLUSH:-}" ] && lk_confirm "\
OK to flush rewrite rules, caches and transients? \
Plugin code will be allowed to run." Y; }; then
        lk_wp_flush
    elif [ -z "${LK_WP_FLUSH:-}" ]; then
        lk_console_detail "To flush rewrite rules:" "wp rewrite flush"
        lk_console_detail "To flush everything:" "lk_wp_flush"
    fi
    lk_console_success "Site renamed successfully"
}

# lk_wp_db_config [WP_CONFIG_PATH]
#
# Output DB_NAME, DB_USER, DB_PASSWORD and DB_HOST values configured in
# WP_CONFIG_PATH (./wp-config.php by default) as KEY="VALUE" pairs without
# calling `wp config`.
function lk_wp_db_config() {
    local WP_CONFIG=${1:-wp-config.php} PHP
    [ -e "$WP_CONFIG" ] || lk_warn "file not found: $WP_CONFIG" || return
    PHP=$(
        echo '<?php'
        # 1. remove comments and whitespace from wp-config.php
        php --strip "$WP_CONFIG" |
            # 2. extract the relevant "define(...);" calls, one per line
            grep -Po "\
(?<=<\?php|;|^)\s*define\s*\(\s*(['\"])DB_(NAME|USER|PASSWORD|HOST)\1\s*,\
\s*('([^']+|\\\\')*'|\"([^\"\$]+|\\\\(\"|\\\$))*\")\s*\)\s*(;|\$)" |
            # 3. add any missing semicolons
            sed -E 's/[^;]$/&;/' || exit
        # 4. add code to output each value as a shell expression
        cat <<"EOF"
$vals = array_map(function ($v) {
        return escapeshellarg($v);
    }, [DB_NAME, DB_USER, DB_PASSWORD, DB_HOST]);
printf("DB_NAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\nDB_HOST=%s\n",
    $vals[0], $vals[1], $vals[2], $vals[3]);
EOF
    ) || return
    # 5. run the code
    php <<<"$PHP"
}

# lk_wp_db_dump_remote SSH_HOST [REMOTE_PATH]
function lk_wp_db_dump_remote() {
    local REMOTE_PATH=${2:-public_html} WP_CONFIG DB_CONFIG \
        DB_NAME=${DB_NAME:-} DB_USER=${DB_USER:-} \
        DB_PASSWORD=${DB_PASSWORD:-} DB_HOST=${DB_HOST:-} \
        OUTPUT_FILE
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
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
        DB_CONFIG=$(lk_wp_db_config <(cat <<<"$WP_CONFIG")) || return
        . /dev/stdin <<<"$DB_CONFIG" || return
    }
    if [ ! -t 1 ]; then
        lk_mysql_dump_remote "$1" "$DB_NAME"
    else
        OUTPUT_FILE=~/$1-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
        lk_console_item "Initiating MySQL dump to" "$OUTPUT_FILE"
        lk_mysql_dump_remote "$1" "$DB_NAME" >"$OUTPUT_FILE"
    fi
}

# lk_wp_db_dump [SITE_ROOT]
function lk_wp_db_dump() {
    local SITE_ROOT OUTPUT_FILE \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=$(lk_replace ~/ "" "$SITE_ROOT")
        OUTPUT_FILE=localhost-${OUTPUT_FILE//\//_}-$(lk_date_ymdhms).sql.gz
        ! lk_in_string "$SITE_ROOT" "$PWD" &&
            OUTPUT_FILE=$PWD/$OUTPUT_FILE ||
            OUTPUT_FILE=~/$OUTPUT_FILE
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

# lk_wp_db_set_local [SITE_ROOT [WP_DB_NAME WP_DB_USER WP_DB_PASSWORD \
#   [DB_NAME [DB_USER]]]]
#
# Set each of LOCAL_DB_NAME, LOCAL_DB_USER, LOCAL_DB_PASSWORD and LOCAL_DB_HOST
# to an appropriate value, taking into account:
# - WP_DB_NAME, WP_DB_USER, WP_DB_PASSWORD (used as-is if validated by the local
#   MySQL server)
# - DB_NAME, DB_USER (used instead of defaults if WP_DB_* values aren't valid)
# - the location of SITE_ROOT relative to well-known home directories
# - the owner of SITE_ROOT
# - the invoking user
#
# New credentials are generated if necessary but they are not applied.
function lk_wp_db_set_local() {
    local SITE_ROOT DEFAULT_IDENTIFIER
    SITE_ROOT=${1:-$(lk_wp_get_site_root)} || return
    LOCAL_DB_NAME=${2:-}
    LOCAL_DB_USER=${3:-}
    LOCAL_DB_PASSWORD=${4:-}
    LOCAL_DB_HOST=${LK_MYSQL_HOST:-localhost}
    if [ -n "$LOCAL_DB_NAME" ] &&
        [ -n "$LOCAL_DB_USER" ] &&
        [ -n "$LOCAL_DB_PASSWORD" ]; then
        lk_mysql_write_cnf \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        # Keep provided credentials if they work
        ! lk_mysql_connects 2>/dev/null || return 0
    fi
    if [[ $SITE_ROOT =~ ^/srv/www/([^./]+)/public_html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[1]}
    elif [[ $SITE_ROOT =~ ^/srv/www/([^./]+)/([^./]+)/public_html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
    elif [[ $SITE_ROOT =~ \
        ^/srv/http/([^./]+)\.localhost/(public_)?html$ ]]; then
        DEFAULT_IDENTIFIER=${BASH_REMATCH[1]}
    elif [[ ! $SITE_ROOT =~ ^/srv/(www|http)(/.*)?$ ]] &&
        [ "${SITE_ROOT:0:${#HOME}}" = "$HOME" ]; then
        DEFAULT_IDENTIFIER=${SITE_ROOT##*/}
    elif [ -e "$SITE_ROOT" ]; then
        DEFAULT_IDENTIFIER=$(lk_file_owner "$SITE_ROOT") || return
    else
        DEFAULT_IDENTIFIER=$USER || return
    fi
    LOCAL_DB_NAME=${5:-$DEFAULT_IDENTIFIER}
    LOCAL_DB_USER=${6:-$DEFAULT_IDENTIFIER}
    lk_mysql_write_cnf \
        "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
    # Try existing password with new LOCAL_DB_USER before changing password
    lk_mysql_connects 2>/dev/null || {
        LOCAL_DB_PASSWORD=$(openssl rand -base64 32) &&
            lk_mysql_write_cnf \
                "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST"
    }
}

# lk_wp_db_restore_local SQL_PATH [DB_NAME [DB_USER]]
function lk_wp_db_restore_local() {
    local SITE_ROOT DEFAULT_IDENTIFIER SQL _SQL COMMAND \
        LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD LOCAL_DB_HOST \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    SITE_ROOT=$(lk_wp_get_site_root) || return
    lk_console_message "Preparing to restore WordPress database"
    lk_wp_quiet || {
        lk_console_detail "Backup file:" "$1"
        lk_console_detail "WordPress installation:" "$SITE_ROOT"
    }
    DB_NAME=$(lk_wp config get DB_NAME) &&
        DB_USER=$(lk_wp config get DB_USER) &&
        DB_PASSWORD=$(lk_wp config get DB_PASSWORD) &&
        DB_HOST=$(lk_wp config get DB_HOST) || return
    lk_wp_db_set_local \
        "$SITE_ROOT" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "${@:2}" || return
    SQL=(
        "DROP DATABASE IF EXISTS \`$LOCAL_DB_NAME\`"
        "CREATE DATABASE \`$LOCAL_DB_NAME\`"
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
        COMMAND=(lk_elevate "$LK_BASE/bin/lk-mysql-grant.sh"
            "$LOCAL_DB_NAME" "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD")
        [[ "$USER" =~ ^[a-zA-Z0-9_]+$ ]] &&
            [[ "$LOCAL_DB_NAME" =~ ^$USER(_[a-zA-Z0-9_]*)?$ ]] ||
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
    lk_console_detail "Preparing database" "$LOCAL_DB_NAME"
    echo "$_SQL" | lk_mysql || return
    lk_console_detail "Restoring from" "$1"
    if [[ "$1" =~ \.gz(ip)?$ ]]; then
        pv --force "$1" | gunzip
    else
        pv --force "$1"
    fi | lk_mysql "$LOCAL_DB_NAME" ||
        lk_console_error "Restore operation failed" || return
    lk_console_success "Database restored successfully"
}

# lk_wp_sync_files_from_remote ssh_host [remote_path [local_path]]
function lk_wp_sync_files_from_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH \
        ARGS=(-vrlptH -x --delete
            ${RSYNC_ARGS[@]+"${RSYNC_ARGS[@]}"}
            ${LK_RSYNC_ARGS:+"$LK_RSYNC_ARGS"}) \
        KEEP_LOCAL EXCLUDE EXIT_STATUS=0
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
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    LOCAL_PATH="${3:-$(lk_wp_get_site_root 2>/dev/null)}" ||
        LOCAL_PATH="$HOME/public_html"
    lk_console_message "Preparing to sync WordPress files"
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    lk_wp_quiet || {
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
    lk_wp_quiet || ! lk_confirm "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_confirm "LOCAL CHANGES WILL BE PERMANENTLY LOST. Proceed?" Y ||
        return
    [ -d "$LOCAL_PATH" ] || mkdir -p "$LOCAL_PATH" || return
    rsync "${ARGS[@]}" || EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -eq 0 ] &&
        lk_console_success "File sync completed successfully" ||
        lk_console_error0 "File sync failed"
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
    [ "$INTERVAL" -lt 60 ] &&
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

function lk_wp_get_maintenance_php() {
    # shellcheck disable=SC2016
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
    local SITE_ROOT OWNER \
        LK_DIR_MODE="${LK_DIR_MODE:-0750}" \
        LK_FILE_MODE="${LK_FILE_MODE:-0640}" \
        LK_WRITABLE_DIR_MODE="${LK_WRITABLE_DIR_MODE:-2770}" \
        LK_WRITABLE_FILE_MODE="${LK_WRITABLE_FILE_MODE:-0660}"
    SITE_ROOT="${1:-$(lk_wp_get_site_root)}" &&
        SITE_ROOT="$(realpath "$SITE_ROOT")" || return
    if lk_is_root || lk_is_true "$(lk_get_maybe_sudo)"; then
        OWNER="$(lk_file_owner "$SITE_ROOT/..")" || return
    fi
    lk_dir_set_permissions \
        "$SITE_ROOT" \
        ".*/wp-content/(cache|uploads|w3tc-config)" \
        ${OWNER+"$OWNER:"}
}

#!/usr/bin/env bash

lk_require mysql provision

function wp() {
    local WP=wp HTTP_CLIENT_IP=127.0.1.1 \
        WP_CLI_CONFIG_PATH=$LK_BASE/share/wp-cli/config.yml \
        WP_CLI_PACKAGES_DIR=${WP_CLI_PACKAGES_DIR-/usr/local/lib/wp-cli-packages}
    export HTTP_CLIENT_IP WP_CLI_CONFIG_PATH
    [[ -d $WP_CLI_PACKAGES_DIR ]] &&
        export WP_CLI_PACKAGES_DIR || unset WP_CLI_PACKAGES_DIR
    set -- ${_LK_WP_ARGS+"${_LK_WP_ARGS[@]}"} \
        ${_LK_WP_PATH+--path="$_LK_WP_PATH"} \
        "$@"
    [[ -z ${WP_CLI_PHP-} ]] ||
        WP=$(type -P wp) || return
    if [[ -n ${_LK_WP_USER-} ]]; then
        lk_run_as "$_LK_WP_USER" ${WP_CLI_PHP:+"$WP_CLI_PHP"} "$WP" "$@"
    else
        command ${WP_CLI_PHP:+"$WP_CLI_PHP"} "$WP" "$@"
    fi
}

function lk_wp() {
    wp --skip-plugins --skip-themes "$@"
}

function wp_if_running() {
    [ $# -gt 0 ] || lk_warn "invalid arguments" || return
    local ARGV=("$@") ARGS=()
    while [[ ${1-} == -* ]]; do
        [[ $1 =~ ^--skip-(themes|plugins)$ ]] ||
            ARGS[${#ARGS[@]}]=$1
        shift
    done
    ! lk_wp ${ARGS+"${ARGS[@]}"} maintenance-mode is-active &>/dev/null ||
        lk_warn "Skipping (maintenance mode enabled): wp $*" ||
        return 0
    wp "${ARGV[@]}"
}

function lk_wp_if_running() {
    wp_if_running --skip-plugins --skip-themes "$@"
}

function _lk_wp_is_quiet() {
    [ -n "${_LK_WP_QUIET-}" ] && ! lk_is_v
}

function _lk_wp_tty_run() {
    if _lk_wp_is_quiet; then
        [[ ${1-} != -* ]] || shift
        "$@"
    else
        lk_tty_run_detail "$@"
    fi
}

function lk_wp_list_commands() {
    wp cli cmd-dump 2>/dev/null | jq -r '
recurse(. as $c | .subcommands[]? | .name |= "\($c.name) \(.)") |
    select(.subcommands | length == 0) | .name'
}

function lk_wp_get_site_root() {
    [[ -z ${_LK_WP_PATH:+1} ]] || { echo "$_LK_WP_PATH" && return; }
    local ABSPATH
    ABSPATH=$(lk_wp eval "echo rtrim(ABSPATH, DIRECTORY_SEPARATOR);" --skip-wordpress) &&
        [[ -e $ABSPATH/wp-includes/version.php ]] &&
        echo "$ABSPATH" || lk_err "WordPress installation not found"
}

# _lk_wp_set_path [SITE_ROOT]
#
# Used when the current directory must be part of WordPress unless the optional
# SITE_ROOT argument is set. Outputs Bash code that either:
# 1. returns non-zero if SITE_ROOT is not set and the current directory is not
#    part of WordPress, or if SITE_ROOT is set and is not a directory (a warning
#    is printed in either case); or
# 2. assigns the relevant site root to `_LK_WP_PATH`, effectively adding
#    `--path=<_LK_WP_PATH>` to every `wp` invocation in the current scope.
#
# Usage:
# - eval "$(_lk_wp_set_path "$@")"
# - [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
# - [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
function _lk_wp_set_path() {
    local _LK_WP_PATH
    _LK_WP_PATH=${1:-$(lk_wp_get_site_root)} &&
        { [ -d "$_LK_WP_PATH" ] || lk_warn "not a directory: $_LK_WP_PATH"; } ||
        lk_pass echo "return 1" || return
    declare -p _LK_WP_PATH
}

# _lk_wp_set_admin_url
#
# Output Bash code that configures subsequent `wp` invocations in the current
# scope to masquerade as admin user requests for the WordPress dashboard.
#
# Necessary for plugins that misbehave outside of wp-admin (e.g. hide-my-wp,
# which doesn't apply its rewrite rules when `wp rewrite flush` is called).
function _lk_wp_set_admin_url() {
    [ -z "${_LK_WP_ADMIN_URL_SET-}" ] || return 0
    local ADMIN_URL ADMIN_USER
    ADMIN_URL=$(lk_wp eval "echo get_admin_url();") &&
        ADMIN_USER=$(lk_wp user list --field=id --role=administrator |
            sort -n | head -n1) || lk_pass echo "return 1" || return
    local _LK_WP_ADMIN_URL_SET=1 \
        _LK_WP_ARGS=(${_LK_WP_ARGS+"${_LK_WP_ARGS[@]}"}
            --url="$ADMIN_URL" ${ADMIN_USER:+--user="$ADMIN_USER"})
    declare -p _LK_WP_ARGS _LK_WP_ADMIN_URL_SET
}

# lk_wp_get_site_address [SITE_ROOT]
function lk_wp_get_site_address() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    lk_wp option get home
}

# lk_wp_get_table_prefix [SITE_ROOT]
function lk_wp_get_table_prefix() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    lk_wp config get table_prefix
}

# lk_wp_option_upsert [-s SITE_ROOT] KEY KEY_PATH... VALUE
function lk_wp_option_upsert() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local IFS i
    unset IFS
    ! lk_wp option pluck "${@:1:$#-1}" &>/dev/null || {
        lk_wp option patch update "$@" ||
            lk_warn "unable to update value in option '$1': ${*:2}"
        return
    }
    lk_wp option get "$1" &>/dev/null ||
        lk_wp option add "$1" "{}" --format=json
    for ((i = 2; i < $# - 1; i++)); do
        lk_wp option pluck "${@:1:i}" &>/dev/null ||
            lk_wp option patch insert "${@:1:i}" "{}" --format=json ||
            lk_warn "unable to insert value in option '$1': ${*:2:i-1}" ||
            return
    done
    lk_wp option patch insert "$@" ||
        lk_warn "unable to set value in option '$1': $*"
}

# lk_wp_curl [-s SITE_ROOT] [CURL_ARG...] PATH
function lk_wp_curl() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME [-s SITE_ROOT] [CURL_ARG...] PATH" || return
    local URL IFS=$' \t\n'
    URL=$(lk_wp_get_site_address) &&
        curl "${@:1:$#-1}" --insecure --connect-to "::127.0.0.1:" \
            "${URL%/}${*: -1}"
}

function lk_wp_package_install() {
    [ $# -ge 1 ] ||
        lk_usage "Usage: $FUNCNAME PACKAGE[:<VERSION|@stable>]..." || return
    while IFS= read -r PACKAGE; do
        lk_tty_detail "Installing WP-CLI package:" "$PACKAGE"
        lk_wp package install "$PACKAGE"
    done < <(printf '%s\n' "$@" | grep -Ev \
        "^$(lk_wp package list --format=ids | tr -s '[:blank:]' '\n' |
            lk_ere_implode_input -e)(:.+)?\$")
}

# lk_wp_flush_opcache [SITE_ROOT]
function lk_wp_flush_opcache() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    local RESULT
    lk_tty_print "Flushing WordPress OPcache"
    RESULT=$(lk_wp_curl -fsS "/php-opcache-flush") || return
    case "$RESULT" in
    DISABLED)
        lk_tty_detail "OPcache not enabled"
        ;;
    OK)
        lk_tty_detail "OPcache flushed successfully"
        ;;
    *)
        false || lk_warn "result not recognised:" "$RESULT"
        ;;
    esac
}

# lk_wp_flush [SITE_ROOT]
function lk_wp_flush() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    eval "$(_lk_wp_set_admin_url)"
    lk_wp_flush_opcache || true
    lk_tty_print "Flushing WordPress rewrite rules and caches"
    lk_tty_detail "Flushing object cache"
    lk_report_error -q wp cache flush --no-skip-plugins || return
    lk_tty_detail "Deleting transients"
    lk_report_error -q wp transient delete --all --no-skip-plugins || return
    lk_tty_detail "Flushing rewrite rules"
    lk_report_error -q wp rewrite flush --hard --no-skip-plugins || return
    if wp cli has-command "w3-total-cache flush" 2>/dev/null; then
        lk_tty_detail "Flushing W3 Total Cache"
        lk_report_error -q wp w3-total-cache flush all || true
    fi
    if wp cli has-command "litespeed-purge all" 2>/dev/null; then
        lk_tty_detail "Flushing LiteSpeed Cache"
        lk_report_error -q wp litespeed-purge all || true
    fi
    if lk_wp plugin is-active wp-rocket; then (
        WP_CLI_PACKAGES_DIR=
        lk_tty_detail "Flushing WP Rocket cache"
        { wp cli has-command "rocket clean" 2>/dev/null ||
            lk_wp_package_install wp-media/wp-rocket-cli:@stable; } &&
            lk_report_error -q wp rocket clean --confirm || true
    ); fi
}

function lk_wp_url_encode() {
    printf '%s' "$1" | php --run \
        'echo urlencode(stream_get_contents(STDIN));'
}

function lk_wp_json_encode() {
    printf '%s' "$1" | php --run \
        'echo substr(json_encode(stream_get_contents(STDIN)), 1, -1);'
}

function _lk_wp_maybe_apply() {
    local _LK_WP_MAYBE=1 STATUS=0
    if lk_is_false LK_WP_APPLY || { [ -z "${LK_WP_APPLY+1}" ] &&
        ! lk_tty_yn \
            "Run database updates and [re]apply WordPress settings?" Y; }; then
        _lk_wp_maybe_flush || STATUS=$?
        _lk_wp_maybe_migrate
    else
        lk_wp_apply
    fi && ((!STATUS))
}

function _lk_wp_maybe_flush() {
    lk_is_false LK_WP_FLUSH || { [ -z "${LK_WP_FLUSH+1}" ] &&
        ! lk_tty_yn "Flush WordPress rewrite rules and caches?" Y; } ||
        lk_wp_flush
}

function _lk_wp_maybe_migrate() {
    lk_is_false LK_WP_MIGRATE || { [ -z "${LK_WP_MIGRATE+1}" ] &&
        ! lk_tty_yn \
            "Run WordPress data migrations and [re]build indexes?" Y; } ||
        lk_wp_migrate
}

# lk_wp_rename_site [-s SITE_ROOT] NEW_URL
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
# - LK_WP_APPLY: run pending database updates and regenerate config files after
#   renaming (default: 1)
# - LK_WP_FLUSH: flush rewrite rules, caches and transients after renaming
#   (default: 1)
# - LK_WP_MIGRATE: run pending data migrations and rebuild indexes after
#   renaming (default: 1)
function lk_wp_rename_site() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local NEW_URL=${1-} OLD_URL=${LK_WP_OLD_URL-} \
        SITE_ROOT OLD_SITE_URL NEW_SITE_URL FILE CONST
    [ $# -eq 1 ] || lk_usage "Usage: $FUNCNAME [-s SITE_ROOT] NEW_URL" || return
    lk_is_uri "$1" || lk_warn "invalid URL: $1" || return
    SITE_ROOT=$(lk_wp_get_site_root) || return
    FILE=$SITE_ROOT/.lk-settings
    OLD_URL=${OLD_URL:-$(sed -n 's/^OLD_WP_HOME=//p' "$FILE" 2>/dev/null |
        grep -m1 . || lk_wp_get_site_address)} || return
    [ "$NEW_URL" != "$OLD_URL" ] ||
        lk_warn "site address not changed (set LK_WP_OLD_URL to override)" ||
        return
    OLD_SITE_URL=$(sed -n 's/^OLD_WP_SITEURL=//p' "$FILE" 2>/dev/null |
        grep -m1 . || lk_wp option get siteurl) || return
    NEW_SITE_URL=${OLD_SITE_URL/"$OLD_URL"/$NEW_URL}
    lk_tty_print "Renaming WordPress installation at" "$SITE_ROOT"
    lk_tty_detail \
        "Site address:" "$OLD_URL -> $LK_BOLD$NEW_URL$LK_RESET"
    lk_tty_detail \
        "WordPress address:" "$OLD_SITE_URL -> $LK_BOLD$NEW_SITE_URL$LK_RESET"
    _lk_wp_is_quiet || lk_tty_yn "Proceed?" Y || return
    for CONST in WP_HOME WP_SITEURL; do
        ! lk_wp config has "$CONST" || {
            lk_sed_i '' "/^OLD_${CONST}=/d" "$FILE" 2>/dev/null || true
            lk_wp config get "$CONST" | sed "s/^/OLD_${CONST}=/" >>"$FILE" &&
                lk_wp config delete "$CONST" || return
        }
    done
    lk_wp option update home "$NEW_URL" &&
        lk_wp option update siteurl "$NEW_SITE_URL" || return
    lk_is_false LK_WP_REPLACE ||
        { [ -z "${LK_WP_REPLACE+1}" ] &&
            ! lk_tty_yn "Replace the previous URL in all tables?" Y; } ||
        lk_wp_replace_url "$OLD_URL" "$NEW_URL" ||
        return
    _lk_wp_maybe_apply || return
    lk_tty_success "Site renamed successfully"
}

function _lk_wp_replace() {
    local PREFIX SKIP
    PREFIX=$(lk_wp_get_table_prefix) || return
    SKIP=(
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
    SKIP=("${SKIP[@]/#/$PREFIX}")
    lk_tty_detail "Replacing:" "$1 -> $2"
    local IFS=,
    "${_LK_WP_REPLACE_COMMAND:-lk_wp}" search-replace "$1" "$2" \
        --no-report \
        --all-tables-with-prefix \
        --skip-tables="${SKIP[*]}" \
        --skip-columns="guid" \
        2>"$STDERR" || lk_pass cat "$STDERR" >&2 ||
        lk_warn "WordPress search/replace failed"
}

# lk_wp_replace_url [-s SITE_ROOT] OLD_URL NEW_URL
function lk_wp_replace_url() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local OLD_URL=${1-} NEW_URL=${2-} REPLACE STDERR IFS _SEARCH _REPLACE
    [ $# -eq 2 ] ||
        lk_usage "Usage: $FUNCNAME [-s SITE_ROOT] OLD_URL NEW_URL" || return
    lk_test_all lk_is_uri "$@" || lk_warn "invalid URL" || return
    lk_tty_print "Performing WordPress search/replace"
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
    lk_mktemp_with STDERR || return
    unset IFS
    while read -r _SEARCH _REPLACE; do
        _lk_wp_replace "$_SEARCH" "$_REPLACE" || return
    done < <(printf '%q %q\n' "${REPLACE[@]}" | lk_uniq)
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
(?<=<\?php|;|^)$LK_h*define$LK_h*\($LK_h*(['\"])DB_(NAME|USER|PASSWORD|HOST)\1$LK_h*,\
$LK_h*('([^']+|\\\\')*'|\"([^\"\$]+|\\\\(\"|\\\$))*\")$LK_h*\)$LK_h*(;|\$)" |
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
        DB_NAME=${DB_NAME-} DB_USER=${DB_USER-} \
        DB_PASSWORD=${DB_PASSWORD-} DB_HOST=${DB_HOST-} \
        OUTPUT_FILE
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME SSH_HOST [REMOTE_PATH]" || return
    [ -n "$1" ] || lk_warn "no ssh host" || return
    REMOTE_PATH=${REMOTE_PATH%/}
    lk_tty_print "Preparing to dump remote WordPress database"
    [ -n "$DB_NAME" ] &&
        [ -n "$DB_USER" ] &&
        [ -n "$DB_PASSWORD" ] &&
        [ -n "$DB_HOST" ] || {
        lk_tty_print "Getting credentials"
        lk_tty_detail "Retrieving" "$1:$REMOTE_PATH/wp-config.php"
        WP_CONFIG=$(ssh "$1" cat "$REMOTE_PATH/wp-config.php") || return
        lk_tty_detail "Parsing WordPress configuration"
        SH=$(lk_wp_db_config <<<"$WP_CONFIG") &&
            eval "$SH" || return
    }
    if [ ! -t 1 ]; then
        lk_mysql_dump_remote "$1" "$DB_NAME"
    else
        OUTPUT_FILE=~/.lk-platform/cache/db/$1-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
        lk_tty_print "Initiating MySQL dump to" "$OUTPUT_FILE"
        install -d -m 00700 "${OUTPUT_FILE%/*}" &&
            lk_mysql_dump_remote "$1" "$DB_NAME" >"$OUTPUT_FILE"
    fi
}

# lk_wp_db_dump [SITE_ROOT]
function lk_wp_db_dump() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    local SITE_ROOT OUTPUT_FILE \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    SITE_ROOT=$(lk_wp_get_site_root) ||
        lk_usage "Usage: $FUNCNAME [SITE_ROOT]" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=${SITE_ROOT#~/}
        OUTPUT_FILE=localhost-${OUTPUT_FILE//\//_}-$(lk_date_ymdhms).sql.gz
        [ "$SITE_ROOT" = "${SITE_ROOT#"$PWD"}" ] &&
            OUTPUT_FILE=$PWD/$OUTPUT_FILE || {
            OUTPUT_FILE=~/.lk-platform/cache/db/$OUTPUT_FILE
            install -d -m 00700 "${OUTPUT_FILE%/*}" || return
        }
        [ -w "${OUTPUT_FILE%/*}" ] ||
            lk_warn "cannot write to ${OUTPUT_FILE%/*}" || return
    }
    lk_tty_print "Preparing to dump WordPress database"
    lk_tty_detail "Getting credentials"
    DB_NAME=$(lk_wp config get DB_NAME) &&
        DB_USER=$(lk_wp config get DB_USER) &&
        DB_PASSWORD=$(lk_wp config get DB_PASSWORD) &&
        DB_HOST=$(lk_wp config get DB_HOST) || return
    if [ ! -t 1 ]; then
        lk_mysql_dump "$DB_NAME"
    else
        lk_tty_print "Initiating MySQL dump to" "$OUTPUT_FILE"
        lk_mysql_dump "$DB_NAME" >"$OUTPUT_FILE"
    fi
}

# lk_wp_db_get_vars [-p PREFIX] [SITE_ROOT]
function lk_wp_db_get_vars() {
    local SITE_ROOT SH PREFIX=
    [ "${1-}" != -p ] || { PREFIX=$2 && shift 2; }
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    SITE_ROOT=$(lk_wp_get_site_root) || return
    SH=$(
        for OPTION in DB_NAME DB_USER DB_PASSWORD DB_HOST; do
            VALUE=$(lk_wp config get "$OPTION") || exit
            [ "${FUNCNAME[1]-}" = lk_wp_db_set_local ] ||
                printf 'declare '
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
    eval "$(_lk_wp_set_path "$@")"
    local SITE_ROOT SH DEFAULT_IDENTIFIER
    SITE_ROOT=$(lk_wp_get_site_root) || return
    LOCAL_DB_NAME=
    LOCAL_DB_USER=
    LOCAL_DB_PASSWORD=
    ! SH=$(lk_wp_db_get_vars -p LOCAL_ "$SITE_ROOT") || eval "$SH"
    LOCAL_DB_HOST=${LK_MYSQL_HOST:-localhost}
    if [ "${LOCAL_DB_NAME:+1}\
${LOCAL_DB_USER:+1}${LOCAL_DB_PASSWORD:+1}" = 111 ]; then
        lk_mysql_options_client_write \
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
        lk_mysql_options_client_write \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST" || return
        ! lk_mysql_connects 2>/dev/null || return 0
    }
    LOCAL_DB_PASSWORD=$(lk_random_password 24) &&
        lk_mysql_options_client_write \
            "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" "$LOCAL_DB_HOST"
}

# lk_wp_db_restore_local [-s SITE_ROOT] SQL_PATH [DB_NAME [DB_USER]]
function lk_wp_db_restore_local() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local LOCAL_DB_NAME LOCAL_DB_USER LOCAL_DB_PASSWORD LOCAL_DB_HOST \
        SITE_ROOT SH CONST LOCAL ACTIONS=() ACTION i=0 SUDO=1
    [ -f "$1" ] || lk_usage "\
Usage: $FUNCNAME [-s SITE_ROOT] SQL_PATH [DB_NAME [DB_USER]]" || return
    SITE_ROOT=$(lk_wp_get_site_root) &&
        SH=$(lk_wp_db_get_vars "$SITE_ROOT") && eval "$SH" &&
        lk_wp_db_set_local "$SITE_ROOT" "${@:2}" || return
    lk_tty_print "Preparing to restore WordPress database"
    _lk_wp_is_quiet || {
        lk_tty_detail "Backup file:" "$1"
        lk_tty_detail "WordPress installation:" "$SITE_ROOT"
        lk_tty_detail "Database:" "$LOCAL_DB_NAME@$LOCAL_DB_HOST"
        lk_tty_print "Actions pending:"
    }
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] || {
        ACTIONS[i++]=$(lk_quote_args \
            _lk_wp_tty_run -1=wp:5="${LOCAL_DB_PASSWORD::4}..." lk_wp \
            config set DB_PASSWORD "$LOCAL_DB_PASSWORD" --type=constant --quiet)
        _lk_wp_is_quiet || {
            lk_tty_detail "Reset MySQL password for user:" "$LOCAL_DB_USER"
            lk_tty_detail "Change DB_PASSWORD in wp-config.php"
        }
    }
    for CONST in DB_NAME DB_USER DB_HOST; do
        LOCAL=LOCAL_$CONST
        [ "${!CONST}" = "${!LOCAL}" ] || {
            ACTIONS[i++]=$(lk_quote_args _lk_wp_tty_run -1=wp lk_wp \
                config set "$CONST" "${!LOCAL}" --type=constant --quiet)
            _lk_wp_is_quiet ||
                lk_tty_detail "Change $CONST in wp-config.php to" "${!LOCAL}"
        }
    done
    _lk_wp_is_quiet || {
        lk_tty_detail "DROP and re-CREATE database:" \
            "$LOCAL_DB_NAME@$LOCAL_DB_HOST"
        lk_tty_detail "Restore" "$1"
        lk_tty_yn "Proceed?" Y || return
    }
    [ "$DB_PASSWORD" = "$LOCAL_DB_PASSWORD" ] || {
        [[ $USER =~ ^[-a-zA-Z0-9_]+$ ]] &&
            [[ $LOCAL_DB_NAME =~ ^$USER(_[-a-zA-Z0-9_]*)?$ ]] ||
            unset SUDO
        local LK_SUDO=${SUDO-${LK_SUDO-}}
        lk_maybe_trace "$LK_BASE/bin/lk-mysql-grant.sh" \
            "$LOCAL_DB_NAME" "$LOCAL_DB_USER" "$LOCAL_DB_PASSWORD" || return
    }
    lk_tty_print "Restoring WordPress database"
    for ACTION in ${ACTIONS+"${ACTIONS[@]}"}; do
        eval "$ACTION" || return
    done
    lk_tty_detail "Resetting database:" "$LOCAL_DB_NAME@$LOCAL_DB_HOST"
    lk_mysql <<SQL || return
DROP DATABASE IF EXISTS $(lk_mysql_escape_identifier "$LOCAL_DB_NAME");
CREATE DATABASE $(lk_mysql_escape_identifier "$LOCAL_DB_NAME");
SQL
    lk_tty_detail "Restoring backup file:" "$1"
    if [[ $1 =~ \.gz(ip)?$ ]]; then
        lk_pv "$1" | gunzip
    else
        lk_pv "$1"
    fi | lk_mysql_restore_filter | lk_mysql "$LOCAL_DB_NAME" ||
        lk_tty_error -r "Restore operation failed" || return
    lk_tty_success "Database restored successfully"
}

# lk_wp_db_myisam_to_innodb [-n]
#
# If -n is set, do not take a backup before conversion.
function lk_wp_db_myisam_to_innodb() { (
    BACKUP=1
    [ "${1-}" != -n ] || BACKUP=
    lk_tty_group -n \
        "Preparing to convert MyISAM tables in WordPress database to InnoDB"
    SH=$(lk_wp_db_get_vars) && eval "$SH" &&
        lk_mysql_options_client_write || return
    ! lk_mysql_innodb_only "$DB_NAME" ||
        lk_warn "no MyISAM tables in database '$DB_NAME'" || return 0
    _lk_wp_is_quiet || {
        if [ -z "$BACKUP" ]; then
            lk_tty_warning "Data loss may occur if conversion fails"
        else
            lk_tty_log "The database will be backed up before conversion"
        fi
        lk_tty_yn "Proceed?" Y || return
    }
    unset _LK_WP_MAINTENANCE_ON
    lk_wp_maintenance_enable &&
        { [ -z "$BACKUP" ] || lk_wp_db_dump; } &&
        lk_mysql_myisam_to_innodb "$DB_NAME" &&
        lk_wp_maintenance_maybe_disable
); }

# lk_wp_sync_files_from_remote SSH_HOST [REMOTE_PATH [LOCAL_PATH [RSYNC_ARG...]]]
function lk_wp_sync_files_from_remote() {
    local REMOTE_PATH=${2:-public_html} LOCAL_PATH KEEP_LOCAL EXCLUDE STATUS=0 \
        ARGS=(-vrlptH -x --delete "${@:4}")
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME SSH_HOST [REMOTE_PATH [LOCAL_PATH [RSYNC_ARG...]]]" || return
    # files that already exist on the local system will be added to --exclude
    KEEP_LOCAL=(
        wp-config.php
        .git
        ${LK_WP_SYNC_KEEP_LOCAL+"${LK_WP_SYNC_KEEP_LOCAL[@]}"}
    )
    EXCLUDE=(
        /**/.git
        /.maintenance
        /.tmb
        "php_error*.log"
        {"error*",debug}"?log"
        /wp-content/{backup,cache,litespeed,upgrade,updraft}/
        /wp-content/uploads/{backup,cache,wp-file-manager-pro/fm_backup}/
        ${LK_WP_SYNC_EXCLUDE+"${LK_WP_SYNC_EXCLUDE[@]}"}
    )
    LOCAL_PATH=${3:-$(lk_wp_get_site_root 2>/dev/null)} ||
        LOCAL_PATH=~/public_html
    lk_tty_print "Preparing to sync WordPress files"
    REMOTE_PATH=${REMOTE_PATH%/}
    LOCAL_PATH=${LOCAL_PATH%/}
    _lk_wp_is_quiet || {
        lk_tty_detail "Source:" "$1:$REMOTE_PATH"
        lk_tty_detail "Destination:" "$LOCAL_PATH"
    }
    for FILE in "${KEEP_LOCAL[@]}"; do
        [ ! -e "$LOCAL_PATH/$FILE" ] || EXCLUDE+=("/$FILE")
    done
    ARGS+=("${EXCLUDE[@]/#/--exclude=}")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    lk_tty_detail "Local files will be overwritten with command:" \
        "rsync ${ARGS[*]}"
    _lk_wp_is_quiet || ! lk_tty_yn "Perform a trial run first?" N ||
        rsync --dry-run "${ARGS[@]}" | "${PAGER:-less}" >&2 || true
    lk_tty_yn "LOCAL CHANGES WILL BE PERMANENTLY LOST. Proceed?" Y ||
        return
    [ -d "$LOCAL_PATH" ] || mkdir -p "$LOCAL_PATH" || return
    rsync "${ARGS[@]}" || STATUS=$?
    [ "$STATUS" -eq 0 ] &&
        lk_tty_success "File sync completed successfully" ||
        lk_tty_error "File sync failed"
    return "$STATUS"
}

# lk_wp_apply [SITE_ROOT]
#
# Run pending database updates, regenerate config files, flush caches (see
# lk_wp_flush), and run pending data migrations (see lk_wp_migrate). Recommended
# after moving or updating WordPress.
function lk_wp_apply() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    eval "$(_lk_wp_set_admin_url)"
    local FILE STATUS=0
    lk_tty_print "Running database updates and [re]applying WordPress settings"
    lk_tty_detail "Updating core database"
    lk_report_error lk_wp core update-db || return
    if wp cli has-command "wc update" 2>/dev/null; then
        lk_tty_detail "Updating WooCommerce tables"
        lk_report_error -q wp wc update || return
    fi
    if lk_wp plugin is-active wp-rocket; then (
        WP_CLI_PACKAGES_DIR=
        lk_tty_detail "Regenerating WP Rocket files"
        lk_wp cli has-command "rocket regenerate" ||
            lk_wp_package_install wp-media/wp-rocket-cli:@stable || return
        for FILE in htaccess advanced-cache config; do
            # `wp rocket regenerate` is known to exit non-zero after running
            # successfully, so ignore any errors
            lk_report_error -q wp rocket regenerate --file="$FILE" || true
        done
    ); fi
    # Updating `email-log` without reactivating can leave it non-operational
    if lk_wp plugin is-active email-log; then
        lk_tty_detail "Re-activating Email Log"
        lk_report_error lk_wp plugin deactivate email-log &&
            lk_report_error lk_wp plugin activate email-log || STATUS=$?
    fi
    if [ -z "${_LK_WP_MAYBE-}" ]; then
        lk_wp_flush "$@" || STATUS=$?
        lk_wp_migrate "$@"
    else
        _lk_wp_maybe_flush || STATUS=$?
        _lk_wp_maybe_migrate
    fi && ((!STATUS))
}

# lk_wp_migrate [SITE_ROOT]
function lk_wp_migrate() {
    eval "$(_lk_wp_set_path "$@")"
    eval "$(_lk_wp_set_admin_url)"
    local STATUS=0 COMMAND
    lk_tty_print "Running WordPress data migrations and [re]building indexes"
    if wp cli has-command "yoast index" 2>/dev/null; then
        lk_tty_detail "Building Yoast index"
        lk_report_error -q wp yoast index || STATUS=$?
    fi
    if wp cli has-command "action-scheduler migrate" 2>/dev/null; then
        COMMAND="wp --path=$(lk_ere_escape \
            "$_LK_WP_PATH") action-scheduler migrate" || return
        pgrep -fu "$USER" "([^[:alnum:]_]|^)$COMMAND" >/dev/null &&
            lk_warn "Scheduled actions are already being migrated" || {
            local LOG_FILE=${_LK_WP_PATH%/*}/log/cron.log
            [ -w "$LOG_FILE" ] || lk_mktemp_with LOG_FILE
            lk_tty_detail "Migrating scheduled actions in the background"
            lk_tty_log "Background task output will be logged to:" "$LOG_FILE"
            LK_LOG_FILE=$LOG_FILE \
                nohup "$LK_BASE/lib/platform/log.sh" -i wordpress -- \
                wp --path="$_LK_WP_PATH" action-scheduler migrate &>/dev/null &
            disown
        }
    fi
    return "$STATUS"
}

# lk_wp_enable_system_cron [-s SITE_ROOT] [INTERVAL]
function lk_wp_enable_system_cron() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local INTERVAL=${1:-1} SITE_ROOT PHP LOG_FILE ARGS ARGS_RE \
        COMMAND REGEX CRONTAB
    SITE_ROOT=$(lk_wp_get_site_root) &&
        PHP=$(lk_wp_curl -fsS "/php-sysinfo" | jq -r '.php.version') &&
        PHP=$(type -P "php$PHP") || return
    LOG_FILE=${SITE_ROOT%/*}/log/cron.log
    [ -w "$LOG_FILE" ] || LOG_FILE=~/cron.log
    lk_mapfile ARGS <(printf '%q\n' \
        "$LK_BASE/lib/platform/log.sh" "--path=$SITE_ROOT")
    COMMAND=$(printf "WP_CLI_PHP=%q LK_LOG_FILE=%q %s -i wordpress -- \
wp_if_running %s cron event run --due-now" "$PHP" "$LOG_FILE" "${ARGS[@]::2}")
    lk_tty_print "Using crontab to schedule WP-Cron in" "$SITE_ROOT"
    lk_wp config get DISABLE_WP_CRON --type=constant 2>/dev/null |
        grep -Fx 1 >/dev/null ||
        lk_wp config set DISABLE_WP_CRON true --type=constant --raw ||
        return
    # Remove legacy cron job
    lk_crontab_remove_command "$SITE_ROOT/wp-cron.php" || return
    # Try to keep everything before and after COMMAND, e.g. environment
    # variables and redirections
    lk_mapfile ARGS_RE <(lk_arr ARGS | lk_ere_escape)
    REGEX=$(lk_regex_expand_whitespace " (WP_CLI_PHP=$LK_H+ )?(LK_LOG_FILE=$LK_H+ )?\
${ARGS_RE[0]} .+ ${ARGS_RE[1]} cron event run --due-now( |\$)")
    [ $# -eq 0 ] && CRONTAB=$(lk_crontab_get "^$LK_h*[^#[:blank:]].*$REGEX" |
        head -n1 | awk -v "c=$COMMAND" -v "r=${REGEX//\\/\\\\}" \
        '{if(split($0,a,r)!=2)exit 1;printf("%s %s",a[1],c);if(a[2])printf(" %s",a[2])}') ||
        # But if that's not possible, add or replace the whole job
        { [ "$INTERVAL" -lt 60 ] &&
            CRONTAB="*/$INTERVAL * * * * $COMMAND >/dev/null" ||
            CRONTAB="42 * * * * $COMMAND >/dev/null"; }
    lk_crontab_apply "$REGEX" "$CRONTAB"
}

# lk_wp_disable_cron [-s SITE_ROOT]
function lk_wp_disable_cron() {
    [ "${1-}" != -s ] || { eval "$(_lk_wp_set_path "$2")" && shift 2; }
    local SITE_ROOT
    SITE_ROOT=$(lk_wp_get_site_root) || return
    lk_tty_print "Disabling WP-Cron in" "$SITE_ROOT"
    lk_wp config get DISABLE_WP_CRON --type=constant 2>/dev/null |
        grep -Fx 1 >/dev/null ||
        lk_wp config set DISABLE_WP_CRON true --type=constant --raw ||
        return
    lk_crontab_remove_command "$SITE_ROOT/wp-cron.php" &&
        lk_crontab_remove_command "--path=$SITE_ROOT"
}

function lk_wp_maintenance_get_php() {
    printf '<?php $upgrading = time(); ?>'
}

# lk_wp_maintenance_enable [SITE_ROOT]
function lk_wp_maintenance_enable() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    local SITE_ROOT ACTIVE=1
    SITE_ROOT=$(lk_wp_get_site_root) || return
    lk_wp maintenance-mode is-active &>/dev/null || ACTIVE=0
    [ -n "${_LK_WP_MAINTENANCE_ON-}" ] ||
        _LK_WP_MAINTENANCE_ON=$ACTIVE
    ((ACTIVE)) ||
        lk_tty_print "Enabling maintenance mode"
    # Always activate explicitly, in case $upgrading is about to expire
    lk_wp_maintenance_get_php >"$SITE_ROOT/.maintenance"
}

# lk_wp_maintenance_disable [SITE_ROOT]
function lk_wp_maintenance_disable() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    local SITE_ROOT
    SITE_ROOT=$(lk_wp_get_site_root) || return
    ! lk_wp maintenance-mode is-active &>/dev/null ||
        lk_tty_print "Disabling maintenance mode"
    rm -f "$SITE_ROOT/.maintenance"
}

# lk_wp_maintenance_maybe_disable [SITE_ROOT]
function lk_wp_maintenance_maybe_disable() {
    ((${_LK_WP_MAINTENANCE_ON-1} == 1)) ||
        lk_wp_maintenance_disable "$@"
}

# lk_wp_set_permissions [SITE_ROOT]
function lk_wp_set_permissions() {
    [ $# -eq 0 ] || eval "$(_lk_wp_set_path "$@")"
    local SITE_ROOT OWNER LOG_FILE CHANGES
    SITE_ROOT=$(lk_wp_get_site_root) &&
        SITE_ROOT=$(lk_realpath "$SITE_ROOT") || return
    if lk_will_elevate; then
        OWNER=$(lk_file_owner "$SITE_ROOT/..") &&
            LOG_FILE=$(lk_mktemp) || return
        lk_tty_print "Setting file ownership in" "$SITE_ROOT"
        lk_tty_detail "Owner:" "$OWNER"
        CHANGES=$(lk_sudo gnu_chown -Rhc "$OWNER" "$SITE_ROOT" |
            tee -a "$LOG_FILE" | wc -l | tr -d ' ') || return
        lk_tty_detail "Changes:" "$CHANGES"
        ! ((CHANGES)) &&
            lk_delete_on_exit "$LOG_FILE" ||
            lk_tty_detail "Changes logged to:" "$LOG_FILE"
    else
        lk_tty_warning "Unable to set owner (not running as root)"
    fi
    lk_dir_set_modes "$SITE_ROOT" \
        "" \
        "${LK_WP_MODE_DIR:-0750}" "${LK_WP_MODE_FILE:-0640}" \
        ".*/wp-content/(cache|uploads|w3tc-config)" \
        "${LK_WP_MODE_WRITABLE_DIR:-2770}" "${LK_WP_MODE_WRITABLE_FILE:-0660}" \
        '.*/\.git/objects/([0-9a-f]{2}|pack)/.*' \
        0555 0444
}

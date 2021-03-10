#!/bin/bash

# shellcheck disable=SC2029

lk_bin_depth=1 include=wordpress . lk-bash-load.sh || exit

REMOTE_PATH=public_html
LOCAL_PATH=$(lk_wp_get_site_root 2>/dev/null) ||
    LOCAL_PATH=~/public_html
MAINTENANCE=
DEACTIVATE=()
RENAME=
SSL=0
EXCLUDE=()
DEFAULT_DB_NAME=
DEFAULT_DB_USER=

LK_USAGE="\
Usage: ${0##*/} [OPTION...] SSH_HOST [-- RSYNC_ARG...]

Migrate a WordPress site from SSH_HOST to the local system, overwriting local
changes if previously migrated.

Options:
  -s, --source=PATH         sync files from PATH on remote system
                            (default: ~/public_html)
  -d, --dest=PATH           sync files to PATH on local system
                            (default: site root if WordPress installation found
                            in working directory, or ~/public_html)
  -m, --maintenance=MODE    specify remote WordPress maintenance MODE
                            (default: <ask>)
  -p, --deactivate=PLUGIN   deactivate the specified WordPress plugin after
                            migration (may be given multiple times)
  -r, --rename=URL          change site address to URL after migration
  -c, --ssl-cert            attempt to retrieve SSL certificate, CA bundle and
                            private key from remote system (cPanel only)
  -e, --exclude=PATTERN     exclude files matching PATTERN
                            (may be given multiple times)
      --db-name=DB_NAME     if local connection fails, use database DB_NAME
      --db-user=DB_USER     if local connection fails, use MySQL user DB_USER

Maintenance modes:
  ignore        don't enable
  on            enable during migration
  indefinite    enable permanently

Maintenance mode is always enabled on the local system during migration."

lk_getopt "s:d:m:p:r:ce:" \
    "source:,dest:,maintenance:,deactivate:,rename:,ssl-cert,exclude:,db-name:,db-user:"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -s | --source)
        REMOTE_PATH=$1
        shift
        ;;
    -d | --dest)
        LOCAL_PATH=$1
        shift
        ;;
    -m | --maintenance)
        [[ $1 =~ ^(ignore|on|indefinite)$ ]] ||
            lk_warn "invalid remote maintenance mode: $1" || lk_usage
        MAINTENANCE=$1
        shift
        ;;
    -p | --deactivate)
        DEACTIVATE+=("$1")
        shift
        ;;
    -r | --rename)
        RENAME=$1
        lk_is_uri "$1" || lk_warn "invalid URL: $1" || lk_usage
        shift
        ;;
    -c | --ssl-cert)
        SSL=1
        ;;
    -e | --exclude)
        EXCLUDE+=("$1")
        shift
        ;;
    --db-name)
        DEFAULT_DB_NAME=$1
        shift
        ;;
    --db-user)
        DEFAULT_DB_USER=$1
        shift
        ;;
    --)
        break
        ;;
    esac
done

[ $# -ge 1 ] || lk_usage
SSH_HOST=$1
shift

function is_final() {
    [ "$MAINTENANCE" = indefinite ]
}

function maybe_disable_remote_maintenance() {
    if [ "$MAINTENANCE" = on ]; then
        MAINTENANCE=
        lk_console_message "[remote] Disabling maintenance mode"
        lk_console_detail "Deleting" "$SSH_HOST:$REMOTE_PATH/.maintenance"
        ssh "$SSH_HOST" \
            "bash -c 'rm \"\$1/.maintenance\"'" bash "$REMOTE_PATH" ||
            lk_warn "\
Error deleting $SSH_HOST:$REMOTE_PATH/.maintenance
Maintenance mode may have been disabled early by another process"
    fi
}

MAINTENANCE_PHP='<?php $upgrading = time(); ?>'
REMOTE_PATH=${REMOTE_PATH%/}
LOCAL_PATH=${LOCAL_PATH%/}

LK_WP_QUIET=1

lk_log_output

lk_console_message "Preparing WordPress migration"
lk_console_detail "[remote] Source:" "$SSH_HOST:$REMOTE_PATH"
lk_console_detail "[local] Destination:" "$LOCAL_PATH"
[ -z "$MAINTENANCE" ] ||
    lk_console_detail "Remote maintenance mode:" "$MAINTENANCE"
lk_console_detail "Plugins to deactivate:" "$([ ${#DEACTIVATE[@]} -eq 0 ] &&
    echo "<none>" ||
    lk_echo_array DEACTIVATE)"
[ -z "$RENAME" ] ||
    lk_console_detail "Rename site to:" "$RENAME"
lk_console_detail "Copy remote SSL certificate:" \
    "$(lk_is_true SSL && echo "yes" || echo "no")"
lk_console_detail "Local WP-Cron:" "$(
    [ "$MAINTENANCE" = indefinite ] &&
        echo "enable" ||
        echo "disable"
)"

lk_console_detail "Exclude files:" "$([ ${#EXCLUDE[@]} -eq 0 ] &&
    echo "<none>" ||
    lk_echo_array EXCLUDE)"

lk_confirm "Proceed?" Y

lk_console_message "Enabling WordPress maintenance mode"
[ -n "$MAINTENANCE" ] || {
    lk_console_detail "\
To minimise downtime, successfully complete at least one migration without
enabling maintenance mode on the remote site, then enable it for the final
migration (immediately before updating DNS)"
    lk_console_detail "\
Once enabled, WordPress will remain in maintenance mode indefinitely"
    ! lk_confirm "Enable maintenance mode on remote system? " N ||
        MAINTENANCE=indefinite
}
lk_console_detail "[local] Creating" "$LOCAL_PATH/.maintenance"
echo -n "$MAINTENANCE_PHP" >"$LOCAL_PATH/.maintenance"
if [[ $MAINTENANCE =~ ^(on|indefinite)$ ]]; then
    lk_console_detail "[remote] Creating" "$SSH_HOST:$REMOTE_PATH/.maintenance"
    ssh "$SSH_HOST" "bash -c 'cat >\"\$1/.maintenance\"'" bash \
        "$REMOTE_PATH" <<<"$MAINTENANCE_PHP"
fi

! is_final || {
    lk_console_message "Waiting 60 seconds for active requests to complete"
    sleep 60
}

# Migrate files
RSYNC_ARGS=(${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"} "$@")
LK_NO_INPUT=1 \
    lk_wp_sync_files_from_remote "$SSH_HOST" "$REMOTE_PATH" "$LOCAL_PATH"

# Migrate database
DB_FILE=~/.lk-platform/cache/db/$SSH_HOST-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
install -d -m 00700 "${DB_FILE%/*}"
lk_wp_db_dump_remote "$SSH_HOST" "$REMOTE_PATH" >"$DB_FILE"
maybe_disable_remote_maintenance
cd "$LOCAL_PATH"
LK_NO_INPUT=1 \
    lk_wp_db_restore_local "$DB_FILE" "$DEFAULT_DB_NAME" "$DEFAULT_DB_USER"
lk_console_message "Refreshing salts defined in wp-config.php"
lk_wp config shuffle-salts
if [ ${#DEACTIVATE[@]} -gt 0 ]; then
    ACTIVE_PLUGINS=($(lk_wp plugin list --status=active --field=name))
    DEACTIVATE=($(comm -12 \
        <(lk_echo_array ACTIVE_PLUGINS | sort -u) \
        <(lk_echo_array DEACTIVATE | sort -u)))
    [ ${#DEACTIVATE[@]} -eq 0 ] || {
        lk_console_item \
            "Deactivating plugins:" $'\n'"$(lk_echo_array DEACTIVATE)"
        lk_wp plugin deactivate "${DEACTIVATE[@]}"
    }
fi

[ -z "$RENAME" ] ||
    LK_WP_QUIET=1 LK_WP_REPLACE=1 LK_WP_REAPPLY=0 LK_WP_FLUSH=0 \
        LK_WP_REPLACE_COMMAND=wp \
        lk_wp_rename_site "$RENAME"
lk_wp_reapply_config
lk_wp_flush

if lk_is_true SSL; then
    SITE_ADDR=$(lk_wp_get_site_address) &&
        [[ $SITE_ADDR =~ ^https?://(www\.)?(.*) ]] &&
        lk_cpanel_get_ssl_cert "$SSH_HOST" "${BASH_REMATCH[2]}"
fi || true

if is_final; then
    lk_console_warning "Enabling WP-Cron"
    lk_wp_enable_system_cron
else
    lk_console_warning "Disabling WP-Cron (remote site still online)"
    lk_wp_disable_cron
fi

lk_console_message "[local] Disabling maintenance mode"
lk_console_detail "Deleting" "$LOCAL_PATH/.maintenance"
rm "$LOCAL_PATH/.maintenance" ||
    lk_warn "\
Error deleting $LOCAL_PATH/.maintenance
Maintenance mode may have been disabled early by another process"

lk_console_success "Migration completed successfully"

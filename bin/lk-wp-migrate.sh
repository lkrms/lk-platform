#!/bin/bash
# shellcheck disable=SC2015,SC2016,SC2029,SC2034

lk_bin_depth=1 include=wordpress . lk-bash-load.sh || exit

REMOTE_PATH=public_html
LOCAL_PATH=$(lk_wp_get_site_root 2>/dev/null) ||
    LOCAL_PATH=$HOME/public_html
MAINTENANCE=
RENAME=
SSL=0
EXCLUDE=()
DEFAULT_DB_NAME=
DEFAULT_DB_USER=

lk_wp_db_set_local "$LOCAL_PATH"

LK_USAGE="\
Usage: ${0##*/} [OPTION...] SSH_HOST

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

lk_check_args
OPTS=$(
    gnu_getopt --options "s:d:m:r:ce:" \
        --longoptions "yes,source:,dest:,maintenance:,rename:,ssl-cert,exclude:,db-name:,db-user:" \
        --name "${0##*/}" \
        -- "$@"
) || lk_usage
eval "set -- $OPTS"

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
[ -z "$RENAME" ] ||
    lk_console_detail "Local site address:" "$RENAME"
lk_console_detail "Copy remote SSL certificate:" \
    "$(lk_is_true "$SSL" && echo "yes" || echo "no")"
lk_console_detail "Local WP-Cron:" "$(
    [ "$MAINTENANCE" = indefinite ] &&
        echo "enable" ||
        echo "disable"
)"

lk_console_detail "Excluded files:" "$([ ${#EXCLUDE[@]} -eq 0 ] &&
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

# Migrate files
RSYNC_ARGS=(${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"})
LK_NO_INPUT=1 \
    lk_wp_sync_files_from_remote "$SSH_HOST" "$REMOTE_PATH" "$LOCAL_PATH"

# Migrate database
DB_FILE=~/$SSH_HOST-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
lk_wp_db_dump_remote "$SSH_HOST" "$REMOTE_PATH" >"$DB_FILE"
maybe_disable_remote_maintenance
cd "$LOCAL_PATH"
LK_NO_INPUT=1 \
    lk_wp_db_restore_local "$DB_FILE" "$DEFAULT_DB_NAME" "$DEFAULT_DB_USER"
[ -z "$RENAME" ] ||
    LK_WP_QUIET=1 LK_WP_REPLACE=1 LK_WP_FLUSH=0 \
        LK_WP_REPLACE_COMMAND=wp \
        lk_wp_rename_site "$RENAME"
lk_wp_flush

if lk_is_true "$SSL"; then
    SITE_ADDR=$(lk_wp_get_site_address) &&
        [[ $SITE_ADDR =~ ^https?://(www\.)?(.*) ]] &&
        lk_cpanel_get_ssl_cert "$SSH_HOST" "${BASH_REMATCH[2]}"
fi || true

if [ "$MAINTENANCE" = indefinite ]; then
    lk_console_warning "Enabling WP-Cron (remote site offline)"
    lk_wp_enable_system_cron
else
    lk_console_warning0 "Disabling WP-Cron (remote site online)"
    lk_wp_disable_cron
fi

lk_console_message "[local] Disabling maintenance mode"
lk_console_detail "Deleting" "$LOCAL_PATH/.maintenance"
rm "$LOCAL_PATH/.maintenance" ||
    lk_warn "\
Error deleting $LOCAL_PATH/.maintenance
Maintenance mode may have been disabled early by another process"

lk_console_success "Migration completed successfully"

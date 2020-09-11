#!/bin/bash
# shellcheck disable=SC2015,SC2016,SC2029,SC2034

lk_bin_depth=1 include=wordpress . lk-bash-load.sh || exit

REMOTE_PATH=public_html
LOCAL_PATH=$(lk_wp_get_site_root 2>/dev/null) ||
    LOCAL_PATH=$HOME/public_html
MAINTENANCE=
EXCLUDE=()
DEFAULT_DB_NAME=
DEFAULT_DB_USER=

lk_wp_db_set_local "$LOCAL_PATH"

USAGE="\
Usage:
  ${0##*/} [OPTION...] <SSH_HOST>

Migrate a WordPress site from SSH_HOST to the local system, overwriting local
changes if previously migrated.

Options:
  -s, --source <PATH>       sync files from PATH on remote system
                            (default: $REMOTE_PATH)
  -d, --dest <PATH>         sync files to PATH on local system
                            (default: $LOCAL_PATH)
  -m, --maintenance <ignore|on|indefinite>
                            control WordPress maintenance mode on remote system
                                ignore:     don't enable
                                on:         enable during migration
                                indefinite: enable permanently
                            (default: ${MAINTENANCE:-<ask>})
  -e, --exclude <PATTERN>   exclude files matching PATTERN
                            (may be given multiple times)
      --db-name <DB_NAME>   if local connection fails, use database DB_NAME
                            (default for $LOCAL_PATH: $LOCAL_DB_NAME)
      --db-user <DB_USER>   if local connection fails, use MySQL user DB_USER
                            (default for $LOCAL_PATH: $LOCAL_DB_USER)

Maintenance mode is always enabled on the local system during migration."

OPTS=$(
    gnu_getopt --options "s:d:m:e:" \
        --longoptions "--source:,--dest:,--maintenance:,--exclude:,--db-name:,--db-user:" \
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
        ;;&
    -d | --dest)
        LOCAL_PATH=$1
        ;;&
    -m | --maintenance)
        case "$1" in
        ignore | on | indefinite)
            MAINTENANCE=$1
            ;;
        *)
            lk_usage
            ;;
        esac
        ;;&
    -e | --exclude)
        EXCLUDE+=("$1")
        ;;&
    --db-name)
        DEFAULT_DB_NAME=$1
        ;;&
    --db-user)
        DEFAULT_DB_USER=$1
        ;;&
    --)
        break
        ;;
    *)
        shift
        ;;
    esac
done

case "$#" in
1)
    SSH_HOST=$1
    ;;
*)
    lk_usage
    ;;
esac

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
lk_console_detail "Local WP-Cron:" "$(
    [ "$MAINTENANCE" = indefinite ] &&
        echo "enable" ||
        echo "disable"
)"

lk_console_detail "Excluded files:" "$([ "${#EXCLUDE[@]}" -eq 0 ] &&
    echo "<none>" ||
    lk_echo_array EXCLUDE)"

lk_no_input || lk_confirm "Proceed?" Y

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
lk_wp_sync_files_from_remote "$SSH_HOST" "$REMOTE_PATH" "$LOCAL_PATH"

# Migrate database
DB_FILE=~/$SSH_HOST-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
lk_wp_db_dump_remote "$SSH_HOST" "$REMOTE_PATH" >"$DB_FILE"
maybe_disable_remote_maintenance
cd "$LOCAL_PATH"
LK_NO_INPUT=1 \
    lk_wp_db_restore_local "$DB_FILE" "$DEFAULT_DB_NAME" "$DEFAULT_DB_USER"
lk_wp_flush

if [ "$MAINTENANCE" = indefinite ]; then
    lk_console_warning "Enabling WP-Cron (remote site offline)"
    lk_wp_enable_system_cron
else
    lk_console_warning "Disabling WP-Cron (remote site online)"
    lk_wp_disable_cron
fi

lk_console_message "[local] Disabling maintenance mode"
lk_console_detail "Deleting" "$LOCAL_PATH/.maintenance"
rm "$LOCAL_PATH/.maintenance" ||
    lk_warn "\
Error deleting $LOCAL_PATH/.maintenance
Maintenance mode may have been disabled early by another process"

lk_console_log "Migration completed successfully"

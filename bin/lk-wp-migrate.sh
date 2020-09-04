#!/bin/bash
# shellcheck disable=SC2016,SC2029,SC2034

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
        lk_console_message "Disabling maintenance mode on remote site"
        lk_console_detail "Deleting" "$SSH_HOST:$REMOTE_PATH/.maintenance"
        ssh "$SSH_HOST" \
            "bash -c 'rm \"\$2/.maintenance\"'" bash "$REMOTE_PATH" ||
            lk_warn "\
Error deleting $SSH_HOST:$REMOTE_PATH/.maintenance
Maintenance mode may have been disabled early by another process"
    fi
}

MAINTENANCE_PHP='<?php $upgrading = time(); ?>'
REMOTE_PATH=${REMOTE_PATH%/}
LOCAL_PATH=${LOCAL_PATH%/}

[ -d "$LOCAL_PATH" ] || lk_warn "not a local directory: $LOCAL_PATH" || true

lk_console_message "Enabling maintenance mode"
lk_console_detail "Creating" "$LOCAL_PATH/.maintenance"
echo -n "$MAINTENANCE_PHP" >"$LOCAL_PATH/.maintenance"
[ -n "$MAINTENANCE" ] || {
    lk_console_detail "\
If this is the final sync before DNS cutover, maintenance mode should be
enabled on the remote site"
    lk_console_detail "\
To minimise downtime, complete an initial sync without enabling
maintenance mode, then sync again"
}
if [[ $MAINTENANCE =~ ^(on|indefinite)$ ]] ||
    lk_confirm "Enable maintenance mode on remote site?" N; then
    lk_console_detail "Creating" "$SSH_HOST:$REMOTE_PATH/.maintenance"
    ssh "$SSH_HOST" \
        "bash -c 'echo -n \"\$1\" >\"\$2/.maintenance\"'" bash \
        "$MAINTENANCE_PHP" "$REMOTE_PATH"
fi

# Migrate files
RSYNC_ARGS=(${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"})
lk_wp_sync_files_from_remote "$SSH_HOST" "$REMOTE_PATH" "$LOCAL_PATH"

# Migrate database
DB_FILE=~/$SSH_HOST-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
lk_wp_db_dump_remote "$SSH_HOST" "$REMOTE_PATH" >"$DB_FILE"
maybe_disable_remote_maintenance
cd "$LOCAL_PATH"
lk_wp_db_restore_local "$DB_FILE" "$DEFAULT_DB_NAME" "$DEFAULT_DB_USER"
lk_wp_flush

lk_console_message "Disabling maintenance mode"
lk_console_detail "Deleting" "$LOCAL_PATH/.maintenance"
rm "$LOCAL_PATH/.maintenance" ||
    lk_warn "\
Error deleting $LOCAL_PATH/.maintenance
Maintenance mode may have been disabled early by another process"

lk_console_message "Migration completed successfully" "$LK_GREEN"

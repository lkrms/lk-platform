#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_include wordpress

REMOTE_PATH=public_html
LOCAL_PATH=$(lk_wp_get_site_root 2>/dev/null) ||
    LOCAL_PATH=~/public_html
MAINTENANCE=
DEACTIVATE=()
RENAME=
INNODB=0
SSL=0
SHUFFLE_SALTS=0
EXCLUDE=()
DEFAULT_DB_NAME=
DEFAULT_DB_USER=
NO_WAIT=

LK_USAGE="\
Usage: ${0##*/} [OPTION...] SSH_HOST [-- RSYNC_ARG...]

Migrate a WordPress site from SSH_HOST to the local system, overwriting local
changes if previously migrated.

Options:
  -s, --source=PATH         sync files from PATH on remote system
                            (default: ~/public_html)
  -d, --dest=PATH           sync files to PATH on local system
                            (default: ~/public_html if WordPress not found in
                            current directory, otherwise root of installation)
  -m, --maintenance=MODE    specify remote WordPress maintenance MODE
                            (default: ignore)
  -p, --deactivate=PLUGIN   deactivate the specified WordPress plugin after
                            migration (may be given multiple times)
  -r, --rename=URL          change site address to URL after migration
  -i, --innodb              convert any MyISAM tables to InnoDB after migration
  -c, --ssl-cert            attempt to retrieve TLS certificate, CA bundle and
                            private key from remote system (cPanel only)
  -t, --shuffle-salts       refresh salts defined in wp-config.php
  -e, --exclude=PATTERN     exclude files matching PATTERN
                            (may be given multiple times)
      --db-name=DB_NAME     if local connection fails, use database DB_NAME
      --db-user=DB_USER     if local connection fails, use MySQL user DB_USER
      --no-wait             skip 60-second delay after activating permanent
                            maintenance mode on remote system

Maintenance modes (for remote system only):
  ignore/off    do not activate or deactivate
  on            activate during migration, deactivate when done
  permanent     activate during migration, do not deactivate

On the local system, maintenance mode is always active during migration, and is
restored after a successful migration.

For minimal downtime, complete one or more migrations without activating
maintenance mode on the remote system, then run the final migration with
'--maintenance=permanent' before updating DNS."

lk_getopt "s:d:m:p:r:icte:" \
    "source:,dest:,maintenance:,deactivate:,rename:,innodb,ssl-cert,shuffle-salts,exclude:,db-name:,db-user:,no-wait"
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
        [[ $1 =~ ^(ignore|off|on|permanent)$ ]] ||
            lk_warn "invalid remote maintenance mode: $1" || lk_usage
        MAINTENANCE=${1/off/ignore}
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
    -i | --innodb)
        INNODB=1
        ;;
    -c | --ssl-cert)
        SSL=1
        ;;
    -t | --shuffle-salts)
        SHUFFLE_SALTS=1
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
    --no-wait)
        NO_WAIT=1
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
    [ "$MAINTENANCE" = permanent ]
}

function maybe_disable_remote_maintenance() {
    if [ "$MAINTENANCE" = on ]; then
        MAINTENANCE=
        lk_console_message "[remote] Disabling maintenance mode"
        lk_console_detail "Deleting" "$SSH_HOST:$REMOTE_PATH/.maintenance"
        ssh "$SSH_HOST" \
            '/bin/sh -c '\''rm "$1/.maintenance"'\''' sh "$REMOTE_PATH" ||
            lk_warn "\
Error deleting $SSH_HOST:$REMOTE_PATH/.maintenance
Maintenance mode may have been disabled early by another process"
    fi
}

REMOTE_PATH=${REMOTE_PATH%/}
LOCAL_PATH=${LOCAL_PATH%/}
STATUS=0

_LK_WP_QUIET=1

lk_log_start
lk_start_trace

lk_console_message "Preparing WordPress migration"
lk_console_detail "[remote] Source:" "$SSH_HOST:$REMOTE_PATH"
lk_console_detail "[local] Destination:" "$LOCAL_PATH"
lk_console_detail "Remote maintenance mode:" "${MAINTENANCE:-ignore}"
lk_console_detail "Plugins to deactivate:" "$([ ${#DEACTIVATE[@]} -eq 0 ] &&
    echo "<none>" ||
    lk_echo_array DEACTIVATE)"
[ -z "$RENAME" ] ||
    lk_console_detail "Rename site to:" "$RENAME"
lk_console_detail "Copy remote TLS certificate:" \
    "$( ((SSL)) && echo yes || echo no)"
lk_console_detail "Refresh salts in local wp-config.php:" \
    "$( ((SHUFFLE_SALTS)) && echo yes || echo no)"
lk_console_detail "Convert local MyISAM tables to InnoDB:" \
    "$( ((INNODB)) && echo yes || echo no)"
lk_console_detail "Local WP-Cron:" \
    "$([ "$MAINTENANCE" = permanent ] && echo enable || echo disable)"

lk_console_detail "Exclude files:" "$([ ${#EXCLUDE[@]} -eq 0 ] &&
    echo "<none>" ||
    lk_echo_array EXCLUDE)"

lk_confirm "Proceed?" Y

lk_console_message "Enabling WordPress maintenance mode"
lk_console_detail "[local] Creating" "$LOCAL_PATH/.maintenance"
lk_wp_maintenance_enable "$LOCAL_PATH"
if [[ $MAINTENANCE =~ ^(on|permanent)$ ]]; then
    lk_console_detail "[remote] Creating" "$SSH_HOST:$REMOTE_PATH/.maintenance"
    ssh "$SSH_HOST" '/bin/sh -c '\''cat >"$1/.maintenance"'\''' sh \
        "$REMOTE_PATH" < <(lk_wp_maintenance_get_php)
fi

! is_final || [ -n "$NO_WAIT" ] || {
    lk_console_message "Waiting 60 seconds for active requests to complete"
    sleep 60
}

# Migrate files
LK_NO_INPUT=1 \
    lk_wp_sync_files_from_remote "$SSH_HOST" "$REMOTE_PATH" "$LOCAL_PATH" \
    ${EXCLUDE[@]+"${EXCLUDE[@]/#/--exclude=}"} "$@"

# Migrate database
DB_FILE=~/.lk-platform/cache/db/$SSH_HOST-${REMOTE_PATH//\//_}-$(lk_date_ymdhms).sql.gz
install -d -m 00700 "${DB_FILE%/*}"
lk_wp_db_dump_remote "$SSH_HOST" "$REMOTE_PATH" >"$DB_FILE"
# TODO: put this in an exit trap
maybe_disable_remote_maintenance
cd "$LOCAL_PATH"
LK_NO_INPUT=1 \
    lk_wp_db_restore_local "$DB_FILE" "$DEFAULT_DB_NAME" "$DEFAULT_DB_USER"
if [ "$INNODB" -eq 1 ]; then
    SH=$(lk_wp_db_get_vars)
    eval "$SH"
    lk_wp_db_myisam_to_innodb -n
fi
if [ "$SHUFFLE_SALTS" -eq 1 ]; then
    lk_console_message "Refreshing salts defined in wp-config.php"
    lk_wp config shuffle-salts
fi
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
    LK_WP_REPLACE=1 LK_WP_APPLY=0 LK_WP_FLUSH=0 LK_WP_MIGRATE=0 \
        _LK_WP_QUIET=1 _LK_WP_REPLACE_COMMAND=wp \
        lk_wp_rename_site "$RENAME"
lk_wp_apply || STATUS=$?

if [ "$SSL" -eq 1 ]; then
    eval "$(lk_get_regex DOMAIN_NAME_REGEX)" &&
        SITE_ADDR=$(lk_wp_get_site_address) &&
        [[ $SITE_ADDR =~ ^https?://(www\.)?($DOMAIN_NAME_REGEX) ]] &&
        DOMAIN=${BASH_REMATCH[2]} &&
        lk_install -d -m 00750 ~/ssl &&
        lk_cpanel_server_set "$SSH_HOST" &&
        lk_cpanel_ssl_get_for_domain "$DOMAIN" ~/ssl
fi || true

if is_final; then
    lk_console_warning "Enabling WP-Cron"
    lk_wp_enable_system_cron
else
    lk_console_warning "Disabling WP-Cron (remote site still online)"
    lk_wp_disable_cron
fi

lk_console_message "[local] Restoring maintenance mode"
lk_wp_maintenance_maybe_disable ||
    lk_warn "Error restoring previous maintenance mode"

(exit "$STATUS") &&
    lk_console_success "Migration completed successfully" ||
    lk_console_error -r "Migration completed with errors" || lk_die ""

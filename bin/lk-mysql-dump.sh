#!/bin/bash
# shellcheck disable=

lk_bin_depth=1 include=mysql . lk-bash-load.sh || exit

DB_NAME=
DB_USER=
DB_PASSWORD=
DB_HOST=${LK_MYSQL_HOST:-localhost}

EXCLUDE_MODE=0
DEST=$PWD
TIMESTAMP=${LK_BACKUP_TIMESTAMP:-}
NO_TIMESTAMP=0
DB_INCLUDE=()
DB_EXCLUDE=()

LK_USAGE="\
Usage: ${0##*/} [OPTION...]
   or: ${0##*/} [OPTION...] DB_NAME...
   or: ${0##*/} [OPTION...] --exclude DB_NAME...

Use mysqldump to back up one or more MySQL/MariaDB databases. If no DB_NAME is
specified, include all databases. If --exclude is set, include all databases
except each DB_NAME.

Options:
  -x, --exclude             dump all databases except each DB_NAME
  -d, --dest=DIR            create each backup file in DIR
                            (default: current directory)
  -t, --timestamp=VALUE     use VALUE as backup file timestamp
                            (default: LK_BACKUP_TIMESTAMP from environment
                            or output of \`date +%Y-%m-%d-%H%M%S\`)
  -s, --no-timestamp        don't add backup file timestamp"

lk_getopt "xd:t:s" \
    "exclude,dest:,timestamp:,no-timestamp"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -x | --exclude)
        EXCLUDE_MODE=1
        ;;
    -d | --dest)
        [ -d "$1" ] || lk_warn "directory not found: $1" || lk_usage
        [ -w "$1" ] || lk_warn "directory not writable: $1" || lk_usage
        DEST=$(realpath "$1")
        shift
        ;;
    -t | --timestamp)
        [[ $1 =~ ^[0-9]{4}(-[0-9]{2}){2}-[0-9]{6}$ ]] ||
            lk_warn "invalid timestamp: $1" || lk_usage
        TIMESTAMP=$1
        NO_TIMESTAMP=0
        shift
        ;;
    -s | --no-timestamp)
        NO_TIMESTAMP=1
        ;;
    --)
        break
        ;;
    esac
done

! INVALID_DB_NAME=$(grep -E '[[:blank:]]$' <(printf '%s\n' "$@")) ||
    lk_warn "invalid DB_NAME $(
        lk_maybe_plural \
            "$(wc -l <<<"$INVALID_DB_NAME")" \
            argument arguments
        false
    ): \"${INVALID_DB_NAME//$'\n'/$'", "'}\"" ||
    lk_usage

lk_is_true "$EXCLUDE_MODE" &&
    DB_EXCLUDE+=("$@") ||
    DB_INCLUDE+=("$@")

EXIT_STATUS=0

LK_MYSQL_QUIET=1
LK_CONSOLE_NO_FOLD=1

lk_log_output

lk_console_message "Preparing database backup"
lk_console_detail "Retrieving list of databases on" "$DB_HOST"
lk_mysql_mapfile DB_ALL ${DB_HOST:+-h"$DB_HOST"} <<<"SHOW DATABASES"
lk_console_detail "${#DB_ALL[@]} $(lk_maybe_plural \
    ${#DB_ALL[@]} database databases) found"

if [ ${#DB_INCLUDE[@]} -gt 0 ]; then
    DB_MISSING=()
    for i in "${!DB_INCLUDE[@]}"; do
        lk_in_array "${DB_INCLUDE[$i]}" DB_ALL || {
            DB_MISSING+=("${DB_INCLUDE[$i]}")
            unset "DB_INCLUDE[$i]"
        }
    done
    [ ${#DB_MISSING[@]} -eq 0 ] || {
        EXIT_STATUS=1
        lk_console_warning "${#DB_MISSING[@]} requested $(
            lk_maybe_plural ${#DB_MISSING[@]} database databases
        ) not available on this host:" "$(lk_echo_array DB_MISSING)"
    }
else
    DB_INCLUDE=("${DB_ALL[@]}")
    DB_EXCLUDE+=(
        information_schema
        performance_schema
        sys
    )
fi

if [ ${#DB_EXCLUDE[@]} -gt 0 ]; then
    DB_EXCLUDED=()
    for i in "${!DB_INCLUDE[@]}"; do
        ! lk_in_array "${DB_INCLUDE[$i]}" DB_EXCLUDE || {
            DB_EXCLUDED+=("${DB_INCLUDE[$i]}")
            unset "DB_INCLUDE[$i]"
        }
    done
    [ ${#DB_EXCLUDED[@]} -eq 0 ] || {
        lk_echo_array DB_EXCLUDED |
            lk_console_detail_list "Excluded:"
    }
fi

[ ${#DB_INCLUDE[@]} -gt 0 ] || lk_die "nothing to dump"

lk_echo_array DB_INCLUDE |
    lk_console_detail_list "Ready to dump:" database databases

lk_confirm "Proceed?" Y || lk_die

LOCK_FILE=/tmp/${0##*/}-${DEST//\//_}.lock
exec 8>"$LOCK_FILE"
flock -n 8 || lk_die "unable to acquire a lock on $LOCK_FILE"

for DB_NAME in "${DB_INCLUDE[@]}"; do
    lk_console_item "Dumping database:" "$DB_NAME"
    FILE=$DEST/$DB_NAME
    lk_is_true "$NO_TIMESTAMP" ||
        FILE=$FILE-${TIMESTAMP:-$(lk_date "%Y-%m-%d-%H%M%S")}
    FILE=$FILE.sql.gz
    lk_console_detail "Backup file:" "$FILE"
    [ ! -e "$FILE" ] || {
        EXIT_STATUS=1
        lk_console_error "Skipping (backup already exists)"
        continue
    }
    install -m 00600 /dev/null "$FILE.pending"
    if lk_mysql_dump \
        "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_HOST" >"$FILE.pending" &&
        mv -f "$FILE.pending" "$FILE"; then
        lk_console_success "Database dump completed successfully"
    else
        EXIT_STATUS=$?
        lk_console_error "Database dump failed (exit status $EXIT_STATUS)"
    fi
done

exec 8>&-
rm -f "$LOCK_FILE"

(exit "$EXIT_STATUS") || lk_die

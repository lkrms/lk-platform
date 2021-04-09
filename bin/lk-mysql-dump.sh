#!/bin/bash

lk_bin_depth=1 include=mysql . lk-bash-load.sh || exit

DB_NAME=
DB_USER=
DB_PASSWORD=
DB_HOST=${LK_MYSQL_HOST:-localhost}

ALL=0
EXCLUDE=0
DEST=$PWD
DEST_GROUP=
TIMESTAMP=${LK_BACKUP_TIMESTAMP:-}
NO_TIMESTAMP=0
DB_INCLUDE=()
DB_EXCLUDE=(information_schema performance_schema sys)

LK_USAGE="\
Usage: ${0##*/} [OPTION...] DB_NAME...
   or: ${0##*/} [OPTION...] --exclude DB_NAME...
   or: ${0##*/} [OPTION...] --all

Use mysqldump to back up one or more MySQL databases.

Options:
  -a, --all                 dump all databases
  -x, --exclude             dump all databases except DB_NAME...
  -d, --dest=DIR            create each backup file in DIR
                            (default: current directory)
  -t, --timestamp=VALUE     use VALUE as backup file timestamp
                            (default: LK_BACKUP_TIMESTAMP from environment
                            or output of \`date +%Y-%m-%d-%H%M%S\`)
  -s, --no-timestamp        don't add backup file timestamp
  -g, --group GROUP         create backup files with group GROUP"

lk_getopt "axd:t:sg:" \
    "all,exclude,dest:,timestamp:,no-timestamp,group:"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -a | --all)
        ALL=1
        EXCLUDE=0
        ;;
    -x | --exclude)
        EXCLUDE=1
        ALL=0
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
    -g | --group)
        # TODO: add macOS-friendly test
        getent group "$1" &>/dev/null ||
            lk_die "group not found: $1"
        DEST_GROUP=$1
        shift
        ;;
    --)
        break
        ;;
    esac
done

! lk_is_true ALL || [ $# -eq 0 ] || lk_usage
lk_is_true ALL || {
    [ $# -gt 0 ] || lk_usage
    ! grep -E '[[:blank:]]$' <(printf '%s\n' "$@") >/dev/null ||
        lk_warn "invalid arguments" || lk_usage
}

EXIT_STATUS=0

LK_MYSQL_QUIET=1
LK_TTY_NO_FOLD=1

lk_log_start
lk_start_trace

lk_console_message "Preparing database backup"
lk_console_detail "Retrieving list of databases on" "$DB_HOST"
lk_mysql_mapfile DB_ALL -h"$DB_HOST" <<<"SHOW DATABASES" || lk_die ""
lk_console_detail "${#DB_ALL[@]} $(lk_maybe_plural \
    ${#DB_ALL[@]} database databases) found"

if lk_is_true ALL; then
    DB_INCLUDE=(${DB_ALL[@]+"${DB_ALL[@]}"})
elif lk_is_true EXCLUDE; then
    DB_INCLUDE=(${DB_ALL[@]+"${DB_ALL[@]}"})
    DB_EXCLUDE+=("$@")
else
    DB_INCLUDE=("$@")
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
    fi
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

lk_confirm "Proceed?" Y || lk_die ""

LOCK_NAME=${0##*/}-${DEST//\//_}
lk_lock LOCK_FILE LOCK_FD "$LOCK_NAME"

DEST_MODE=00600
[ -z "$DEST_GROUP" ] ||
    DEST_MODE=00640
for DB_NAME in "${DB_INCLUDE[@]}"; do
    lk_console_item "Dumping database:" "$DB_NAME"
    FILE=$DEST/$DB_NAME
    lk_is_true NO_TIMESTAMP ||
        FILE=$FILE-${TIMESTAMP:-$(lk_date "%Y-%m-%d-%H%M%S")}
    FILE=$FILE.sql.gz
    lk_console_detail "Backup file:" "$FILE"
    [ ! -e "$FILE" ] || {
        EXIT_STATUS=1
        lk_console_error "Skipping (backup already exists)"
        continue
    }
    install -m "$DEST_MODE" ${DEST_GROUP:+-g "$DEST_GROUP"} \
        /dev/null "$FILE.pending"
    if lk_mysql_dump \
        "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_HOST" >"$FILE.pending" &&
        mv -f "$FILE.pending" "$FILE"; then
        lk_console_success "Database dump completed successfully"
    else
        EXIT_STATUS=$?
        lk_console_error "Database dump failed (exit status $EXIT_STATUS)"
    fi
done

(exit "$EXIT_STATUS") || lk_die ""

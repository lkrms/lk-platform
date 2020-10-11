#!/bin/bash
# shellcheck disable=

lk_bin_depth=1 include=mysql . lk-bash-load.sh || exit

EXCLUDE_MODE=0
DEST=$PWD
TIMESTAMP=${LK_BACKUP_TIMESTAMP:-}
NO_TIMESTAMP=0
DB_INCLUDE=()
DB_EXCLUDE=(
    information_schema
    performance_schema
    sys
)

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

lk_check_args
OPTS=$(
    gnu_getopt --options "xd:t:s" \
        --longoptions "yes,exclude,dest:,timestamp:,no-timestamp" \
        --name "${0##*/}" \
        -- "$@"
) || lk_usage
eval "set -- $OPTS"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -x | --exclude)
        EXCLUDE_MODE=1
        ;;
    -d | --dest=DIR)
        [ -d "$1" ] || lk_warn "directory not found: $1" || lk_usage
        [ -w "$1" ] || lk_warn "directory not writable: $1" || lk_usage
        DEST=$1
        shift
        ;;
    -t | --timestamp=VALUE)
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

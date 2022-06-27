#!/bin/bash

function lk_mysql_is_quiet() {
    [ -n "${_LK_MYSQL_QUIET-}" ]
}

function lk_mysql_escape() {
    if [ $# -gt 0 ]; then
        lk_echo_args "$@" | lk_mysql_escape
    else
        sed -E 's/['\''\]/\\&/g'
    fi
}

function lk_mysql_escape_like() {
    if [ $# -gt 0 ]; then
        lk_echo_args "$@" | lk_mysql_escape_like
    else
        sed -E 's/[%'\''\_]/\\&/g'
    fi
}

function lk_mysql_escape_cnf() {
    if [ $# -gt 0 ]; then
        lk_echo_args "$@" | lk_mysql_escape_cnf
    else
        sed -E 's/["\]/\\&/g'
    fi
}

function lk_mysql_quote_identifier() {
    local IDENTIFIER=${1//'`'/\`\`}
    echo "\`$IDENTIFIER\`"
}

function lk_mysql_batch_unescape() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        sed -Ee 's/(^|[^\])\\n/\1\n/g' \
            -e 's/(^|[^\])\\t/\1\t/g' \
            -e 's/\\\\/\\/g'
}

# lk_mysql_bytes SIZE
#
# Convert SIZE to its equivalent in bytes, where SIZE is an integer optionally
# followed by K, M, G, T, P or E (not case-sensitive).
function lk_mysql_bytes() {
    local POWER=0
    [[ ${1-} =~ ^0*([0-9]+)([kKmMgGtTpPeE]?)$ ]] ||
        lk_warn "invalid size: ${1-}" || return
    case "${BASH_REMATCH[2]}" in
    k | K)
        POWER=1
        ;;
    m | M)
        POWER=2
        ;;
    g | G)
        POWER=3
        ;;
    t | T)
        POWER=4
        ;;
    p | P)
        POWER=5
        ;;
    e | E)
        POWER=6
        ;;
    esac
    echo $((BASH_REMATCH[1] * 1024 ** POWER))
}

# lk_mysql_get_cnf [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_get_cnf() {
    cat <<EOF
# Generated by $(lk_script_name)
[client]
user="$(lk_mysql_escape_cnf "${1-$DB_USER}")"
password="$(lk_mysql_escape_cnf "${2-$DB_PASSWORD}")"
host="$(lk_mysql_escape_cnf \
        "${3-${DB_HOST-${LK_MYSQL_HOST:-localhost}}}")"${LK_MY_CNF_OPTIONS:+
$LK_MY_CNF_OPTIONS}
EOF
}

function lk_mysql_write_cnf() {
    LK_MY_CNF=${LK_MY_CNF:-~/.lk_mysql.cnf}
    lk_mysql_get_cnf "$@" >"$LK_MY_CNF"
    ! type -p lk_delete_on_exit >/dev/null ||
        lk_delete_on_exit "$LK_MY_CNF"
}

function lk_mysql() {
    if [ -n "${LK_MY_CNF-}" ]; then
        [ -f "$LK_MY_CNF" ] || lk_warn "file not found: $LK_MY_CNF" || return
        "${_LK_MYSQL_COMMAND:-mysql}" --defaults-file="$LK_MY_CNF" "$@"
    elif lk_root || lk_is_true LK_MYSQL_ELEVATE; then
        lk_elevate "${_LK_MYSQL_COMMAND:-mysql}" \
            --no-defaults \
            --user="${LK_MYSQL_ELEVATE_USER:-root}" \
            "$@"
    elif [ -f ~/.my.cnf ]; then
        "${_LK_MYSQL_COMMAND:-mysql}" "$@"
    else
        lk_warn "LK_MY_CNF not set"
    fi
}

function lk_mysql_connects() {
    lk_mysql --execute="\\q" ${1+"$1"}
}

function lk_mysql_list() {
    lk_mysql --batch --skip-column-names "$@"
}

function lk_mysql_mapfile() {
    local _LK_OUT _lk_i=0 _LK_LINE
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    _LK_OUT=$(lk_mktemp_file) &&
        lk_delete_on_exit "$_LK_OUT" &&
        lk_mysql_list "${@:2}" | lk_mysql_batch_unescape >"$_LK_OUT" || return
    eval "$1=()"
    while IFS= read -r _LK_LINE; do
        eval "$1[$((_lk_i++))]=\$_LK_LINE"
    done <"$_LK_OUT"
    rm -f -- "$_LK_OUT"
}

function _lk_mysqldump() {
    _LK_MYSQL_COMMAND=mysqldump \
        lk_mysql "$@"
}

function lk_mysql_innodb_only() {
    local NOT_INNODB
    NOT_INNODB=$(lk_mysql_list <<<"SELECT COUNT(*)
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
    AND ENGINE <> 'InnoDB'
    AND TABLE_SCHEMA = '$(lk_mysql_escape "$1")'") || return 2
    [ "$NOT_INNODB" -eq 0 ]
}

# lk_mysql_myisam_to_innodb DB_NAME
function lk_mysql_myisam_to_innodb() { (
    [ $# -eq 1 ] || lk_usage "Usage: $FUNCNAME DB_NAME" || return
    lk_mktemp_with TABLES lk_mysql_list <<<"SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
    AND ENGINE = 'MyISAM'
    AND TABLE_SCHEMA = '$(lk_mysql_escape "$1")'" || return
    if [ -s "$TABLES" ]; then
        lk_tty_list - "Converting to InnoDB from MyISAM in database '$1':" \
            table tables <"$TABLES"
        sed -E 's/.*/ALTER TABLE & ENGINE=InnoDB;/' "$TABLES" |
            lk_mysql "$1" &&
            lk_tty_success "Tables converted successfully" ||
            lk_tty_error -r "Table conversion failed"
    else
        lk_tty_success "No MyISAM tables in database:" "$1"
    fi
); }

# lk_mysql_dump DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_dump() {
    local DB_NAME=$1 DB_USER=${2-${DB_USER-}} DB_PASSWORD=${3-${DB_PASSWORD-}} \
        DB_HOST=${4-${DB_HOST-${LK_MYSQL_HOST:-localhost}}} \
        LK_MYSQL_ELEVATE LK_MY_CNF OUTPUT_FILE OUTPUT_FD \
        INNODB_ONLY=1 DUMP_ARGS ARG_COLOUR EXIT_STATUS=0
    unset ARG_COLOUR
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]" ||
        return
    [ -n "$DB_NAME" ] || lk_warn "no database name" || return
    if [ "${DB_USER:+1}${DB_PASSWORD:+1}$DB_HOST" = localhost ] &&
        lk_can_sudo mysqldump; then
        LK_MYSQL_ELEVATE=1
    else
        LK_MY_CNF=~/.lk_mysqldump.cnf
        lk_tty_print "Creating temporary mysqldump configuration file"
        lk_tty_detail "Adding credentials for user" "$DB_USER"
        lk_tty_detail "Writing" "$LK_MY_CNF"
        lk_mysql_write_cnf
    fi
    lk_mysql_connects "$DB_NAME" 2>/dev/null ||
        lk_warn "database connection failed" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=~/.lk-platform/cache/db/$DB_HOST-$DB_NAME-$(lk_date_ymdhms).sql.gz
        install -d -m 00700 "${OUTPUT_FILE%/*}" &&
            OUTPUT_FD=$(lk_fd_next) &&
            eval "exec $OUTPUT_FD>&1 >\"\$OUTPUT_FILE\"" || return
    }
    lk_mysql_innodb_only "$DB_NAME" || {
        [ $? -eq 1 ] || return
        INNODB_ONLY=0
    }
    if ((INNODB_ONLY)); then
        DUMP_ARGS=(
            --single-transaction
            --skip-lock-tables
        )
    else
        DUMP_ARGS=(
            --lock-tables
        )
        ARG_COLOUR=$LK_BOLD$LK_RED
    fi
    DUMP_ARGS+=(--no-tablespaces)
    lk_mysql_is_quiet || {
        lk_tty_print "Dumping database:" "$DB_NAME"
        lk_tty_detail "Host:" "$DB_HOST"
    }
    { lk_mysql_is_quiet && ((INNODB_ONLY)); } || {
        lk_tty_detail "InnoDB only?" "${ARG_COLOUR+$ARG_COLOUR}$(
            ((INNODB_ONLY)) && echo yes || echo no
        )${ARG_COLOUR+$LK_RESET}"
        lk_tty_detail "mysqldump arguments:" \
            "${ARG_COLOUR+$ARG_COLOUR}${DUMP_ARGS[*]}${ARG_COLOUR+$LK_RESET}"
    }
    [ -z "${OUTPUT_FILE-}" ] ||
        lk_tty_detail "Writing compressed SQL to" "$OUTPUT_FILE"
    _lk_mysqldump \
        "${DUMP_ARGS[@]}" \
        "$DB_NAME" |
        gzip |
        lk_pv ||
        EXIT_STATUS=$?
    [ -z "${OUTPUT_FILE-}" ] || eval "exec >&$OUTPUT_FD $OUTPUT_FD>&-"
    [ -z "${LK_MY_CNF-}" ] || {
        lk_tty_print "Deleting mysqldump configuration file"
        rm -f "$LK_MY_CNF" &&
            lk_tty_detail "Deleted" "$LK_MY_CNF" ||
            lk_tty_warning "Error deleting" "$LK_MY_CNF"
    }
    lk_mysql_is_quiet || {
        [ "$EXIT_STATUS" -eq 0 ] &&
            lk_tty_success "Database dump completed successfully" ||
            lk_tty_error "Database dump failed"
    }
    return "$EXIT_STATUS"
}

# lk_mysql_dump_remote SSH_HOST DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_dump_remote() {
    local SSH_HOST=$1 DB_NAME=$2 \
        DB_USER=${3-${DB_USER-}} DB_PASSWORD=${4-${DB_PASSWORD-}} \
        DB_HOST=${5-${DB_HOST-${LK_MYSQL_HOST:-localhost}}} \
        OUTPUT_FILE OUTPUT_FD SH EXIT_STATUS=0
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME SSH_HOST DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]" ||
        return
    [ -n "$SSH_HOST" ] || lk_warn "no ssh host" || return
    [ -n "$DB_NAME" ] || lk_warn "no database name" || return
    lk_tty_print "Creating temporary mysqldump configuration file"
    lk_tty_detail "Adding credentials for user" "$DB_USER"
    lk_tty_detail "Writing" "$SSH_HOST:.lk_mysqldump.cnf"
    lk_mysql_get_cnf |
        ssh "$SSH_HOST" "bash -c 'cat >.lk_mysqldump.cnf'" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=~/.lk-platform/cache/db/$SSH_HOST-$DB_NAME-$(lk_date_ymdhms).sql.gz
        install -d -m 00700 "${OUTPUT_FILE%/*}" &&
            OUTPUT_FD=$(lk_fd_next) &&
            eval "exec $OUTPUT_FD>&1 >\"\$OUTPUT_FILE\"" || return
    }
    lk_tty_print "Dumping remote database"
    lk_tty_detail "Database:" "$DB_NAME"
    lk_tty_detail "Host:" "$DB_HOST"
    [ -z "${OUTPUT_FILE-}" ] ||
        lk_tty_detail "Writing compressed SQL to" "$OUTPUT_FILE"
    # TODO: implement lk_mysql_innodb_only
    SH=$(
        function do-mysqldump() {
            local IFS=
            # Use `sed` to remove the database name when it appears as a
            # qualifier, working around this MariaDB bug:
            # https://jira.mariadb.org/browse/MDEV-22282
            mysqldump \
                --defaults-file=.lk_mysqldump.cnf \
                --single-transaction \
                --skip-lock-tables \
                --no-tablespaces \
                "$1" | sed -E ':repeat
s/^(\/\*![0-9]+[[:blank:]]+.*)'"$2"'\.(`([^`]+|``)*`)/\1\2/
t repeat' | gzip && [[ ${PIPESTATUS[*]} == 000 ]]
        }
        declare -f do-mysqldump
        lk_quote_args do-mysqldump \
            "$DB_NAME" \
            "$(lk_sed_escape "$(lk_mysql_quote_identifier "$DB_NAME")")"
    )
    ssh "$SSH_HOST" "bash -c $(lk_quote_args "$SH")" |
        lk_pv ||
        EXIT_STATUS=$?
    [ -z "${OUTPUT_FILE-}" ] || eval "exec >&$OUTPUT_FD $OUTPUT_FD>&-"
    lk_tty_print "Deleting mysqldump configuration file"
    ssh "$SSH_HOST" "bash -c 'rm -f .lk_mysqldump.cnf'" &&
        lk_tty_detail "Deleted" "$SSH_HOST:.lk_mysqldump.cnf" ||
        lk_tty_warning "Error deleting" "$SSH_HOST:.lk_mysqldump.cnf"
    [ "$EXIT_STATUS" -eq 0 ] &&
        lk_tty_success "Database dump completed successfully" ||
        lk_tty_error "Database dump failed"
    return "$EXIT_STATUS"
}

# lk_mysql_restore_filter [SED_ARG...]
#
# Fix known issues in mysqldump-generated SQL.
#
# To print changed lines only, call:
#
#     lk_mysql_restore_filter -n -e "T; p"
function lk_mysql_restore_filter() {
    sed -E -e 's/^(\/\*![0-9]+[[:blank:]]+DEFINER=)`([^`]+|``)*`@`([^`]+|``)*`/\1CURRENT_USER/' "$@"
}

# lk_mysql_restore_local FILE DB_NAME
function lk_mysql_restore_local() {
    local FILE=$1 DB_NAME=$2 SQL _SQL LK_MYSQL_ELEVATE
    [ -f "$FILE" ] || lk_warn "file not found: $FILE" || return
    [ -n "$DB_NAME" ] || lk_warn "no database name" || return
    ! lk_can_sudo mysql ||
        LK_MYSQL_ELEVATE=1
    lk_tty_print "Preparing to restore database"
    lk_tty_detail "Backup file:" "$FILE"
    lk_tty_detail "Database:" "$DB_NAME"
    SQL=(
        "DROP DATABASE IF EXISTS $(lk_mysql_quote_identifier "$DB_NAME")"
        "CREATE DATABASE $(lk_mysql_quote_identifier "$DB_NAME")"
    )
    _SQL=$(printf '%s;\n' "${SQL[@]}")
    lk_tty_detail "Local database will be reset with:" "$_SQL"
    lk_tty_warning \
        "All data in local database '$DB_NAME' will be permanently destroyed"
    lk_confirm "Proceed?" Y || return
    lk_tty_print "Restoring database to local system"
    lk_tty_detail "Resetting database" "$DB_NAME"
    echo "$_SQL" | lk_mysql || return
    lk_tty_detail "Restoring" "$FILE"
    if [[ $FILE =~ \.gz(ip)?$ ]]; then
        lk_pv "$FILE" | gunzip
    else
        lk_pv "$FILE"
    fi | lk_mysql_restore_filter | lk_mysql "$DB_NAME" ||
        lk_tty_error -r "Restore operation failed" || return
    lk_tty_success "Database restored successfully"
}

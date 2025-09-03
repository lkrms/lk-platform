#!/usr/bin/env bash

#### INCLUDE mysql.sh.d

function lk_mysql_innodb_only() {
    local NOT_INNODB
    NOT_INNODB=$(lk_mysql_list <<<"SELECT COUNT(*)
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
    AND ENGINE <> 'InnoDB'
    AND TABLE_SCHEMA = $(lk_mysql_escape "$1")") || return 2
    [ "$NOT_INNODB" -eq 0 ]
}

# lk_mysql_myisam_to_innodb DB_NAME
function lk_mysql_myisam_to_innodb() { (
    [ $# -eq 1 ] || lk_usage "Usage: $FUNCNAME DB_NAME" || return
    lk_mktemp_with TABLES lk_mysql_list <<<"SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
    AND ENGINE = 'MyISAM'
    AND TABLE_SCHEMA = $(lk_mysql_escape "$1")" || return
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
        LK_MY_CNF=~/.mysqldump.lk.my.cnf
        lk_tty_print "Creating temporary mysqldump configuration file"
        lk_tty_detail "Adding credentials for user" "$DB_USER"
        lk_tty_detail "Writing" "$LK_MY_CNF"
        lk_mysql_options_client_write
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
    lk_mysqldump \
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
    lk_tty_detail "Writing" "$SSH_HOST:.mysqldump.lk.my.cnf"
    lk_mysql_options_client_print |
        ssh "$SSH_HOST" "bash -c 'cat >.mysqldump.lk.my.cnf'" || return
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
        # shellcheck disable=SC2329
        function do-mysqldump() {
            local IFS=
            # Use `sed` to remove the database name when it appears as a
            # qualifier, working around this MariaDB bug:
            # https://jira.mariadb.org/browse/MDEV-22282
            mysqldump \
                --defaults-file=.mysqldump.lk.my.cnf \
                --single-transaction \
                --skip-lock-tables \
                --no-tablespaces \
                "$1" | sed -E ':repeat
s/^(\/\*![0-9]+[[:blank:]]+.*)'"$2"'\.(`([^`]+|``)*`)/\1\2/
t repeat' | gzip && test "${PIPESTATUS[*]}" = 000
        }
        declare -f do-mysqldump
        lk_quote_args do-mysqldump \
            "$DB_NAME" \
            "$(lk_sed_escape "$(lk_mysql_escape_identifier "$DB_NAME")")"
    )
    ssh "$SSH_HOST" "bash -c $(lk_quote_args "$SH")" |
        lk_pv ||
        EXIT_STATUS=$?
    [ -z "${OUTPUT_FILE-}" ] || eval "exec >&$OUTPUT_FD $OUTPUT_FD>&-"
    lk_tty_print "Deleting mysqldump configuration file"
    ssh "$SSH_HOST" "bash -c 'rm -f .mysqldump.lk.my.cnf'" &&
        lk_tty_detail "Deleted" "$SSH_HOST:.mysqldump.lk.my.cnf" ||
        lk_tty_warning "Error deleting" "$SSH_HOST:.mysqldump.lk.my.cnf"
    [ "$EXIT_STATUS" -eq 0 ] &&
        lk_tty_success "Database dump completed successfully" ||
        lk_tty_error "Database dump failed"
    return "$EXIT_STATUS"
}

# lk_mysql_restore_filter
#
# Fix known issues in mysqldump-generated SQL.
function lk_mysql_restore_filter() {
    local version sandbox_version expr=(
        # Replace definer with CURRENT_USER
        's/^(\/\*![0-9]+[[:blank:]]*DEFINER=)`([^`]+|``)*`@`([^`]+|``)*`/\1CURRENT_USER/'
    )
    # See https://mariadb.org/mariadb-dump-file-compatibility-change/
    version=$(lk_mysql_version) || return
    case "$version" in
    10.5.*) sandbox_version=10.5.25 ;;
    10.6.*) sandbox_version=10.6.18 ;;
    10.11.*) sandbox_version=10.11.8 ;;
    11.0.*) sandbox_version=11.0.6 ;;
    11.1.*) sandbox_version=11.1.5 ;;
    11.2.*) sandbox_version=11.2.4 ;;
    11.4.*) sandbox_version=11.4.2 ;;
    *) sandbox_version=12.0 ;;
    esac
    lk_version_at_least "$version" "$sandbox_version" ||
        expr+=('1 { /^\/\*![0-9]+[[:blank:]]*\\-.*\*\/[[:blank:]]*$/ d }')
    sed -E "${expr[@]/#/-e}"
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
        "DROP DATABASE IF EXISTS $(lk_mysql_escape_identifier "$DB_NAME")"
        "CREATE DATABASE $(lk_mysql_escape_identifier "$DB_NAME")"
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

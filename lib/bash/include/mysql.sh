#!/bin/bash

# shellcheck disable=SC2015,SC2029,SC2120

function lk_mysql_quiet() {
    [ "${LK_MYSQL_QUIET:-0}" -ne 0 ]
}

function lk_mysql_escape() {
    lk_escape "$1" "\\" "'"
}

function lk_mysql_escape_cnf() {
    lk_escape "$1" "\\" '"'
}

function lk_mysql_batch_unescape() {
    sed -Ee 's/(^|[^\])\\n/\1\n/g' \
        -e 's/(^|[^\])\\t/\1\t/g' \
        -e 's/\\\\/\\/g' <<<"$1"
}

# lk_mysql_get_cnf [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_get_cnf() {
    cat <<EOF
# Generated by $(lk_myself)
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
}

function lk_mysql() {
    if [ -n "${LK_MY_CNF:-}" ]; then
        [ -f "$LK_MY_CNF" ] || lk_warn "file not found: $LK_MY_CNF" || return
        "${LK_MYSQL_COMMAND:-mysql}" --defaults-file="$LK_MY_CNF" "$@"
    elif lk_is_root || lk_is_true "${LK_MYSQL_ELEVATE:-}"; then
        lk_elevate "${LK_MYSQL_COMMAND:-mysql}" \
            --no-defaults \
            --user="${LK_MYSQL_ELEVATE_USER:-root}" \
            "$@"
    elif [ -f ~/.my.cnf ]; then
        "${LK_MYSQL_COMMAND:-mysql}" "$@"
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
    local _LK_LINE
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    eval "$1=()"
    while IFS= read -r _LK_LINE; do
        _LK_LINE=$(lk_mysql_batch_unescape "$_LK_LINE")
        eval "$1+=(\"\$_LK_LINE\")"
    done < <(lk_mysql_list "${@:2}")
}

function _lk_mysqldump() {
    LK_MYSQL_COMMAND=mysqldump \
        lk_mysql "$@"
}

function lk_mysql_innodb_only() {
    local NOT_INNODB
    NOT_INNODB=$(lk_mysql_list <<<"SELECT COUNT(*)
FROM information_schema.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
    AND ENGINE <> 'InnoDB'
    AND TABLE_SCHEMA = '$(lk_mysql_escape "$1")'") || return
    [ "$NOT_INNODB" -eq 0 ] &&
        echo yes ||
        echo no
}

# lk_mysql_dump DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_dump() {
    local DB_NAME=$1 DB_USER=${2-${DB_USER-}} DB_PASSWORD=${3-${DB_PASSWORD-}} \
        DB_HOST=${4-${DB_HOST-${LK_MYSQL_HOST:-localhost}}} \
        LK_MYSQL_ELEVATE LK_MY_CNF OUTPUT_FILE \
        INNODB_ONLY DUMP_ARGS ARG_COLOUR EXIT_STATUS=0
    [ $# -ge 1 ] || lk_usage "\
Usage: $(lk_myself -f) DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]" ||
        return
    [ -n "$DB_NAME" ] || lk_warn "no database name" || return
    if [ "${DB_USER:+1}${DB_PASSWORD:+1}$DB_HOST" = localhost ] &&
        lk_can_sudo mysqldump; then
        LK_MYSQL_ELEVATE=1
    else
        LK_MY_CNF=~/.lk_mysqldump.cnf
        lk_console_message "Creating temporary mysqldump configuration file"
        lk_console_detail "Adding credentials for user" "$DB_USER"
        lk_console_detail "Writing" "$LK_MY_CNF"
        lk_mysql_write_cnf
    fi
    lk_mysql_connects "$DB_NAME" 2>/dev/null ||
        lk_warn "database connection failed" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=~/$DB_HOST-$DB_NAME-$(lk_date_ymdhms).sql.gz
        exec 6>&1 >"$OUTPUT_FILE"
    }
    INNODB_ONLY=$(lk_mysql_innodb_only "$DB_NAME") || return
    if lk_is_true "$INNODB_ONLY"; then
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
    lk_mysql_quiet || {
        lk_console_item "Dumping database:" "$DB_NAME"
        lk_console_detail "Host:" "$DB_HOST"
    }
    { lk_mysql_quiet && lk_is_true "$INNODB_ONLY"; } || {
        lk_console_detail "InnoDB only?" \
            "${ARG_COLOUR+$ARG_COLOUR}$INNODB_ONLY${ARG_COLOUR+$LK_RESET}"
        lk_console_detail "mysqldump arguments:" \
            "${ARG_COLOUR+$ARG_COLOUR}${DUMP_ARGS[*]}${ARG_COLOUR+$LK_RESET}"
    }
    [ -z "${OUTPUT_FILE:-}" ] ||
        lk_console_detail "Writing compressed SQL to" "$OUTPUT_FILE"
    _lk_mysqldump \
        "${DUMP_ARGS[@]}" \
        "$DB_NAME" |
        gzip |
        pv --force ||
        EXIT_STATUS=$?
    [ -z "${OUTPUT_FILE:-}" ] || exec 1>&6 6>&-
    [ -z "${LK_MY_CNF:-}" ] || {
        lk_console_message "Deleting mysqldump configuration file"
        rm -f "$LK_MY_CNF" &&
            lk_console_detail "Deleted" "$LK_MY_CNF" ||
            lk_console_warning0 "Error deleting" "$LK_MY_CNF"
    }
    lk_mysql_quiet || {
        [ "$EXIT_STATUS" -eq 0 ] &&
            lk_console_success "Database dump completed successfully" ||
            lk_console_error0 "Database dump failed"
    }
    return "$EXIT_STATUS"
}

# lk_mysql_dump_remote SSH_HOST DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]
function lk_mysql_dump_remote() {
    local SSH_HOST=$1 DB_NAME=$2 \
        DB_USER=${3-${DB_USER-}} DB_PASSWORD=${4-${DB_PASSWORD-}} \
        DB_HOST=${5-${DB_HOST-${LK_MYSQL_HOST:-localhost}}} \
        OUTPUT_FILE EXIT_STATUS=0
    [ $# -ge 2 ] || lk_usage "\
Usage: $(lk_myself -f) SSH_HOST DB_NAME [DB_USER [DB_PASSWORD [DB_HOST]]]" ||
        return
    [ -n "$SSH_HOST" ] || lk_warn "no ssh host" || return
    [ -n "$DB_NAME" ] || lk_warn "no database name" || return
    lk_console_message "Creating temporary mysqldump configuration file"
    lk_console_detail "Adding credentials for user" "$DB_USER"
    lk_console_detail "Writing" "$SSH_HOST:.lk_mysqldump.cnf"
    lk_mysql_get_cnf |
        ssh "$SSH_HOST" "bash -c 'cat >.lk_mysqldump.cnf'" || return
    [ ! -t 1 ] || {
        OUTPUT_FILE=~/$SSH_HOST-$DB_NAME-$(lk_date_ymdhms).sql.gz
        exec 6>&1 >"$OUTPUT_FILE"
    }
    lk_console_message "Dumping remote database"
    lk_console_detail "Database:" "$DB_NAME"
    lk_console_detail "Host:" "$DB_HOST"
    [ -z "${OUTPUT_FILE:-}" ] ||
        lk_console_detail "Writing compressed SQL to" "$OUTPUT_FILE"
    ssh "$SSH_HOST" "bash -c 'mysqldump \\
    --defaults-file=.lk_mysqldump.cnf \\
    --single-transaction \\
    --skip-lock-tables \\
    \"\$1\" | gzip
exit \${PIPESTATUS[0]}' bash $(printf '%q' "$DB_NAME")" | pv --force ||
        EXIT_STATUS=$?
    [ -z "${OUTPUT_FILE:-}" ] || exec 1>&6 6>&-
    lk_console_message "Deleting mysqldump configuration file"
    ssh "$SSH_HOST" "bash -c 'rm -f .lk_mysqldump.cnf'" &&
        lk_console_detail "Deleted" "$SSH_HOST:.lk_mysqldump.cnf" ||
        lk_console_warning0 "Error deleting" "$SSH_HOST:.lk_mysqldump.cnf"
    [ "$EXIT_STATUS" -eq 0 ] &&
        lk_console_success "Database dump completed successfully" ||
        lk_console_error0 "Database dump failed"
    return "$EXIT_STATUS"
}
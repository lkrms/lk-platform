#!/bin/bash

# lk_wp_get_db_config [wp_config_path]
#   Output DB_NAME, DB_USER, DB_PASSWORD and DB_HOST values configured in
#   wp-config.php as KEY="VALUE" pairs without calling `wp config`.
#   If not specified, WP_CONFIG_PATH is assumed to be "./wp-config.php".
function lk_wp_get_db_config() {
    local WP_CONFIG="${1:-wp-config.php}" PHP
    [ -e "$WP_CONFIG" ] || lk_warn "file not found: $WP_CONFIG" || return
    # 1. remove comments and whitespace from wp-config.php (php --strip)
    # 2. extract the relevant "define(...);" calls, one per line (grep -Po)
    # 3. add any missing semicolons (sed -E)
    # 4. add code to output each value as a shell expression (cat)
    # 5. run the code (php <<<"$PHP")
    PHP="$(
        echo '<?php'
        php --strip "$WP_CONFIG" |
            grep -Po "(?<=<\?php|;|^)\s*define\s*\(\s*(['\"])DB_(NAME|USER|PASSWORD|HOST)\1\s*,\s*('([^']+|\\\\')*'|\"([^\"\$]+|\\\\(\"|\\\$))*\")\s*\)\s*(;|\$)" |
            sed -E 's/[^;]$/&;/' || exit
        cat <<EOF
\$vals = array_map(function (\$v) { return addslashes(\$v); }, [DB_NAME, DB_USER, DB_PASSWORD, DB_HOST]);
printf("DB_NAME=%s\nDB_USER=%s\nDB_PASSWORD=%s\nDB_HOST=%s\n", \$vals[0], \$vals[1], \$vals[2], \$vals[3]);
EOF
    )" || return
    php <<<"$PHP"
}

# lk_wp_mysqldump_from_remote ssh_host [remote_path]
# shellcheck disable=SC1003,SC1091,SC2029,SC2087,SC2088
function lk_wp_mysqldump_from_remote() {
    local REMOTE_PATH="${2:-public_html}" WP_CONFIG DB_CONFIG EXIT_CODE=0 \
        DB_NAME DB_USER DB_PASSWORD DB_HOST
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    REMOTE_PATH="${REMOTE_PATH%/}"
    lk_console_item "Retrieving credentials from remote system:" "$1:$REMOTE_PATH/wp-config.php"
    WP_CONFIG="$(ssh "$1" cat "$REMOTE_PATH/wp-config.php")" || return
    DB_CONFIG="$(lk_wp_get_db_config <(echo "$WP_CONFIG"))" || return
    . /dev/stdin <<<"$DB_CONFIG" || return
    lk_console_item "Storing credentials for '$DB_USER'@'$DB_HOST' on remote system:" "~/.lk_mysqldump.cnf"
    ssh "$1" "bash -c 'cat >\"\$HOME/.lk_mysqldump.cnf\"'" <<EOF || return
[mysqldump]
user="$(lk_escape "$DB_USER" '\' '"')"
password="$(lk_escape "$DB_PASSWORD" '\' '"')"
host="$(lk_escape "$DB_HOST" '\' '"')"
EOF
    lk_console_message "Dumping remote database '$DB_NAME'"
    ssh "$1" "bash -c 'mysqldump --defaults-file=\"\$HOME/.lk_mysqldump.cnf\" --single-transaction --skip-lock-tables \"$DB_NAME\" | gzip; exit \"\${PIPESTATUS[0]}\"'" | pv || EXIT_CODE="$?"
    lk_console_message "Deleting credentials stored on remote system"
    ssh "$1" "bash -c 'rm -f \"\$HOME/.lk_mysqldump.cnf\"'" || :
    return "$EXIT_CODE"
}

# lk_wp_rsync_from_remote ssh_host [remote_path [local_path]]
function lk_wp_rsync_from_remote() {
    local REMOTE_PATH="${2:-public_html}" LOCAL_PATH="${3:-$HOME/public_html}" \
        ARGS=(-vrlptH -x --delete ${RSYNC_ARGS[@]+"${RSYNC_ARGS[@]}"}) DRY_RUN_DONE
    [ -n "${1:-}" ] || lk_warn "no ssh host" || return
    REMOTE_PATH="${REMOTE_PATH%/}"
    LOCAL_PATH="${LOCAL_PATH%/}"
    [ ! -f "$LOCAL_PATH/wp-config.php" ] || ARGS+=(--exclude="/wp-config.php")
    [ ! -d "$LOCAL_PATH/.git" ] || ARGS+=(--exclude="/.git")
    ARGS+=("$1:$REMOTE_PATH/" "$LOCAL_PATH/")
    while :; do
        lk_console_warning "Local changes in '$LOCAL_PATH' will be lost"
        echo "\
rsync command:
  $LK_BOLD${ARGS[*]}$LK_RESET
" >&2
        [ "${DRY_RUN_DONE:-0}" -eq "0" ] || break
        ! lk_confirm "Perform a trial run first?" Y && break ||
            rsync --dry-run "${ARGS[@]}" >&2
        echo >&2
        DRY_RUN_DONE=1
    done
    ! lk_confirm "OK to lose changes in '$LOCAL_PATH'?" N ||
        rsync "${ARGS[@]}"
}

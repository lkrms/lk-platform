#!/usr/bin/env bash

# _lk_mysql_is_quiet
#
# Check if _LK_MYSQL_QUIET is set.
function _lk_mysql_is_quiet() {
    [[ ${_LK_MYSQL_QUIET-} ]]
}

# lk_mysql_native_command <command>
#
# Resolve the name of a mysql command to the name of its local implementation,
# e.g. for `mysqldump` on MariaDB systems, print `mariadb-dump` if running on
# MariaDB 11.4+, otherwise print `mysqldump`.
function lk_mysql_native_command() {
    (($# == 1)) || lk_bad_args || return
    local cmd
    if cmd=$(type -P "$1") && [[ -L $cmd ]] && cmd=$(readlink "$cmd"); then
        printf '%s\n' "${cmd##*/}"
    else
        printf '%s\n' "$1"
    fi
}

#### Reviewed: 2026-03-31

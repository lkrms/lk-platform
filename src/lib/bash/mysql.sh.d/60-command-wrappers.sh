#!/usr/bin/env bash

# lk_mysql [<mysql_arg>...]
#
# - If `LK_MY_CNF` is set, run `mysql` as the current user and read default
#   options from `LK_MY_CNF` only.
# - If `LK_MYSQL_SUDO` is set, run `mysql` as the root user without reading
#   default options from any file.
# - Otherwise, run `mysql` as the current user with default options.
function lk_mysql() {
    if [[ -n ${LK_MY_CNF-} ]]; then
        [[ -f $LK_MY_CNF ]] || lk_warn "file not found: $LK_MY_CNF" || return
        "${_LK_MYSQL:-mysql}" --defaults-file="$LK_MY_CNF" "$@"
    elif [[ -n ${LK_MYSQL_SUDO-} ]]; then
        lk_elevate "${_LK_MYSQL:-mysql}" --no-defaults "$@"
    else
        "${_LK_MYSQL:-mysql}" "$@"
    fi
}

# lk_mysqldump [<mysql_arg>...]
#
# Run `mysqldump` in the same environment as `mysql` in `lk_mysql`.
function lk_mysqldump() {
    _LK_MYSQL=mysqldump lk_mysql "$@"
}

function lk_mysql_connects() {
    lk_mysql --execute '\q' "$@"
}

# shellcheck disable=SC2120
function lk_mysql_list() {
    lk_mysql --batch --raw --skip-column-names "$@"
}

function lk_mysql_mapfile() {
    (($# > 1)) && unset -v "$1" || lk_bad_args || return
    local _var=$1 _file
    shift
    lk_mktemp_with _file lk_mysql_list "$@" &&
        lk_mapfile "$_var" "$_file"
}

function lk_mysql_version() {
    local version
    version=$(mysql --version | grep -Eo '([0-9]+[.-])+MariaDB') ||
        lk_warn "unsupported MySQL version" || return
    printf '%s\n' "${version%-*}"
}

#### Reviewed: 2025-09-03

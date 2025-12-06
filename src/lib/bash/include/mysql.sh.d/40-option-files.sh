#!/usr/bin/env bash

# lk_mysql_option_bytes <size>
#
# Convert a size to bytes, where <size> is an integer with an optional
# case-insensitive `K`, `M`, `G`, `T`, `P` or `E` suffix.
function lk_mysql_option_bytes() { (
    shopt -s nocasematch
    # See https://mariadb.com/docs/server/server-management/variables-and-modes/server-system-variables
    [[ ${1-} =~ ^0*([0-9]+)[KMGTPE]?$ ]] || lk_err "invalid size: ${1-}" || exit
    case "$1" in
    *K) p=1 ;;
    *M) p=2 ;;
    *G) p=3 ;;
    *T) p=4 ;;
    *P) p=5 ;;
    *E) p=6 ;;
    *) p=0 ;;
    esac
    printf '%d\n' $((BASH_REMATCH[1] * 1024 ** p))
); }

# lk_mysql_options_client_print [<user> [<password> [<host>]]]
#
# Print client options.
#
# Values not given as arguments may be given via variables `DB_USER`,
# `DB_PASSWORD` and `DB_HOST`.
function lk_mysql_options_client_print() {
    local options=(
        user "${1-$DB_USER}"
        password "${2-$DB_PASSWORD}"
        host "${3-${DB_HOST-${LK_MYSQL_HOST:-localhost}}}"
    )
    printf '[client]\n'
    for ((i = 0; i < ${#options[@]}; i += 2)); do
        printf '%s=%s\n' "${options[i]}" \
            "$(lk_mysql_option_escape "${options[i + 1]}")"
    done
}

# [LK_MY_CNF=<file>] lk_mysql_options_client_write [<user> [<password> [<host>]]]
#
# Write client options to <file> (default: `~/.mysql.lk.my.cnf`) and apply its
# path to `LK_MY_CNF` in the caller's scope.
#
# Values not given as arguments may be given via variables `DB_USER`,
# `DB_PASSWORD` and `DB_HOST`.
#
# shellcheck disable=SC2120
function lk_mysql_options_client_write() {
    LK_MY_CNF=${LK_MY_CNF:-~/.mysql.lk.my.cnf}
    lk_mysql_options_client_print "$@" >"$LK_MY_CNF" || return
    lk_delete_on_exit "$LK_MY_CNF" 2>/dev/null || true
}

#### Reviewed: 2025-09-03

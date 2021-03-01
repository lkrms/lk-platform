#!/bin/bash

# shellcheck disable=SC2016,SC2034,SC2206,SC2207

lk_bash_at_least 4 2 || return 0

function __lkc_arg() {
    COMPREPLY=($(compgen \
        -W "$(_parse_help "$1") $* --help --no-log --yes" -- "$cur"))
    [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
}

function _lkc_keepassxc() {
    local cur prev words cword
    _init_completion || return
    if [[ $cur == -* ]]; then
        __lkc_arg "$@"
    else
        _filedir kdbx
    fi
} && complete -F _lkc_keepassxc lk-keepassxc.sh

function __lkc_mysql_db() {
    mysql --batch --skip-column-names <<<"SHOW DATABASES" 2>/dev/null
}

function _lkc_mysql_dump() {
    local cur prev words cword split
    _init_completion -s || return
    case "$prev" in
    -d | --dest)
        _filedir
        ;;
    -t | --timestamp)
        COMPREPLY=($(compgen -W "$(for i in %H%M%S %H%M00 %H0000; do
            printf "%(%Y-%m-%d-$i)T "
        done) ${LK_BACKUP_TIMESTAMP:-}" -- "$cur"))
        ;;
    *)
        case "$cur" in
        -*)
            __lkc_arg "$@"
            ;;
        *)
            COMPREPLY=($(compgen -W "$(__lkc_mysql_db)" -- "$cur"))
            ;;
        esac
        ;;
    esac
} && complete -F _lkc_mysql_dump lk-mysql-dump.sh

function _lkc_wp_migrate() {
    local cur prev words cword split \
        URL_PREFIX
    _init_completion -s || return
    case "$prev" in
    -s | -d | --source | --dest)
        _filedir
        ;;
    --maintenance)
        COMPREPLY=($(compgen -W "ignore on indefinite" -- "$cur"))
        ;;
    --rename)
        COMP_WORDBREAKS=${COMP_WORDBREAKS//:/}
        if [[ $cur =~ ^(https?://)(.*) ]]; then
            URL_PREFIX=${BASH_REMATCH[1]}
            _known_hosts_real -4 -6 -- "${BASH_REMATCH[2]}"
            COMPREPLY=(${COMPREPLY[@]/#/$URL_PREFIX})
        else
            COMPREPLY=($(compgen -W "http:// https://" -- "$cur"))
            compopt -o nospace
        fi
        ;;
    *)
        case "$cur" in
        -*)
            __lkc_arg "$@"
            ;;
        *)
            _known_hosts_real -a -- "$cur"
            ;;
        esac
        ;;
    esac
} && complete -F _lkc_wp_migrate lk-wp-migrate.sh

function _lkc_wp() {
    local cur prev words cword \
        IFS=$'\n' COMP
    _init_completion || return
    COMP=($(wp --skip-plugins --skip-themes \
        cli completions --line="${COMP_LINE:3}" --point=$((COMP_POINT - 3))))
    COMPREPLY=($(grep -Ev '^(<file>[[:blank:]]*)?$' <<<"${COMP[*]}"))
    [ ${#COMP[@]} -eq ${#COMPREPLY[@]} ] && [ ${#COMP[@]} -gt 0 ] ||
        _filedir
} && complete -o nospace -F _lkc_wp lk_wp

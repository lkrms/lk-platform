#!/bin/bash

#function __lk_template() {
#    # Either:
#    local cur prev words cword
#    _init_completion || return
#
#    # or if you have --option=VALUE arguments:
#    local cur prev words cword split
#    _init_completion -s || return
#
#    # Then, something like:
#    case "$prev" in
#    -t | --timestamp)
#        # Note the single quotes
#        COMPREPLY=($(compgen -W '$(__lk_backup_timestamps)' -- "$cur"))
#        ;;
#    *)
#        case "$cur" in
#        -*) __lk_options "$@" ;;
#        *) _known_hosts_real -a -- "$cur" ;;
#        esac
#        ;;
#    esac
#}

lk_bash_at_least 4 2 || return 0

function __lk_options() {
    local opts
    opts=$({
        _parse_help "$1"
        printf '%s\n' --{help,version,dry-run,yes,no-log}
    } | sort -u)
    COMPREPLY=($(compgen -W '$opts' -- "$cur"))
    [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
}

function __lk_backup_timestamps() { {
    local i
    for i in %H%M%S %H%M00 %H0000; do
        printf "%(%Y-%m-%d-$i)T\n" -1
    done
    [ -z ${LK_BACKUP_TIMESTAMP-} ] || echo "$LK_BACKUP_TIMESTAMP"
} | sort -u; }

function __lk_mysql_databases() {
    mysql --batch --skip-column-names <<<"SHOW DATABASES" 2>/dev/null
}

function __lk_generic() {
    local cur prev words cword
    _init_completion || return
    if [[ $cur == -* ]]; then
        __lk_options "$@"
    else
        case "$1" in
        lk-keepassxc.sh) _filedir kdbx ;;
        lk-ssh-configure-migration.sh) _known_hosts_real -a -- "$cur" ;;
        *) _filedir ;;
        esac
    fi
} && complete -F __lk_generic \
    lk-keepassxc.sh \
    lk-ssh-configure-migration.sh \
    lk-wp-dev-reset.sh

function __lk_mysql_dump() {
    local cur prev words cword split
    _init_completion -s || return
    case "$prev" in
    -d | --dest) _filedir ;;
    -t | --timestamp)
        COMPREPLY=($(compgen -W '$(__lk_backup_timestamps)' -- "$cur"))
        ;;
    *)
        case "$cur" in
        -*) __lk_options "$@" ;;
        *)
            COMPREPLY=($(compgen -W '$(__lk_mysql_databases)' -- "$cur"))
            ;;
        esac
        ;;
    esac
} && complete -F __lk_mysql_dump lk-mysql-dump.sh

function __lk_wp_migrate() {
    local cur prev words cword split
    _init_completion -s || return
    case "$prev" in
    -s | --source | -d | --dest) _filedir -d ;;
    -m | --maintenance)
        COMPREPLY=($(compgen -W "ignore off on permanent" -- "$cur"))
        ;;
    -r | --rename)
        COMP_WORDBREAKS=${COMP_WORDBREAKS//:/}
        if [[ $cur =~ ^(https?://)(.*) ]]; then
            local url_prefix=${BASH_REMATCH[1]}
            _known_hosts_real -4 -6 -- "${BASH_REMATCH[2]}"
            COMPREPLY=(${COMPREPLY[@]/#/$url_prefix})
        else
            COMPREPLY=($(compgen -W "http:// https://" -- "$cur"))
            compopt -o nospace
        fi
        ;;
    *)
        case "$cur" in
        -*) __lk_options "$@" ;;
        *) _known_hosts_real -a -- "$cur" ;;
        esac
        ;;
    esac
} && complete -F __lk_wp_migrate lk-wp-migrate.sh

function __lk_wp() {
    local cur prev words cword
    _init_completion || return
    local opts
    opts=($(
        point=$COMP_POINT
        # `wp cli completions` doesn't expand "--path" to "--path=", but it does
        # expand "--pat" to "--path=", so pass --point=$((COMP_POINT - 1)) and
        # use `compgen -W` to filter out any irrelevant results
        [ -n "$cur" ] && ((point--))
        "$1" cli completions \
            --line="$COMP_LINE" \
            --point=$((point > ${#1} ? point : ${#1} + 1))
    ))
    if [[ ${opts-} == "<file>" ]]; then
        _filedir
    else
        COMPREPLY=($(compgen -W '${opts[*]}' -- "$cur"))
        [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
    fi
} && complete -F __lk_wp lk_wp wp

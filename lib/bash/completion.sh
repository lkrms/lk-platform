#!/bin/bash

lk_bash_at_least 4 2 || return 0

complete -F _command \
    lk_faketty \
    lk_git_with_repos

# __lk_get_cpos [OPTION...]
#
# Set cpos to the number of the current positional parameter, or to zero if the
# current parameter is an option or argument, or to -<OFFSET> if the current
# parameter appears after a '--' parameter at ${words[<OFFSET>-1]}. Also assign
# positional parameters up to and including the current parameter to pwords.
#
# Use OPTION to specify any options that have a required argument. Ensure cpos
# and pwords are local before calling this function.
#
# If a '--' parameter appears before the first positional parameter, subsequent
# parameters are interpreted as positional. If a '--' parameter appears after
# positional parameters, cpos is set to the index of the next parameter and
# negated (see above).
function __lk_get_cpos() {
    local IFS=, args i
    args=$*
    cpos=0
    pwords=()
    for ((i = 1; i <= cword; i++)); do
        if ((i < cword)) && [[ ${words[i]} == -- ]]; then
            if ((cpos)); then
                ((cpos = -(i + 1)))
                return
            fi
            ((cpos = cword - i))
            continue
        elif ((cpos)); then
            :
        elif [[ ${words[i]} != -* ]]; then
            ((cpos = cword - i + 1))
        elif [[ ,$args, == *,"${words[i]}",* ]]; then
            ((i++))
        fi
        ((cpos)) && pwords[${#pwords[@]}]=${words[i]}
    done
}

# __lk_options COMMAND [EXTRA_OPTION...]
#
# Complete the current word by parsing the output of `COMMAND --help`.
function __lk_options() {
    COMPREPLY=($(compgen -W "$({ _parse_help "$1" && shift &&
        printf '%s\n' --{help,dry-run,yes} "$@"; } | sort -u)" -- "$cur"))
    [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
}

function __lk_scp_local_or_remote_files() {
    _expand || return
    if [[ $cur == *:* ]]; then
        _xfunc ssh _scp_remote_files "$@"
    else
        _known_hosts_real -c -a -- "$cur"
        _xfunc ssh _scp_local_files "$@"
    fi
}

function __lk_backup_source_names() {
    COMPREPLY=($(compgen -W "$({ hostname -s && id -un &&
        ls -1 "${LK_BACKUP_ROOT:-/srv/backup}/snapshot/"; } 2>/dev/null |
        sort -u)" -- "$cur"))
}

function __lk_backup_timestamps() {
    COMPREPLY=($(compgen -W \
        "$({ for fmt in %H%M%S %H%M00 %H0000; do
            printf "%(%Y-%m-%d-$fmt)T\n" -1
        done && echo "${LK_BACKUP_TIMESTAMP-}"; } | sort -u)" -- "$cur"))
}

function __lk_mysql_databases() {
    COMPREPLY=($(compgen -W "$(mysql --batch --skip-column-names \
        <<<"SHOW DATABASES" 2>/dev/null)" -- "$cur"))
}

function __lk_generic() {
    local cur prev words cword
    _init_completion || return
    if [[ $cur == -* ]]; then
        __lk_options "$1"
    else
        case "${1##*/}" in
        lk-keepassxc.sh) _filedir kdbx ;;
        lk-ssh-configure-migration.sh) _known_hosts_real -a -- "$cur" ;;
        *) _filedir ;;
        esac
    fi
} && complete -F __lk_generic \
    lk-backup-prune-snapshots.sh \
    lk-cloud-image-boot.sh \
    lk-handbrake-batch.sh \
    lk-keepassxc.sh \
    lk-maildir-archive-by-year.sh \
    lk-mysql-grant.sh \
    lk-provision-arch.sh \
    lk-ssh-configure-migration.sh \
    lk-wp-dev-reset.sh \
    lk-xfce4-apply-dpi.sh \
    lk-xkb-load.sh

function __lk_backup_create_snapshot() {
    local cur prev words cword split cpos pwords
    _init_completion -s -n : || return
    __lk_get_cpos -g --group -f --filter -h --hook
    ((!cpos)) && [[ $prev == -* ]] &&
        case "$prev" in
        -g | --group) _allowed_groups "$cur" ;;&
        -f | --filter) _filedir ;;&
        -h | --hook)
            if [[ $cur =~ ^[^:]+:(.*) ]]; then
                # This works because Bash starts completing a new argument after
                # a colon
                cur=${BASH_REMATCH[1]}
                _filedir
            else
                local hooks=({pre,post}_rsync)
                COMPREPLY=($(compgen -W '${hooks[@]/%/:}' -- "$cur"))
                compopt -o nospace
            fi
            ;;&
        *) return ;;
        esac
    case "$cpos,$cur" in
    0,-*) __lk_options "$1" ;;
    1,*) __lk_backup_source_names ;;
    2,*) __lk_scp_local_or_remote_files -d ;;
    3,*) _filedir -d ;;
    -*) _xfunc rsync _rsync ;;
    esac
} && complete -F __lk_backup_create_snapshot lk-backup-create-snapshot.sh

function __lk_mysql_dump() {
    local cur prev words cword split
    _init_completion -s || return
    case "$prev" in
    -d | --dest) _filedir ;;
    -t | --timestamp) __lk_backup_timestamps ;;
    *)
        case "$cur" in
        -*) __lk_options "$1" ;;
        *) __lk_mysql_databases ;;
        esac
        ;;
    esac
} && complete -F __lk_mysql_dump lk-mysql-dump.sh

function __lk_wp_migrate() {
    local cur prev words cword split
    _init_completion -s -n : || return
    case "$prev" in
    -s | --source | -d | --dest) _filedir -d ;;
    -m | --maintenance)
        COMPREPLY=($(compgen -W "ignore off on permanent" -- "$cur"))
        ;;
    -r | --rename)
        if [[ $cur =~ ^https?://(.*) ]]; then
            _known_hosts_real -4 -6 -- "${BASH_REMATCH[1]}"
            COMPREPLY=("${COMPREPLY[@]/#/\/\/}")
        else
            COMPREPLY=($(compgen -W "http:// https://" -- "$cur"))
            compopt -o nospace
        fi
        ;;
    *)
        case "$cur" in
        -*) __lk_options "$1" ;;
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
        COMPREPLY=($(compgen -W '${opts[@]}' -- "$cur"))
        [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
    fi
} && complete -F __lk_wp lk_wp wp

#!/bin/bash

# shellcheck disable=SC2016,SC2034,SC2206,SC2207

function _lkc_keepassxc() {
    local cur prev words cword
    _init_completion || return
    if [[ $cur == -* ]]; then
        COMPREPLY=($(compgen -W '$(_parse_help "$1")' -- "$cur"))
        [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
    else
        _filedir kdbx
    fi
} && complete -F _lkc_keepassxc lk-keepassxc.sh

function _lkc_wp_migrate() {
    local cur prev words cword split \
        URL_PREFIX
    _init_completion -s || return
    case "$prev" in
    -s | -d | -e | --source | --dest | --exclude)
        _filedir
        ;;
    --maintenance)
        COMPREPLY=($(compgen -W 'ignore on indefinite' -- "$cur"))
        ;;
    --rename)
        COMP_WORDBREAKS=${COMP_WORDBREAKS//:/}
        if [[ $cur =~ ^(https?://)(.*) ]]; then
            URL_PREFIX=${BASH_REMATCH[1]}
            _known_hosts_real -4 -6 -- "${BASH_REMATCH[2]}"
            COMPREPLY=(${COMPREPLY[@]/#/$URL_PREFIX})
        else
            COMPREPLY=($(compgen -W 'http:// https://' -- "$cur"))
            compopt -o nospace
        fi
        ;;
    *)
        case "$cur" in
        -*)
            COMPREPLY=($(compgen -W '$(_parse_help "$1") --yes' -- "$cur"))
            [[ ${COMPREPLY-} == *= ]] && compopt -o nospace
            ;;
        *)
            _known_hosts_real -a -- "$cur"
            ;;
        esac
        ;;
    esac
} && complete -F _lkc_wp_migrate lk-wp-migrate.sh

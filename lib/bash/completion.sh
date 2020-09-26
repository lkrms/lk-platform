#!/bin/bash

# shellcheck disable=SC2016,SC2034,SC2207

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

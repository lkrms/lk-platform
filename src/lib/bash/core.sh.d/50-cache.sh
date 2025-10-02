#!/usr/bin/env bash

# _lk_cache_dir [<stack_depth>]
function _lk_cache_dir() {
    local TMPDIR=${TMPDIR:-/tmp} depth=$((${_LK_STACK_DEPTH-0} + ${1-0}))
    local dir=${TMPDIR%/}/lk_cache_${EUID}
    local dirs=("$dir")
    [[ -z ${LK_CACHE_NAMESPACE-} ]] || {
        dir=$dir/$LK_CACHE_NAMESPACE
        dirs[${#dirs[@]}]=$dir
    }
    local file=${BASH_SOURCE[depth + 2]-${0##*/}}
    dir=$dir/${file//"/"/__}
    dirs[${#dirs[@]}]=$dir
    [[ -d $dir ]] || install -d -m 0700 "${dirs[@]}" || return
    printf '%s\n' "$dir"
}

# _lk_cache_init [-f] [-t <ttl>] [--] <command> [<arg>...]
function _lk_cache_init() {
    local depth=$((${_LK_STACK_DEPTH-0})) force=0 ttl=300 age
    while [[ ${1-} == -* ]]; do
        case "$1" in
        -f) force=1 ;;
        -t) ttl=${2-} && shift ;;
        --) shift && break ;;
        *) lk_bad_args || return ;;
        esac
        shift || lk_bad_args || return
    done
    cmd=("$@")
    file=$(_lk_cache_dir 1)/${FUNCNAME[depth + 2]-${0##*/}}_$(lk_hash "$@") || return
    hit=1
    if ((force)) || [[ ! -f $file ]] || {
        ((ttl)) && age=$(lk_file_age "$file") && ((age > ttl))
    }; then
        hit=0
    fi
}

# lk_cache [-f] [-t <ttl>] [--] <command> [<arg>...]
#
# If the most recent run of a command was successful, print its output again and
# return. Otherwise, run the command and cache its output for subsequent runs if
# its exit status is zero.
#
# Options:
#
#     -t <ttl>  Number of seconds output from the command is considered fresh,
#               or 0 to use cached output indefinitely (default: 300)
#     -f        Run the command even if cached output is available
#
# Cached output is stored under `TMPDIR` in directories that can only be
# accessed by the current user. Pathnames are derived from:
# - `LK_CACHE_NAMESPACE` (if set)
# - caller filename (to prevent downstream naming collisions)
# - caller name
function lk_cache() {
    local cmd file hit
    _lk_cache_init "$@" &&
        if ((hit)); then
            cat "$file"
        else
            local tmp=${file%/*}/.${file##*/}.tmp
            "${cmd[@]}" | tee -- "$tmp" && mv -f "$tmp" "$file" ||
                lk_pass rm -f -- "$file" "$tmp"
        fi
}

# lk_cache_has [-t <ttl>] [--] <command> [<arg>...]
#
# Check if cached output is available for a command.
#
# The state of the output cache may change between calls to `lk_cache_has` and
# `lk_cache`. Code that assumes otherwise may be vulnerable to race conditions.
function lk_cache_has() {
    local cmd file hit
    _lk_cache_init "$@" &&
        ((hit == 1))
}

# lk_cache_flush
#
# Discard output cached by calls to `lk_cache` from the caller's source file.
function lk_cache_flush() {
    local dir
    dir=$(_lk_cache_dir) &&
        rm -Rf -- "$dir"
}

#### Reviewed: 2025-10-03

#!/bin/bash

[ -n "${_LK_INST-}" ] || { SH=$(
    set -u
    lk_die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }
    _FILE=$BASH_SOURCE && [ -f "$_FILE" ] && [ ! -L "$_FILE" ] ||
        lk_die "script must be sourced directly"
    [[ $_FILE == */* ]] || _FILE=./$_FILE
    _DIR=$(cd "${_FILE%/*}" && pwd -P) &&
        printf 'export LK_BASE=%q\n' "${_DIR%/lib/bash}" ||
        lk_die "LK_BASE not found"
    # Discard settings with the same name as LK_* variables in the environment
    # and add any that remain to the global scope
    vars() { printf '%s\n' "${!LK_@}"; }
    _PATH_PREFIX=${LK_PATH_PREFIX-}
    unset IFS LK_PATH_PREFIX
    VARS=$(vars)
    [ ! -r /etc/default/lk-platform ] ||
        . /etc/default/lk-platform || exit
    [ ! -r "${_DIR%/lib/bash}/etc/lk-platform/lk-platform.conf" ] ||
        . "${_DIR%/lib/bash}/etc/lk-platform/lk-platform.conf" || exit
    XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-~/.config}
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${_PATH_PREFIX:-lk-}}
    [ ! -f ~/".${LK_PATH_PREFIX}settings" ] ||
        . ~/".${LK_PATH_PREFIX}settings" || exit
    [ ! -f "$XDG_CONFIG_HOME/lk-platform/lk-platform.conf" ] ||
        . "$XDG_CONFIG_HOME/lk-platform/lk-platform.conf" || exit
    unset LK_BASE $VARS
    VARS=$(vars)
    [ -z "${VARS:+1}" ] ||
        declare -p $VARS
) && eval "$SH" || return; }
SH=$(. "${_LK_INST:-$LK_BASE}/lib/bash/env.sh") && eval "$SH" || return
unset SH

. "${_LK_INST:-$LK_BASE}/lib/bash/include/core.sh" || return
set -E

lk_require assert

function _lk_getopt_usage_available() {
    [[ $(type -t __usage) == "function" ]] ||
        [ -n "${LK_USAGE:+1}" ]
} #### Reviewed: 2021-12-30

function _lk_getopt_version_available() {
    [[ $(type -t __version) == "function" ]] ||
        [ -n "${LK_VERSION:+1}" ]
} #### Reviewed: 2021-12-30

function _lk_getopt_add_long() {
    [[ ,$LONG, == *,$1,* ]] ||
        LONG=${LONG:+$LONG,}$1
} #### Reviewed: 2021-12-30

function lk_getopt() {
    local SHIFT=0
    [[ ${1-} != -* ]] || { SHIFT=${1#-} && shift; }
    local SHORT=${1-} LONG=${2-} ARGC=$# GETOPT OPT OPTS=()
    ! _lk_getopt_usage_available || _lk_getopt_add_long "help"
    ! _lk_getopt_version_available || _lk_getopt_add_long version
    _lk_getopt_add_long dry-run
    _lk_getopt_add_long run
    _lk_getopt_add_long yes
    _lk_getopt_add_long no-log
    GETOPT=$(gnu_getopt \
        --options "$SHORT" \
        --longoptions "$LONG" \
        --name "${0##*/}" \
        -- ${_LK_ARGV[@]+"${_LK_ARGV[@]:SHIFT}"}) || lk_usage
    eval "set -- $GETOPT"
    while :; do
        case "$1" in
        --help)
            ! _lk_getopt_usage_available || {
                _lk_usage ""
                exit
            }
            ;;
        --version)
            ! _lk_getopt_version_available || {
                _lk_version ""
                exit
            }
            ;;
        esac
        SHIFT=1
        case "$1" in
        --dry-run)
            LK_DRY_RUN=1
            shift
            continue
            ;;
        --run)
            unset LK_DRY_RUN
            shift
            continue
            ;;
        --yes)
            LK_NO_INPUT=1
            shift
            continue
            ;;
        --no-log)
            _LK_NO_LOG=1
            shift
            continue
            ;;
        --)
            break
            ;;
        --*)
            OPT=${1:2}
            [[ ,$LONG, == *,$OPT,* ]] || ((SHIFT++))
            ;;
        -*)
            OPT=${1:1}
            [[ $SHORT != *$OPT:* ]] || ((SHIFT++))
            ;;
        esac
        while ((SHIFT--)); do
            OPTS[${#OPTS[@]}]=$1
            shift
        done
    done
    ((ARGC)) || shift
    OPTS+=("$@")
    LK_GETOPT=$(lk_quote_arr OPTS)
} #### Reviewed: 2021-12-30

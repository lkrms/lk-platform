#!/bin/bash

[ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)

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

lk_include assert

function lk_is_dry_run() {
    [ -n "${LK_DRY_RUN-}" ]
}

# lk_maybe [-p] COMMAND [ARG...]
function lk_maybe() {
    local PRINT=
    [ "${1-}" != -p ] || { PRINT=1 && shift; }
    if lk_is_dry_run; then
        ! lk_is_true PRINT && ! lk_verbose ||
            lk_console_item \
                "[DRY RUN] Not running:" $'\n'"$(lk_quote_args "$@")"
    else
        "$@"
    fi
}

function _lk_getopt_maybe_add_long() {
    [[ ,$LONG, == *,$1,* ]] ||
        { [ $# -gt 1 ] && [ -z "${!2-}" ]; } ||
        LONG=${LONG:+$LONG,}$1
}

function lk_getopt() {
    local SHIFT=0
    [[ ${1-} != -* ]] || { SHIFT=${1#-} && shift; }
    local SHORT=${1-} LONG=${2-} ARGC=$# _OPTS HAS_ARG OPT OPTS=()
    _lk_getopt_maybe_add_long help LK_USAGE
    _lk_getopt_maybe_add_long version LK_VERSION
    _lk_getopt_maybe_add_long dry-run
    _lk_getopt_maybe_add_long yes
    _lk_getopt_maybe_add_long no-log
    _OPTS=$(gnu_getopt --options "$SHORT" \
        --longoptions "$LONG" \
        --name "${0##*/}" \
        -- ${_LK_ARGV[@]+"${_LK_ARGV[@]:SHIFT}"}) || lk_usage
    eval "set -- $_OPTS"
    while :; do
        case "$1" in
        --help)
            [ -z "${LK_USAGE-}" ] || {
                sed -E 's/^\\(.)/\1/' <<<"$LK_USAGE"
                exit
            }
            ;;
        --version)
            [ -z "${LK_VERSION-}" ] || {
                echo "$LK_VERSION"
                exit
            }
            ;;
        esac
        HAS_ARG=0
        case "$1" in
        --dry-run)
            LK_DRY_RUN=1
            shift
            continue
            ;;
        --yes)
            LK_NO_INPUT=1
            shift
            continue
            ;;
        --no-log)
            LK_NO_LOG=1
            shift
            continue
            ;;
        --)
            break
            ;;
        --*)
            OPT=${1:2}
            [[ ,$LONG, == *,$OPT,* ]] || HAS_ARG=1
            ;;
        -*)
            OPT=${1:1}
            [[ $SHORT != *$OPT:* ]] || HAS_ARG=1
            ;;
        esac
        while [ $((HAS_ARG--)) -ge 0 ]; do
            OPTS+=("$1")
            shift
        done
    done
    [ "$ARGC" -gt 0 ] || shift
    OPTS+=("$@")
    LK_GETOPT=$(lk_quote OPTS)
}

#!/bin/bash

# shellcheck disable=SC1090,SC2120,SC2128,SC2207

_LK_ENV=${_LK_ENV:-$(declare -x)}

lk_die() { s=$? && echo "$BASH_SOURCE: $1" >&2 && (exit $s) && false || exit; }
[ -n "${LK_INST:-${LK_BASE:-}}" ] || lk_die "LK_BASE not set"
[ ! "${LK_INST:+1}${LK_BASE:+2}" = 2 ] || export LK_BASE

. "${LK_INST:-$LK_BASE}/lib/bash/include/core.sh"

# 1. Source each SETTINGS file in order, allowing later files to override values
#    set earlier
# 2. Discard settings with the same name as any LK_* variables found in the
#    environment
# 3. Copy remaining LK_* variables to the global scope (other variables are
#    discarded)
[[ ,${LK_SKIP:-}, == *,settings,* ]] || { SH=$(
    if [ -n "${LK_SETTINGS_FILES+1}" ]; then
        SETTINGS=("${LK_SETTINGS_FILES[@]}")
    else
        # Passed to lk_expand_template just before sourcing, to allow expansion
        # of values set by earlier files
        SETTINGS=(
            /etc/default/lk-platform
            ~/".{{LK_PATH_PREFIX}}settings"
        )
    fi
    # lk_var lists all LK_* variables that aren't environment variables
    ENV=$(lk_get_env -n | sed '/^LK_/!d' | sort)
    lk_var() { comm -23 \
        <(printf '%s\n' "${!LK_@}" | sort) \
        <(cat <<<"$ENV") | sed '/^LK_ARGV$/d'; }
    (
        VAR=($(lk_var))
        [ ${#VAR[@]} -eq 0 ] || unset "${VAR[@]}"
        for FILE in "${SETTINGS[@]}"; do
            FILE=$(lk_expand_template <<<"$FILE" 2>/dev/null) || continue
            [ ! -r "$FILE" ] || . "$FILE"
        done
        VAR=($(lk_var))
        [ ${#VAR[@]} -eq 0 ] || lk_get_quoted_var "${VAR[@]}"
    )
) && eval "$SH"; }

# shellcheck disable=SC2154
lk_include assert ${include:+${include//,/ }}

# lk_die [MESSAGE]
#
# Output "<context>: MESSAGE" using lk_console_error and exit non-zero with the
# previous command's exit status (if available).
#
# To suppress output, set MESSAGE to the empty string.
function lk_die() {
    local EXIT_STATUS=$?
    [ "$EXIT_STATUS" -ne 0 ] || EXIT_STATUS=1
    if [ $# -eq 0 ] || [ -n "$1" ]; then
        lk_console_error "$(_lk_caller): ${1:-execution failed}"
    fi
    exit "$EXIT_STATUS"
}

function lk_exit_trap() {
    local EXIT_STATUS=$? i
    [ "$EXIT_STATUS" -eq 0 ] ||
        [[ ${FUNCNAME[1]:-} =~ ^_?lk_(die|usage|elevate)$ ]] ||
        lk_console_error \
            "$(_lk_caller "${_LK_ERR_TRAP_CONTEXT:-}"): unhandled error"
    for i in ${_LK_EXIT_DELETE[@]+"${_LK_EXIT_DELETE[@]}"}; do
        lk_elevate_if_error rm -Rf -- "$i" || true
    done
}

function lk_err_trap() {
    _LK_ERR_TRAP_CONTEXT=$(caller 0) || _LK_ERR_TRAP_CONTEXT=
}

function lk_delete_on_exit() {
    [ -n "${_LK_EXIT_DELETE+1}" ] || _LK_EXIT_DELETE=()
    _LK_EXIT_DELETE+=("$@")
}

function lk_usage() {
    local EXIT_STATUS=$? MESSAGE=${1:-${LK_USAGE:-}}
    [ -z "$MESSAGE" ] || MESSAGE=$(_lk_usage_format "$MESSAGE")
    LK_TTY_NO_FOLD=1 \
        lk_console_log "${MESSAGE:-$(_lk_caller): invalid arguments}"
    exit "$EXIT_STATUS"
}

function _lk_getopt_maybe_add_long() {
    [[ ,$LONG, == *,$1,* ]] ||
        { [ $# -gt 1 ] && [ -z "${!2:-}" ]; } ||
        LONG=${LONG:+$LONG,}$1
}

# shellcheck disable=SC2034
function lk_getopt() {
    local SHORT=${1:-} LONG=${2:-} ARGC=$# _OPTS HAS_ARG OPT OPTS=()
    _lk_getopt_maybe_add_long help LK_USAGE
    _lk_getopt_maybe_add_long version LK_VERSION
    _lk_getopt_maybe_add_long dry-run
    _lk_getopt_maybe_add_long yes
    _lk_getopt_maybe_add_long no-log
    _OPTS=$(gnu_getopt --options "$SHORT" \
        --longoptions "$LONG" \
        --name "${0##*/}" \
        -- ${LK_ARGV[@]+"${LK_ARGV[@]}"}) || lk_usage
    eval "set -- $_OPTS"
    while :; do
        case "$1" in
        --help)
            [ -z "${LK_USAGE:-}" ] || {
                echo "$LK_USAGE"
                exit
            }
            ;;
        --version)
            [ -z "${LK_VERSION:-}" ] || {
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

if ! lk_is_true LK_NO_SOURCE_FILE; then
    function _lk_elevate() {
        if [ $# -gt 0 ]; then
            sudo -H "$@"
        else
            sudo -H "$0" "${LK_ARGV[@]}"
            exit
        fi
    }

    function lk_elevate() {
        if [ "$EUID" -eq 0 ]; then
            if [ $# -gt 0 ]; then
                "$@"
            fi
        else
            _lk_elevate "$@"
        fi
    }

    function lk_maybe_elevate() {
        if [ "$EUID" -ne 0 ] && lk_can_sudo "${1-$0}"; then
            _lk_elevate "$@"
        elif [ $# -gt 0 ]; then
            "$@"
        fi
    }
fi

SH=$(
    [[ ,${LK_SKIP:-}, == *,env,* ]] || {
        printf '%s=%q\n' \
            LK_PATH_PREFIX "${LK_PATH_PREFIX-lk-}"
        . "${LK_INST:-$LK_BASE}/lib/bash/env.sh"
    }

    [[ ,${LK_SKIP:-}, == *,trap,* ]] || {
        printf 'trap %q %s\n' \
            lk_exit_trap EXIT \
            lk_err_trap ERR
        echo "set -E"
    }
) && eval "$SH"
unset SH

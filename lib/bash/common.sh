#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2046,SC2086,SC2207

_LK_ENV=${_LK_ENV:-$(declare -x)}

lk_die() { s=$? && echo "${BASH_SOURCE[0]}: $1" >&2 &&
    (return $s) && false || exit; }
[ -n "${LK_INST:-${LK_BASE:-}}" ] || lk_die "LK_BASE not set"
[ -z "${LK_BASE:-}" ] || export LK_BASE

# 1. Source each SETTINGS file in order, allowing later files to override values
#    set earlier
# 2. Discard settings with the same name as any LK_* variables found in the
#    environment
# 3. Copy remaining LK_* variables to the global scope (other variables are
#    discarded)
[[ ,${LK_SKIP:-}, == *,settings,* ]] || eval "$(
    if [ "${LK_SETTINGS_FILES[*]+1}" = 1 ]; then
        SETTINGS=(${LK_SETTINGS_FILES[@]+"${LK_SETTINGS_FILES[@]}"})
    else
        # Passed to eval just before sourcing, to allow expansion of values set
        # by earlier files
        SETTINGS=(
            "/etc/default/lk-platform"
            ${HOME:+"\$HOME/.\${LK_PATH_PREFIX:-lk-}settings"}
        )
    fi
    ENV="$(printenv | grep -Eio '^LK_[a-z0-9_]*' | sort)" || true
    lk_var() { comm -23 <(printf '%s\n' "${!LK_@}" | sort) <(cat <<<"$ENV"); }
    (
        VAR=($(lk_var))
        [ "${#VAR[@]}" -eq 0 ] || unset "${VAR[@]}"
        for FILE in "${SETTINGS[@]}"; do
            eval "FILE=\"$FILE\""
            [ ! -f "$FILE" ] || . "$FILE"
        done
        VAR=($(lk_var))
        [ "${#VAR[@]}" -eq 0 ] || declare -p $(lk_var)
    )
)"

colour=dynamic . "${LK_INST:-$LK_BASE}/lib/bash/include/core.sh"

lk_include assert $(
    include=${include:-}
    echo "${include//,/ }"
)

# lk_die [MESSAGE]
#
# Output "<context>: MESSAGE" as an error and exit non-zero with the previous
# command's exit status (if available).
#
# To suppress output, set MESSAGE to the empty string.
function lk_die() {
    local EXIT_STATUS=$?
    if lk_is_true "${LK_DIE_HAPPY:-}"; then
        EXIT_STATUS=0
    elif [ "$EXIT_STATUS" -eq 0 ]; then
        EXIT_STATUS=1
    fi
    if [ $# -eq 0 ] || [ -n "$1" ]; then
        lk_console_error "$(_lk_caller): ${1:-execution failed}"
    fi
    exit "$EXIT_STATUS"
}

function lk_exit_trap() {
    local EXIT_STATUS=$? i
    [ "$EXIT_STATUS" -eq 0 ] ||
        [[ ${FUNCNAME[1]:-} =~ ^_?lk_(die|usage|elevate)$ ]] ||
        lk_console_error0 \
            "$(_lk_caller "${_LK_ERR_TRAP_CONTEXT:-}"): unhandled error"
    for i in ${LK_EXIT_DELETE[@]+"${LK_EXIT_DELETE[@]}"}; do
        rm -Rf -- "$i" || true
    done
}

function lk_err_trap() {
    _LK_ERR_TRAP_CONTEXT=$(caller 0) || _LK_ERR_TRAP_CONTEXT=
}

function lk_delete_on_exit() {
    [ "${LK_EXIT_DELETE[*]+1}" = 1 ] || LK_EXIT_DELETE=()
    LK_EXIT_DELETE+=("$@")
}

function lk_usage() {
    local EXIT_STATUS=$? MESSAGE=${1:-${LK_USAGE:-}}
    [ -z "$MESSAGE" ] || MESSAGE=$(_lk_usage_format "$MESSAGE")
    LK_CONSOLE_NO_FOLD=1 \
        lk_console_log "${MESSAGE:-$(_lk_caller): invalid arguments}"
    exit "$EXIT_STATUS"
}

function lk_check_args() {
    if [ -n "${LK_USAGE:-}" ] && lk_has_arg --help; then
        echo "$LK_USAGE"
        exit
    elif [ -n "${LK_VERSION:-}" ] && lk_has_arg --version; then
        echo "$LK_VERSION"
        exit
    elif lk_has_arg --yes; then
        # shellcheck disable=SC2034
        LK_NO_INPUT=1
    fi
}

# shellcheck disable=SC2016
function lk_get_env() {
    local VAR
    VAR=$(env -i bash -c "$(
        printf '%s\n' \
            "$_LK_ENV" \
            '[ -n "${!1+1}" ] || exit' \
            'echo "${!1}."'
    )" bash "$1") && echo "${VAR%.}"
}

if ! lk_is_true "${LK_NO_SOURCE_FILE:-0}"; then
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

# shellcheck disable=SC2034,SC2206
eval "$(
    [[ ,${LK_SKIP:-}, == *,env,* ]] || {
        printf '%s=%q\n' \
            LK_PATH_PREFIX "${LK_PATH_PREFIX:-lk-}" \
            LK_PATH_PREFIX_ALPHA "${LK_PATH_PREFIX_ALPHA:-$(
                sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
            )}"
        . "$LK_BASE/lib/bash/env.sh"
    }

    [[ ,${LK_SKIP:-}, == *,trap,* ]] || {
        printf 'trap %q %s\n' \
            "lk_exit_trap" "EXIT" \
            "lk_err_trap" "ERR"
        echo "set -E"
    }
)"

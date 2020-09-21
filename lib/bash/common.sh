#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2046,SC2086,SC2207

lk_die() { s=$? && echo "${BASH_SOURCE[0]}: $1" >&2 && (return $s) && false || exit; }
[ -n "${LK_INST:-${LK_BASE:-}}" ] || lk_die "LK_BASE not set"
[ -z "${LK_BASE:-}" ] || export LK_BASE

# 1. Source each SETTINGS file in order, allowing later files to override values
#    set earlier
# 2. Discard settings with the same name as any LK_* variables found in the
#    environment
# 3. Copy remaining LK_* variables to the global scope (other variables are
#    discarded)
eval "$(
    if [ "${LK_SETTINGS_FILES+1}" = 1 ]; then
        SETTINGS=(${LK_SETTINGS_FILES[@]+"${LK_SETTINGS_FILES[@]}"})
    else
        # passed to eval just before sourcing, to allow expansion of values set
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

colour=generate . "${LK_INST:-$LK_BASE}/lib/bash/core.sh"

lk_include assert $(
    include=${include:-}
    echo "${include//,/ }"
)

function lk_trap_exit() {
    function lk_exit_trap() {
        local EXIT_STATUS=$? i
        [ "$EXIT_STATUS" -eq 0 ] ||
            [[ ${FUNCNAME[1]:-} =~ ^_?lk_(die|usage|elevate)$ ]] ||
            lk_console_error0 "$(_lk_caller): unhandled error"
        for i in ${LK_EXIT_DELETE[@]+"${LK_EXIT_DELETE[@]}"}; do
            rm -Rf -- "$i" || true
        done
    }
    LK_EXIT_DELETE=()
    trap 'lk_exit_trap' EXIT
}

function lk_delete_on_exit() {
    lk_is_declared "LK_EXIT_DELETE" || lk_warn "no exit trap" || return
    LK_EXIT_DELETE+=("$@")
}

if ! lk_is_true "${LK_NO_SOURCE_FILE:-0}"; then
    function lk_usage() {
        echo "${1:-${USAGE:-Please see $0 for usage}}" >&2
        exit 1
    }

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
    IFS=$' \t\n,'
    SKIP=(
        ${LK_SKIP:-}
    )
    unset IFS

    lk_in_array "env" SKIP || {
        printf '%s=%q\n' \
            LK_PATH_PREFIX "${LK_PATH_PREFIX:-lk-}" \
            LK_PATH_PREFIX_ALPHA "${LK_PATH_PREFIX_ALPHA:-$(
                sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
            )}"
        . "$LK_BASE/lib/bash/env.sh"
    }

    lk_in_array "trap" SKIP ||
        echo "lk_trap_exit"
)"

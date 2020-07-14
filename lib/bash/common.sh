#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2030,SC2031,SC2046,SC2207

# 1. Source each SETTINGS file in order, allowing later files to override values
#    set earlier
# 2. Discard settings with the same name as any LK_* variables found in the
#    environment
# 3. Copy remaining LK_* variables to the global scope (other variables are
#    discarded)
eval "$(
    # passed to eval just before sourcing to allow expansion of values set by
    # earlier files
    SETTINGS=(
        "/etc/default/lk-platform"
        ${HOME:+"\$HOME/.\${LK_PATH_PREFIX:-lk-}settings"}
    )
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

LK_PATH_PREFIX="${LK_PATH_PREFIX:-lk-}"
LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(echo "$LK_PATH_PREFIX" |
    sed 's/[^a-zA-Z0-9]//g')}"

[ -n "${LK_BASE:-}" ] || eval "$(
    BS="${BASH_SOURCE[0]}"
    if [ ! -L "$BS" ] &&
        LK_BASE="$(cd "${BS%/*}/../.." && pwd -P)" &&
        [ -d "$LK_BASE/lib/bash" ]; then
        printf 'LK_BASE=%q' "$LK_BASE"
    else
        echo "$BS: LK_BASE not set" >&2
    fi
)"
export LK_BASE

. "$LK_BASE/lib/bash/core.sh"
. "$LK_BASE/lib/bash/assert.sh"

function _lk_include() {
    local INCLUDE INCLUDE_PATH
    for INCLUDE in ${LK_INCLUDE:+${LK_INCLUDE//,/ }}; do
        INCLUDE_PATH="$LK_BASE/lib/bash/$INCLUDE.sh"
        [ -r "$INCLUDE_PATH" ] ||
            lk_warn "file not found: $INCLUDE_PATH" || return
        echo ". \"\$LK_BASE/lib/bash/$INCLUDE.sh\""
    done
}

function lk_usage() {
    echo "${1:-${USAGE:-Please see $0 for usage}}" >&2
    lk_die
}

function lk_has_arg() {
    lk_in_array "$1" LK_ARGV
}

function _lk_elevate() {
    if [ "$#" -gt "0" ]; then
        sudo -H -E "$@"
    else
        sudo -H -E "$0" "${LK_ARGV[@]}"
        exit
    fi
}

function lk_elevate() {
    if [ "$EUID" -eq "0" ]; then
        if [ "$#" -gt "0" ]; then
            "$@"
        fi
    else
        _lk_elevate "$@"
    fi
}

function lk_maybe_elevate() {
    if [ "$EUID" -ne "0" ] && lk_can_sudo; then
        _lk_elevate "$@"
    elif [ "$#" -gt "0" ]; then
        "$@"
    fi
}

lk_trap_exit

eval "$(. "$LK_BASE/lib/bash/env.sh")"

LK_ARGV=("$@")

eval "$(LK_INCLUDE="${LK_INCLUDE:-${INCLUDE:-${include:-}}}" _lk_include)"
unset LK_INCLUDE

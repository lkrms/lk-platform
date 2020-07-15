#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2015,SC2030,SC2031,SC2046,SC2207

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
    [ "${LK_SETTINGS_FILES+1}" != "1" ] ||
        SETTINGS=(${LK_SETTINGS_FILES[@]+"${LK_SETTINGS_FILES[@]}"})
    ENV="$(printenv |
        grep -Eio '^LK_[a-z0-9_]*=' | sed -E 's/(.*)=/\1/' | sort)" || true
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

. "${LK_INST:-$LK_BASE}/lib/bash/core.sh"
. "${LK_INST:-$LK_BASE}/lib/bash/assert.sh"

function _lk_include() {
    local INCLUDE INCLUDE_PATH
    for INCLUDE in ${LK_INCLUDE:+${LK_INCLUDE//,/ }}; do
        INCLUDE_PATH="${LK_INST:-$LK_BASE}/lib/bash/$INCLUDE.sh"
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

# lk_log_output [log_dir]
function lk_log_output() {
    local LOG_DIR="${1-${LK_INST:-$LK_BASE}/var/log}" LOG_FILE LOG_PATH
    LOG_FILE="$(basename "$0")-$UID.log"
    for LOG_DIR in ${LOG_DIR:+"$LOG_DIR"} "/tmp"; do
        [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] ||
            lk_maybe_elevate install -d -m 0777 "$LOG_DIR" 2>/dev/null ||
            continue
        LOG_PATH="$LOG_DIR/$LOG_FILE"
        if [ -f "$LOG_PATH" ]; then
            [ -w "$LOG_PATH" ] || {
                lk_maybe_elevate chown "$UID:" "$LOG_PATH" &&
                    lk_maybe_elevate chmod 00600 "$LOG_PATH" ||
                    continue
            } 2>/dev/null
        else
            install -m 0600 /dev/null "$LOG_PATH" 2>/dev/null ||
                continue
        fi
        lk_log "$LK_BOLD====> $(basename "$0") invoked$(
            [ "${#LK_ARGV[@]}" -eq "0" ] || {
                printf ' with %s %s:' \
                    "${#LK_ARGV[@]}" \
                    "$(lk_maybe_plural \
                        "${#LK_ARGV[@]}" "argument" "arguments")"
                printf '\n- %q' "${LK_ARGV[@]}"
            }
        )$LK_RESET" >>"$LOG_PATH" &&
            exec 6>&1 7>&2 &&
            exec > >(tee >(lk_log >>"$LOG_PATH")) 2>&1 ||
            exit
        lk_echoc "Output is being logged to $LK_BOLD$LOG_PATH$LK_RESET" \
            "$LK_GREY" >&7
        return
    done
    lk_die "unable to open log file"
}

eval "$(LK_INCLUDE="${LK_INCLUDE:-${include:-}}" _lk_include)"
unset LK_INCLUDE

if [[ ! "${skip:-}" =~ (,|^)env(,|$) ]]; then
    LK_PATH_PREFIX="${LK_PATH_PREFIX:-lk-}"
    LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(
        echo "$LK_PATH_PREFIX" | sed 's/[^a-zA-Z0-9]//g'
    )}"
    eval "$(. "$LK_BASE/lib/bash/env.sh")"
fi

LK_ARGV=("$@")

lk_trap_exit

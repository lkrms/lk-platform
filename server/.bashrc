#!/bin/bash
# shellcheck disable=SC2030,SC2031

[ -n "${LK_BASE:-}" ] ||
    eval "$(
        RC_PATH="${BASH_SOURCE[0]}"
        if [ ! -L "$RC_PATH" ] &&
            LK_BASE="$(cd "$(dirname "$RC_PATH")/.." && pwd -P)" &&
            [ -d "$LK_BASE/lib/bash" ]; then
            export LK_BASE
            declare -p LK_BASE
        else
            echo "$RC_PATH: symbolic links to lk-platform scripts are not supported" >&2
        fi
    )"

eval "$(
    shopt -s nullglob
    [ ! -f "$LK_BASE/etc/server.conf" ] ||
        echo ". \"\$LK_BASE/etc/server.conf\""
    for FILE in "$LK_BASE/lib/bash"/*.sh; do
        echo ". \"\$LK_BASE/lib/bash/$(basename "$FILE")\""
    done
)"

function lk_find_latest() {
    local i TYPE="${1:-}" TYPE_ARGS=()
    [[ "$TYPE" =~ ^[bcdflps]+$ ]] && shift || TYPE="f"
    for i in $(seq "${#TYPE}"); do
        TYPE_ARGS+=(${TYPE_ARGS[@]+-o} -type "${TYPE:$i-1:1}")
    done
    [ "${#TYPE_ARGS[@]}" -eq 2 ] || TYPE_ARGS=(\( "${TYPE_ARGS[@]}" \))
    gnu_find -L . -xdev -regextype posix-egrep ${@+\( "$@" \)} "${TYPE_ARGS[@]}" -print0 | xargs -0 gnu_stat --format '%Y :%y %12s %N' | sort -nr | cut -d: -f2- | "${PAGER:-less}"
}

function latest() {
    lk_find_latest "${1:-fl}" ! \( -type d -name .git -prune \)
}

function latest_dir() {
    latest d
}

function latest_all() {
    lk_find_latest fl
}

function latest_all_dir() {
    lk_find_latest d
}

function find_all() {
    local FIND="${1:-}"
    [ -n "$FIND" ] || return
    shift
    gnu_find -L . -xdev -iname "*$FIND*" "$@"
}

export WP_CLI_CONFIG_PATH="$LK_BASE/etc/wp-cli.yml"

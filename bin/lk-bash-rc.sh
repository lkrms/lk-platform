#!/bin/bash
# shellcheck disable=SC2030,SC2031

unset LK_PROMPT_DISPLAYED

[ ! -f "/etc/default/lk-platform" ] || . "/etc/default/lk-platform"

[ -n "${LK_BASE:-}" ] ||
    eval "$(
        BS="${BASH_SOURCE[0]}"
        if [ ! -L "$BS" ] &&
            LK_BASE="$(cd "$(dirname "$BS")/.." && pwd -P)" &&
            [ -d "$LK_BASE/lib/bash" ]; then
            export LK_BASE
            declare -p LK_BASE
        else
            echo "$BS: LK_BASE not set" >&2
        fi
    )"

eval "$(
    shopt -s nullglob
    for FILE in "$LK_BASE/lib/bash"/{core,prompt,wordpress}.sh; do
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

shopt -s checkwinsize

shopt -s histappend
HISTCONTROL=ignorespace
HISTIGNORE=
HISTSIZE=
HISTFILESIZE=
HISTTIMEFORMAT="%b %_d %Y %H:%M:%S %z "

[ ! -f "/usr/share/bash-completion/bash_completion" ] || . "/usr/share/bash-completion/bash_completion"

export WP_CLI_CONFIG_PATH="$LK_BASE/etc/wp-cli.yml"

[ "${LK_PROMPT:-1}" -ne "1" ] || lk_enable_prompt

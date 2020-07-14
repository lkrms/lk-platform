#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2030,SC2031,SC2046,SC2207

unset LK_PROMPT_DISPLAYED

# see lib/bash/common.sh
eval "$(
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
. "$LK_BASE/lib/bash/prompt.sh"
. "$LK_BASE/lib/bash/git.sh"
. "$LK_BASE/lib/bash/wordpress.sh"

function lk_find_latest() {
    local i TYPE="${1:-}" TYPE_ARGS=()
    [[ "$TYPE" =~ ^[bcdflps]+$ ]] && shift || TYPE="f"
    for i in $(seq "${#TYPE}"); do
        TYPE_ARGS+=(${TYPE_ARGS[@]+-o} -type "${TYPE:$i-1:1}")
    done
    [ "${#TYPE_ARGS[@]}" -eq 2 ] || TYPE_ARGS=(\( "${TYPE_ARGS[@]}" \))
    lk_check_gnu_commands stat
    gnu_find -L . -xdev -regextype posix-egrep \
        ${@+\( "$@" \)} "${TYPE_ARGS[@]}" -print0 |
        xargs -0 gnu_stat --format '%Y :%y %12s %A %N' |
        sort -nr | cut -d: -f2- | "${PAGER:-less}"
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

if lk_is_linux; then
    alias cwd='pwd | xclip'
    alias duh='du -h --max-depth 1 | sort -h'
    alias open='xdg-open'
elif lk_is_macos; then
    alias duh='du -h -d 1 | sort -h'
fi

shopt -s checkwinsize

shopt -s histappend
HISTCONTROL=ignorespace
HISTIGNORE=
HISTSIZE=
HISTFILESIZE=
HISTTIMEFORMAT="%b %_d %Y %H:%M:%S %z "

[ ! -f "/usr/share/bash-completion/bash_completion" ] ||
    . "/usr/share/bash-completion/bash_completion"

eval "$(. "$LK_BASE/lib/bash/env.sh")"

[ "${LK_PROMPT:-1}" -ne "1" ] || lk_enable_prompt

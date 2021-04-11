#!/bin/bash

export -n BASH_XTRACEFD SHELLOPTS
[ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)

unset LK_PROMPT_DISPLAYED LK_BASE

SH=$(
    set -u
    die() { echo "${BASH_SOURCE:-$0}: $1" >&2 && false || exit; }
    _FILE=$BASH_SOURCE && [ -f "$_FILE" ] && [ ! -L "$_FILE" ] ||
        die "script must be sourced directly"
    [[ $_FILE == */* ]] || _FILE=./$_FILE
    _DIR=$(cd "${_FILE%/*}" && pwd -P) &&
        printf 'export LK_BASE=%q\n' "${_DIR%/lib/bash}" ||
        die "LK_BASE not found"
    LC_ALL=C
    vars() { printf '%s\n' "${!LK_@}"; }
    unset IFS
    VARS=$(vars)
    [ ! -r /etc/default/lk-platform ] ||
        . /etc/default/lk-platform
    [ ! -r ~/".${LK_PATH_PREFIX:-lk-}settings" ] ||
        . ~/".${LK_PATH_PREFIX:-lk-}settings"
    unset LK_BASE $VARS
    VARS=$(vars)
    [ -z "${VARS:+1}" ] ||
        declare -p $VARS
) && eval "$SH" && . "$LK_BASE/lib/bash/include/core.sh" || return

function lk_cat_log() {
    local FILES FILE
    lk_files_exist "$@" || lk_usage "\
Usage: ${FUNCNAME[0]} LOG_FILE[.gz] [LOG_FILE...]" || return
    lk_mapfile FILES <(lk_file_sort_by_date "$@")
    for FILE in "${FILES[@]}"; do
        case "$FILE" in
        *.gz)
            zcat "$FILE"
            ;;
        *)
            cat "$FILE"
            ;;
        esac
    done
}

function lk_bak_find() {
    local REGEX=".*(-[0-9]+\\.bak|\\.lk-bak-[0-9]{8}T[0-9]{6}Z)"
    lk_elevate gnu_find / -xdev -regextype posix-egrep \
        ! \( -type d -path /srv/backup/snapshot -prune \) \
        -regex "${_LK_DIFF_REGEX:-$REGEX}" \
        ${@+\( "$@" \)}
}

function lk_bak_diff() {
    local BACKUP FILE FILE2 \
        REGEX=".*(-[0-9]+\\.bak|\\.lk-bak-[0-9]{8}T[0-9]{6}Z)"
    lk_is_root || ! lk_can_sudo bash || {
        lk_elevate bash -c "$(
            function _bak_diff() {
                . "$1"
                shift
                lk_bak_diff "$@"
            }
            declare -f _bak_diff
            lk_quote_args \
                _LK_DIFF_REGEX=${_LK_DIFF_REGEX:-} \
                _bak_diff \
                "$LK_BASE/lib/bash/rc.sh" \
                "$@"
        )"
        return
    }
    while IFS= read -rd '' BACKUP; do
        [[ $BACKUP =~ ${_LK_DIFF_REGEX:-$REGEX} ]] || continue
        FILE=${BACKUP%${BASH_REMATCH[1]}}
        [ -e "$FILE" ] || {
            FILE2=${FILE##*/}
            FILE=${FILE2//"__"/\/}
            [ "$FILE" != "$FILE2" ] && [ -e "$FILE" ] || continue
        }
        lk_console_diff "$BACKUP" "$FILE" || true
    done < <(gnu_find / -xdev -regextype posix-egrep \
        ! \( -type d -path /srv/backup/snapshot -prune \) \
        -regex "${_LK_DIFF_REGEX:-$REGEX}" ${@+\( "$@" \)} -print0 | sort -z)
}

function lk_orig_find() {
    _LK_DIFF_REGEX=".*\\.orig" \
        lk_bak_find "$@"
}

function lk_orig_diff() {
    _LK_DIFF_REGEX=".*(\\.orig)" \
        lk_bak_diff "$@"
}

function lk_find_latest() {
    local i TYPE=f TYPE_ARGS=()
    [[ ! ${1:-} =~ ^[bcdflps]+$ ]] || { TYPE=$1 && shift; }
    for i in $(seq 0 $((${#TYPE} - 1))); do
        TYPE_ARGS+=(${TYPE_ARGS[@]+-o} -type "${TYPE:$i:1}")
    done
    [ ${#TYPE_ARGS[@]} -eq 2 ] || TYPE_ARGS=(\( "${TYPE_ARGS[@]}" \))
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
    [ -n "${1:-}" ] || lk_warn "no search term" || return
    gnu_find -L . -xdev -iname "*$1*" "${@:2}"
}

[ ! -d /srv/www ] || lk_include hosting
lk_include bash git linode misc provision wordpress

if lk_is_linux; then
    lk_include iptables linux
    ! lk_is_arch || lk_include arch
    ! lk_is_ubuntu || lk_include debian
elif lk_is_macos; then
    lk_include macos
    export BASH_SILENCE_DEPRECATION_WARNING=1
fi

LK_PATH_PREFIX=${LK_PATH_PREFIX-lk-}
SH=$(. "$LK_BASE/lib/bash/env.sh") &&
    eval "$SH"

[[ $- != *i* ]] || {

    shopt -s checkwinsize histappend
    HISTCONTROL=ignorespace
    HISTIGNORE=
    HISTSIZE=
    HISTFILESIZE=
    HISTTIMEFORMAT="%b %_d %Y %H:%M:%S %z "

    lk_is_false LK_COMPLETION || { SH=$(
        if [ -r /usr/share/bash-completion/bash_completion ]; then
            COMMAND=/usr/share/bash-completion/bash_completion
        elif [ -z "${HOMEBREW_PREFIX:-}" ]; then
            return
        else
            shopt -s nullglob
            VERSION=
            ! lk_bash_at_least 4 ||
                VERSION="@2"
            COMMAND=$(printf '%s\n' \
                "$HOMEBREW_PREFIX/Cellar/bash-completion$VERSION"/*/etc/profile.d/bash_completion.sh |
                sort -V | tail -n1)
            [ -n "$COMMAND" ] || return 0
            [ -n "$VERSION" ] || {
                COMMAND=${COMMAND/profile.d\/bash_completion.sh/bash_completion}
                printf '%s=%q ' \
                    BASH_COMPLETION "$COMMAND" \
                    BASH_COMPLETION_DIR "$COMMAND.d"
            }
        fi
        printf '. %q\n' "$COMMAND" "$LK_BASE/lib/bash/completion.sh"
    ) && eval "$SH"; }

    lk_is_false LK_PROMPT || {
        lk_include prompt
        lk_enable_prompt
    }

    ! lk_command_exists dircolors || { SH=$(
        COMMAND=(dircolors -b)
        [ ! -r ~/.dircolors ] || COMMAND+=(~/.dircolors)
        # OTHER_WRITABLE defaults to 34;42 (blue on green), which is almost
        # always unreadable; replace it with white on green
        OUTPUT=$("${COMMAND[@]}") &&
            echo "${OUTPUT//=34;42:/=37;42:}"
    ) && eval "$SH"; }

    alias clip=lk_clip
    alias unclip=lk_paste
    if ! lk_is_macos; then
        alias duh='du -h --max-depth 1 | sort -h'
        alias open='xdg-open'
    else
        alias duh='du -h -d 1 | sort -h'
    fi

}

unset SH

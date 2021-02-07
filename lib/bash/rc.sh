#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2030,SC2031,SC2207

export -n BASH_XTRACEFD SHELLOPTS
[ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)

unset LK_PROMPT_DISPLAYED LK_BASE

SH=$(
    BS=${BASH_SOURCE[0]}
    [ "${BS%/*}" != "$BS" ] || BS=./$BS
    if [ ! -L "$BS" ] &&
        LK_BASE="$(cd "${BS%/*}/../.." && pwd -P)" &&
        [ -d "$LK_BASE/lib/bash" ]; then
        printf 'LK_BASE=%q' "$LK_BASE"
    else
        echo "$BS: LK_BASE not set" >&2
    fi
) && eval "$SH"
[ -n "${LK_BASE:-}" ] || return
export LK_BASE

. "$LK_BASE/lib/bash/include/core.sh"

# see lib/bash/common.sh
SH=$(
    SETTINGS=(
        /etc/default/lk-platform
        ~/".{{LK_PATH_PREFIX}}settings"
    )
    ENV=$(lk_get_env -n | sed '/^LK_/!d' | sort)
    function lk_var() { comm -23 \
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
) && eval "$SH"

function clip() {
    if lk_command_exists clip; then
        unset -f clip
    else
        function clip() {
            lk_clip
        }
    fi
    clip "$@"
}

function lk_cat_log() {
    local IFS FILES FILE
    lk_files_exist "$@" || lk_usage "\
Usage: $(lk_myself -f) LOG_FILE[.gz] [LOG_FILE...]" || return
    IFS=$'\n'
    FILES=($(lk_sort_paths_by_date "$@"))
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
    local BACKUP FILE FILE2 DIFF_VER \
        REGEX=".*(-[0-9]+\\.bak|\\.lk-bak-[0-9]{8}T[0-9]{6}Z)"
    [ "$EUID" -eq 0 ] || ! lk_can_sudo bash || {
        sudo -H env \
            _LK_DIFF_REGEX="${_LK_DIFF_REGEX:-}" \
            bash -c "$(declare -f lk_bak_diff); lk_bak_diff \"\$@\"" "bash" "$@"
        return
    }
    DIFF_VER=$(lk_diff_version 2>/dev/null) &&
        lk_version_at_least "$DIFF_VER" 3.4 || unset DIFF_VER
    while IFS= read -rd '' BACKUP; do
        [[ $BACKUP =~ ${_LK_DIFF_REGEX:-$REGEX} ]] || continue
        FILE=${BACKUP%${BASH_REMATCH[1]}}
        [ -e "$FILE" ] || {
            FILE2=${FILE##*/}
            FILE=${FILE2//"__"/\/}
            [ "$FILE" != "$FILE2" ] && [ -e "$FILE" ] || continue
        }
        gnu_diff --unified ${DIFF_VER+--color=always} \
            --report-identical-files "$BACKUP" "$FILE" ||
            true
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
    [[ $- != *i* ]] || {
        alias duh='du -h --max-depth 1 | sort -h'
        alias open='xdg-open'
    }
elif lk_is_macos; then
    lk_include macos
    [[ $- != *i* ]] || {
        alias duh='du -h -d 1 | sort -h'
    }
    export BASH_SILENCE_DEPRECATION_WARNING=1
fi
alias cwd='pwd | lk_clip'

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

    lk_is_false LK_COMPLETION || { SH=$(for FILE in \
        /usr/share/bash-completion/bash_completion \
        ${HOMEBREW_PREFIX:+"$HOMEBREW_PREFIX/etc/profile.d/bash_completion.sh"}; do
        [ -r "$FILE" ] || continue
        printf '. %q\n' "$FILE" "$LK_BASE/lib/bash/completion.sh"
        return
    done) && eval "$SH"; }

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

}

unset SH

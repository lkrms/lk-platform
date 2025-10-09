#!/usr/bin/env bash

unset _LK_PROMPT_SEEN

SH=$(
    set -u
    lk_die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }
    _FILE=$BASH_SOURCE && [ -f "$_FILE" ] && [ ! -L "$_FILE" ] ||
        lk_die "script must be sourced directly"
    [[ $_FILE == */* ]] || _FILE=./$_FILE
    _DIR=$(cd "${_FILE%/*}" && pwd -P) &&
        printf 'export LK_BASE=%q\n' "${_DIR%/lib/bash}" ||
        lk_die "LK_BASE not found"
    # Discard settings with the same name as LK_* variables in the environment
    # and add any that remain to the global scope
    vars() { printf '%s\n' "${!LK_@}"; }
    _PATH_PREFIX=${LK_PATH_PREFIX-}
    unset IFS LK_PATH_PREFIX
    VARS=$(vars)
    [ ! -r /etc/default/lk-platform ] ||
        . /etc/default/lk-platform || exit
    [ ! -r "${_DIR%/lib/bash}/etc/lk-platform/lk-platform.conf" ] ||
        . "${_DIR%/lib/bash}/etc/lk-platform/lk-platform.conf" || exit
    XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-~/.config}
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${_PATH_PREFIX:-lk-}}
    [ ! -f ~/".${LK_PATH_PREFIX}settings" ] ||
        . ~/".${LK_PATH_PREFIX}settings" || exit
    [ ! -f "$XDG_CONFIG_HOME/lk-platform/lk-platform.conf" ] ||
        . "$XDG_CONFIG_HOME/lk-platform/lk-platform.conf" || exit
    unset LK_BASE $VARS
    VARS=$(vars)
    [ -z "${VARS:+1}" ] ||
        declare -p $VARS
) && eval "$SH" || return
SH=$(. "$LK_BASE/lib/bash/env.sh") && eval "$SH" || return
unset SH

. "$LK_BASE/lib/bash/include/core.sh" || return

function lk_cat_log() {
    local FILES FILE
    lk_files_exist "$@" || lk_usage "\
Usage: $FUNCNAME LOG_FILE[.gz] [LOG_FILE...]" || return
    lk_mapfile FILES <(lk_file_sort_modified "$@")
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
    local REGEX='.*(-[0-9]+\.bak|\.lk-bak-[0-9]{8}T[0-9]{6}Z)'
    lk_elevate gnu_find / -xdev -regextype posix-egrep \
        ! \( -type d -path /srv/backup/snapshot -prune \) \
        -regex "${_LK_DIFF_REGEX:-$REGEX}" \
        ${@+\( "$@" \)}
}

function lk_bak_diff() {
    local BACKUP FILE FILE2 \
        REGEX='.*(-[0-9]+\.bak|\.lk-bak-[0-9]{8}T[0-9]{6}Z)'
    lk_root || ! lk_can_sudo bash || {
        lk_elevate bash -c "$(
            function bak_diff() {
                . "$1"
                shift
                lk_bak_diff "$@"
            }
            declare -f bak_diff
            lk_quote_args \
                _LK_DIFF_REGEX=${_LK_DIFF_REGEX-} \
                bak_diff \
                "$LK_BASE/lib/bash/rc.sh" \
                "$@"
        )"
        return
    }
    while IFS= read -rd '' BACKUP; do
        [[ $BACKUP =~ ${_LK_DIFF_REGEX:-$REGEX} ]] || continue
        FILE=${BACKUP%"${BASH_REMATCH[1]}"}
        [ -e "$FILE" ] || {
            FILE2=${FILE##*/}
            FILE=${FILE2//"__"/\/}
            [ "$FILE" != "$FILE2" ] && [ -e "$FILE" ] || continue
        }
        lk_tty_diff "$BACKUP" "$FILE" || true
    done < <(gnu_find / -xdev -regextype posix-egrep \
        ! \( -type d -path /srv/backup/snapshot -prune \) \
        -regex "${_LK_DIFF_REGEX:-$REGEX}" ${@+\( "$@" \)} -print0 | sort -z)
}

function lk_orig_find() {
    _LK_DIFF_REGEX='.*\.orig' \
        lk_bak_find "$@"
}

function lk_orig_diff() {
    _LK_DIFF_REGEX='.*(\.orig)' \
        lk_bak_diff "$@"
}

# latest [-t=TYPE[,...]] [-L] [-g] [-- FIND_ARG...]
#
# Options:
#   -t=TYPE[,...]   Only match files of TYPE (default: f,l)
#   -L              Follow symbolic links
#   -g              Include .git directories
function latest() {
    local OPTIND OPTARG OPT LK_USAGE IFS TYPES=(f l) DEREF= NO_GIT=1
    LK_USAGE="Usage: $FUNCNAME [-t=TYPE[,...]] [-L] [-g] [-- FIND_ARG...]"
    while getopts ":t:Lg" OPT; do
        case "$OPT" in
        t)
            IFS=,
            TYPES=($OPTARG)
            unset IFS
            ;;
        L)
            DEREF=1
            ;;
        g)
            NO_GIT=
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    local TYPE i=0 ARGS=() FORMAT='%T@ :%t %12s %M %p'
    for TYPE in ${TYPES+"${TYPES[@]}"}; do
        [[ $TYPE =~ ^[bcdflps]$ ]] ||
            lk_warn "invalid file type: $TYPE" || return
        ! ((i++)) || ARGS+=(-o)
        ARGS+=(-type "$TYPE")
    done
    ((i < 2)) || ARGS=(\( "${ARGS[@]}" \))
    [ $# -eq 0 ] ||
        ARGS=(\( "$@" \) ${ARGS+"${ARGS[@]}"})
    [ -z "$NO_GIT" ] ||
        ARGS=(! \( -type d -name .git -prune \) ${ARGS+"${ARGS[@]}"})
    gnu_find ${DEREF:+-L} . -xdev -regextype posix-egrep \
        ${ARGS+"${ARGS[@]}"} \
        \( \( -type l -printf "$FORMAT -> %l\n" \) -o -printf "$FORMAT\n" \) |
        sort -nr | cut -d: -f2- | "${PAGER:-less}"
}

function latest_dir() {
    latest -td "$@"
}

function latest_all() {
    latest -g "$@"
}

function latest_all_dir() {
    latest -g -td "$@"
}

function find_all() {
    [ -n "${1-}" ] || lk_warn "no search term" || return
    gnu_find . -xdev -iname "*$1*" "${@:2}"
}

[ ! -d /srv/www ] || lk_require hosting
[ ! -d /srv/backup ] || lk_require backup
lk_require bash git linode misc provision wordpress

if lk_is_linux; then
    lk_require ebtables iptables linux
    ! lk_is_arch || lk_require arch
    ! lk_is_ubuntu || lk_require debian
elif lk_is_macos; then
    lk_require macos
    export BASH_SILENCE_DEPRECATION_WARNING=1
fi

if [[ $- != *i* ]]; then
    return
fi

shopt -s checkwinsize histappend
HISTCONTROL=ignorespace
HISTIGNORE=
HISTSIZE=
HISTFILESIZE=
HISTTIMEFORMAT="%b %_d %Y %H:%M:%S %z "

lk_false LK_COMPLETION || ! lk_bash_at_least 4 || { SH=$(
    SOURCE=()
    ! FILE=$(
        lk_first_file /usr/share/bash-completion/bash_completion \
            "${HOMEBREW_PREFIX-}/opt/bash-completion@2/etc/profile.d/bash_completion.sh"
    ) || SOURCE+=("$FILE" "$LK_BASE/lib/bash/completion.sh")
    ! lk_is_macos || ! FILE=$(
        XCODE=/Applications/Xcode.app/Contents/Developer
        TOOLS=/Library/Developer/CommandLineTools
        lk_first_file {"$XCODE","$TOOLS"}/usr/share/git-core/git-completion.bash
    ) || SOURCE+=("$FILE")
    ! FILE=$(
        lk_first_file /usr/share/fzf/completion.bash \
            "${HOMEBREW_PREFIX-}/opt/fzf/shell/completion.bash"
    ) || SOURCE+=("$FILE")
    [[ -z ${SOURCE+1} ]] || printf '. %q\n' "${SOURCE[@]}"
) && eval "$SH"; }

lk_false LK_PROMPT || {
    lk_require prompt
    lk_prompt_enable
    [[ $(type -t __git_ps1) == function ]] || { SH=$(
        ! FILE=$(
            lk_first_file /usr/share/git/git-prompt.sh \
                /usr/lib/git-core/git-sh-prompt \
                {/Applications/Xcode.app/Contents/Developer,/Library/Developer/CommandLineTools}/usr/share/git-core/git-prompt.sh
        ) || printf '. %q\n' "$FILE"
    ) && eval "$SH"; }
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

unset SH

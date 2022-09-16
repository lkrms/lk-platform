#!/bin/bash

# lk_file_is_empty_dir FILE
#
# Return true if FILE exists and is an empty directory.
function lk_file_is_empty_dir() {
    ! lk_sudo -f ls -A "$1" 2>/dev/null | grep . >/dev/null &&
        [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == 01 ]]
}

# lk_file_maybe_move OLD_PATH CURRENT_PATH
#
# If OLD_PATH exists and CURRENT_PATH doesn't, move OLD_PATH to CURRENT_PATH.
function lk_file_maybe_move() {
    lk_sudo -f test ! -e "$1" ||
        lk_sudo -f test -e "$2" || {
        lk_sudo mv -nv "$1" "$2" &&
            LK_FILE_NO_CHANGE=0
    }
}

# lk_file_list_duplicates [DIR]
#
# Print a list of files in DIR or the current directory that would be considered
# duplicates on a case-insensitive filesystem. Only useful on case-sensitive
# filesystems.
function lk_file_list_duplicates() {
    find "${1:-.}" -print0 | sort -zf | gnu_uniq -zDi | tr '\0' '\n'
}

# lk_expand_path [PATH...]
#
# Remove enclosing quotation marks (if any) and perform tilde and glob expansion
# on each PATH. Call after `shopt -s globstar` to expand `**` globs.
function lk_expand_path() { (
    shopt -s nullglob
    lk_awk_load AWK sh-sanitise-quoted-pathname || return
    SH="printf '%s\\n' $(_lk_stream_args 3 awk -f "$AWK" "$@" | tr '\n' ' ')" &&
        eval "$SH"
); }

# lk_file [-i REGEX] [-dpbr] [-m MODE] [-o USER] [-g GROUP] [-v] FILE
#
# Create or update FILE if its content or permissions differ from the input.
#
# Options:
#
#     -i REGEX    Ignore REGEX when comparing
#     -d          Print a diff between FILE and its replacement
#     -p          Prompt before replacing FILE (implies -d)
#     -b          Create a backup of FILE before replacing it
#     -r          Preserve the original FILE as FILE.orig
#     -m MODE     Specify the file mode
#     -o USER     Specify the owner
#     -g GROUP    Specify the group
#     -v          Be verbose
#
# If -p is set and the user opts out of replacing FILE, return false and
# increment LK_FILE_DECLINED.
function lk_file() {
    local OPTIND OPTARG OPT \
        DIFF=0 PROMPT=0 BACKUP=0 ORIG=0 MODE OWNER GROUP VERBOSE=0 \
        GREP_ARGS=() TEMP
    lk_counter_init LK_FILE_DECLINED
    while getopts ":i:dpbrm:o:g:v" OPT; do
        case "$OPT" in
        i)
            GREP_ARGS+=(-e "$OPTARG")
            ;;
        d)
            DIFF=1
            ;;
        p)
            PROMPT=1
            DIFF=1
            ;;
        b)
            BACKUP=1
            ;;
        r)
            ORIG=1
            ;;
        m)
            MODE=$OPTARG
            ;;
        o)
            OWNER=$(id -u "$OPTARG") || return
            ((OWNER == EUID)) || lk_will_elevate ||
                lk_err "not allowed: -o $OPTARG" || return
            OWNER=$OPTARG
            ;;
        g)
            GROUP=$OPTARG
            [[ $GROUP =~ [^0-9] ]] ||
                lk_err "invalid group: $GROUP" || return
            lk_will_elevate ||
                id -Gn | tr -s '[:blank:]' '\n' | grep -Fx "$GROUP" >/dev/null ||
                lk_err "not allowed: -g $GROUP"
            ;;
        v)
            VERBOSE=1
            ;;
        \? | :)
            lk_bad_args
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# == 1)) || lk_bad_args || return
    [[ ! -t 0 ]] || lk_err "no input" || return
    lk_mktemp_with TEMP cat &&
        lk_reopen_tty_in || return
    # If the file doesn't exist, use `install` to create it
    if [[ ! -e $1 ]] && ! { lk_will_sudo && sudo test -e "$1"; }; then
        ((!DIFF)) || lk_tty_diff_detail -L "" -L "$1" /dev/null "$TEMP"
        ((!PROMPT)) || lk_tty_yn "Install $1 as above?" Y || {
            ((++LK_FILE_DECLINED))
            return 1
        }
        lk_sudo_on_fail install -m "${MODE:-0644}" \
            ${OWNER:+-o="$OWNER"} ${GROUP:+-g="$GROUP"} \
            "$TEMP" "$1" || lk_err "error installing $1" || return
        return
    fi
    # Otherwise, update permissions if needed
    OWNER_MODE=$(lk_file_owner_mode)

}

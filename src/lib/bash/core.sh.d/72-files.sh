#!/usr/bin/env bash

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

# lk_file [-i <regex>] [-dpbsrvq] [-m <mode>] [-o <user>] [-g <group>] <file>
#
# Create or update a file if it differs from the given input or permissions.
#
# Options:
#
#     -i <regex>  Exclude lines that match a regular expression from comparison
#     -d          Print a diff before replacing the file
#     -p          Prompt to confirm changes (implies -d)
#     -b          Create a backup of the file before replacing it
#     -s          Create the backup in a secure store (implies -b)
#     -r          Preserve the original file as `<file>.orig`
#     -m <mode>   Specify a numeric mode for the file
#     -o <user>   Specify an owner for the file
#     -g <group>  Specify a group for the file
#     -v          Be verbose (repeat for more detail; overrides previous -q)
#     -q          Only report errors (overrides previous -v)
#
# If the file is created or updated, it is added to LK_FILE_CHANGED and the
# return value is 0.
#
# If -p is given and the user opts out of replacing the file, it is added to
# LK_FILE_UNCHANGED and the return value is 1.
#
# If an error occurs, the return value is 2.
#
# If -s is given, the file is copied to a user- or system-wide backup directory
# before it is replaced. See `lk_file_backup` for details.
#
# If -v or -q are given, the value of LK_VERBOSE is ignored.
#
# Entries in global arrays LK_FILE_CHANGED and LK_FILE_UNCHANGED are arranged
# from most to least recent. New entries are always added at index 0.
function lk_file() {
    local OPTIND OPTARG OPT \
        DIFF=0 PROMPT=0 BACKUP=0 STORE= ORIG=0 MODE OWNER GROUP VERBOSE= \
        SED_ARGS=() CHANGED=0 TEMP _MODE _OWNER _GROUP _CHOWN= CHOWN=
    while getopts ":i:dpbsrm:o:g:vq" OPT; do
        case "$OPT" in
        i)
            SED_ARGS+=(-e "/${OPTARG//\//\\\/}/d")
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
        s)
            STORE=1
            BACKUP=1
            ;;
        r)
            ORIG=1
            ;;
        m)
            [[ $OPTARG =~ ^[0-7]{3,4}$ ]] ||
                lk_err "invalid mode: $OPTARG" || return 2
            MODE=$(printf '%4s' "$OPTARG" | tr ' ' 0)
            ;;
        o)
            [[ $OPTARG =~ [^0-9] ]] ||
                lk_err "invalid user: $OPTARG" || return 2
            OWNER=$(id -u "$OPTARG") || return 2
            ((OWNER == EUID)) || lk_will_elevate ||
                lk_err "not allowed: -o $OPTARG" || return 2
            OWNER=$OPTARG
            ;;
        g)
            [[ $OPTARG =~ [^0-9] ]] ||
                lk_err "invalid group: $OPTARG" || return 2
            GROUP=$OPTARG
            lk_will_elevate ||
                id -Gn | tr -s '[:blank:]' '\n' | grep -Fx "$GROUP" >/dev/null ||
                lk_err "not allowed: -g $GROUP" || return 2
            ;;
        v)
            ((++VERBOSE))
            ;;
        q)
            VERBOSE=0
            ;;
        \? | :)
            lk_bad_args || return 2
            ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# == 1)) || lk_bad_args || return 2
    [[ ! -t 0 ]] || lk_err "no input" || return 2
    lk_mktemp_with TEMP cat || lk_err "error writing input to file" || return 2
    lk_readable_tty_open || PROMPT=0
    VERBOSE=${VERBOSE:-${LK_VERBOSE:-0}}

    # If the file doesn't exist, use `install` to create it
    if [[ ! -e $1 ]] && ! { lk_will_sudo && sudo test -e "$1"; }; then
        ((!DIFF)) || lk_tty_diff_detail -L "" -L "$1" /dev/null "$TEMP"
        ((!PROMPT)) || lk_tty_yn "Create $1 as above?" Y || {
            LK_FILE_UNCHANGED=("$1" ${LK_FILE_UNCHANGED+"${LK_FILE_UNCHANGED[@]}"})
            return 1
        }
        ((!VERBOSE)) || lk_tty_detail "Creating:" "$1"
        lk_sudo_on_fail install -m "${MODE:-0644}" \
            ${OWNER:+-o="$OWNER"} ${GROUP:+-g="$GROUP"} \
            "$TEMP" "$1" || lk_err "error creating $1" || return 2
        LK_FILE_CHANGED=("$1" ${LK_FILE_CHANGED+"${LK_FILE_CHANGED[@]}"})
        return
    fi

    # Otherwise, check if the file has been changed
    if [[ -n ${SED_ARGS+1} ]]; then
        diff -q \
            <(lk_sudo_on_fail sed -E "${SED_ARGS[@]}" "$1") \
            <(sed -E "${SED_ARGS[@]}" "$TEMP") \
            >/dev/null
    else
        diff -q <(lk_sudo_on_fail cat "$1") "$TEMP" >/dev/null
    fi || {
        ((!DIFF)) || lk_tty_diff_detail -L "a/${1#/}" -L "b/${1#/}" "$1" "$TEMP"
        ((!PROMPT)) || lk_tty_yn "Update $1 as above?" Y || {
            LK_FILE_UNCHANGED=("$1" ${LK_FILE_UNCHANGED+"${LK_FILE_UNCHANGED[@]}"})
            return 1
        }
        ((!VERBOSE)) || lk_tty_detail "Updating:" "$1"
        ((!ORIG)) || [[ -e "$1.orig" ]] || { lk_will_sudo && sudo test -e "$1.orig"; } || {
            lk_sudo_on_fail cp -aL "$1" "$1.orig" || return 2
            # FILE.orig will suffice as a backup
            BACKUP=0
        }
        ((!BACKUP)) || lk_file_backup ${STORE:+-m} "$1" || return 2
        lk_sudo_on_fail cp "$TEMP" "$1" ||
            lk_err "error replacing $1" || return 2
        CHANGED=1
    }

    # Finally, update permissions and ownership if needed
    if [[ -n ${MODE-} ]]; then
        _MODE=$(lk_file_mode "$1") || return 2
        [[ $MODE == "$_MODE" ]] || {
            ((VERBOSE < 2)) ||
                lk_tty_detail "Updating file mode ($_MODE -> $MODE):" "$1"
            lk_sudo_on_fail chmod "0$MODE" "$1" || return 2
            CHANGED=1
        }
    fi
    if [[ -n ${OWNER-} ]]; then
        _OWNER=$(lk_file_owner "$1") || return 2
        [[ $OWNER == "$_OWNER" ]] || {
            _CHOWN=$_OWNER
            CHOWN=$OWNER
        }
    fi
    if [[ -n ${GROUP-} ]]; then
        _GROUP=$(lk_file_group "$1") || return 2
        [[ $GROUP == "$_GROUP" ]] || {
            _CHOWN+=:$_GROUP
            CHOWN+=:$GROUP
        }
    fi
    [[ -z $CHOWN ]] || {
        ((VERBOSE < 2)) ||
            lk_tty_detail "Updating ownership ($_CHOWN -> $CHOWN):" "$1"
        lk_sudo_on_fail chown "$CHOWN" "$1" || return 2
        CHANGED=1
    }

    ((!CHANGED)) ||
        LK_FILE_CHANGED=("$1" ${LK_FILE_CHANGED+"${LK_FILE_CHANGED[@]}"})
}

# lk_file_complement [-s] <file> <file2>...
#
# Print lines in <file> that are not present in any of the subsequent files.
# Individual files are not sorted if -s is given. This option should only be
# used when files have already been sorted by `sort -u` in the current locale.
function lk_file_complement() {
    local sort=1
    [[ ${1-} != -s ]] || {
        sort=0
        shift
    }
    (($# > 1)) || lk_bad_args || return
    if ((sort)); then
        comm -23 <(sort -u "$1") <(shift && sort -u "$@")
    elif (($# > 2)); then
        comm -23 "$1" <(shift && sort -u "$@")
    else
        comm -23 "$1" "$2"
    fi
}

# lk_file_intersect [-s] <file> <file2>...
#
# Print lines in <file> that are present in at least one subsequent file.
# Individual files are not sorted if -s is given. This option should only be
# used when files have already been sorted by `sort -u` in the current locale.
function lk_file_intersect() {
    local sort=1
    [[ ${1-} != -s ]] || {
        sort=0
        shift
    }
    (($# > 1)) || lk_bad_args || return
    if ((sort)); then
        comm -12 <(sort -u "$1") <(shift && sort -u "$@")
    elif (($# > 2)); then
        comm -12 "$1" <(shift && sort -u "$@")
    else
        comm -12 "$1" "$2"
    fi
}

# lk_file_cp_new [<rsync_arg>...] <src>... <dest>
#
# Copy one or more files with a portable `rsync` command similar to the
# deprecated `cp -an`.
#
# To preserve hard links, ACLs and extended attributes as per `cp -a`, `rsync`
# options -H, -A and -X, respectively, may be given.
function lk_file_cp_new() {
    (($# > 1)) || lk_bad_args || return
    # cp option => rsync equivalent:
    # - --no-dereference => -l
    # - --recursive => -r
    # - --preserve=mode => -p
    # - --preserve=ownership => -go
    # - --preserve=timestamps => -t
    # - --preserve=links => -H
    # - --preserve=context,xattr => -AX
    # - --no-clobber => --ignore-existing
    rsync -rlptgo --ignore-existing --info=flist0,stats0 "$@"
}

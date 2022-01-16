#!/bin/bash

# lk_script_running
#
# Return true if a script file is running. If reading commands from a named pipe
# (e.g. `bash <(list)`), the standard input (`bash -i` or `list | bash`), or the
# command line (`bash -c "string"`), return false.
function lk_script_running() {
    [ "${BASH_SOURCE+${BASH_SOURCE[*]: -1}}" = "$0" ] && [ -f "$0" ]
}

# lk_verbose [LEVEL]
#
# Return true if LK_VERBOSE [default: 0] is at least LEVEL [default: 1].
function lk_verbose() {
    [ "${LK_VERBOSE:-0}" -ge "${1-1}" ]
}

# lk_debug
#
# Return true if LK_DEBUG is set.
function lk_debug() {
    [ "${LK_DEBUG-}" = Y ]
}

# lk_root
#
# Return true if running as the root user.
function lk_root() {
    [ "$EUID" -eq 0 ]
}

# lk_dry_run
#
# Return true if LK_DRY_RUN is set.
function lk_dry_run() {
    [ "${LK_DRY_RUN:-0}" -eq 1 ]

}

# lk_true VAR
#
# Return true if VAR or ${!VAR} is 'Y', 'yes', '1', 'true', or 'on' (not
# case-sensitive).
function lk_true() {
    local REGEX='^([yY]([eE][sS])?|1|[tT][rR][uU][eE]|[oO][nN])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

# lk_false VAR
#
# Return true if VAR or ${!VAR} is 'N', 'no', '0', 'false', or 'off' (not
# case-sensitive).
function lk_false() {
    local REGEX='^([nN][oO]?|0|[fF][aA][lL][sS][eE]|[oO][fF][fF])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

# lk_test TEST [VALUE...]
#
# Return true if every VALUE passes TEST, otherwise return false. If there are
# no VALUE arguments, return false.
function lk_test() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [ -n "${COMMAND+1}" ] && [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        "${COMMAND[@]}" "$1" || break
        shift
    done
    [ $# -eq 0 ]
}

# lk_test_any TEST [VALUE...]
#
# Return true if at least one VALUE passes TEST, otherwise return false.
function lk_test_any() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [ -n "${COMMAND+1}" ] && [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        ! "${COMMAND[@]}" "$1" || break
        shift
    done
    [ $# -gt 0 ]
}

function lk_paths_exist() { lk_test "lk_sudo test -e" "$@"; }

function lk_files_exist() { lk_test "lk_sudo test -f" "$@"; }

function lk_dirs_exist() { lk_test "lk_sudo test -d" "$@"; }

function lk_files_not_empty() { lk_test "lk_sudo test -s" "$@"; }

#### Reviewed: 2021-12-29

#!/usr/bin/env bash

# lk_script_running
#
# Return true if a script file is running. If reading commands from a named pipe
# (e.g. `bash <(list)`), the standard input (`bash -i` or `list | bash`), or the
# command line (`bash -c "string"`), return false.
function lk_script_running() {
    [[ ${BASH_SOURCE+${BASH_SOURCE[*]: -1}} == "$0" ]] && [[ -f $0 ]]
}

# lk_verbose [LEVEL]
#
# Return true if LK_VERBOSE (default: 0) is at least LEVEL (default: 1).
function lk_verbose() {
    ((${LK_VERBOSE:-0} >= ${1-1}))
}

# lk_no_input
#
# Return true if the user should not be prompted for input.
#
# Returns false if:
# - LK_FORCE_INPUT is set, or
# - /dev/stdin is a terminal and LK_NO_INPUT is not set
function lk_no_input() {
    [[ ${LK_FORCE_INPUT-} != Y ]] || {
        { [[ -t 0 ]] ||
            lk_err "/dev/stdin is not a terminal"; } && false || return
    }
    [[ ! -t 0 ]] || [[ ${LK_NO_INPUT-} == Y ]]
}

# lk_debug
#
# Return true if LK_DEBUG is set.
function lk_debug() {
    [[ ${LK_DEBUG-} == Y ]]
}

# lk_root
#
# Return true if running as the root user.
function lk_root() {
    [[ $EUID -eq 0 ]]
}

# lk_dry_run
#
# Return true if LK_DRY_RUN is set.
function lk_dry_run() {
    [[ ${LK_DRY_RUN-} == Y ]]
}

# lk_true VAR
#
# Return true if VAR or ${!VAR} is 'Y', 'yes', '1', 'true', or 'on' (not
# case-sensitive).
function lk_true() {
    [[ $1 =~ ^([yY]([eE][sS])?|1|[tT][rR][uU][eE]|[oO][nN])$ ]] ||
        [[ ${1:+${!1-}} =~ ^([yY]([eE][sS])?|1|[tT][rR][uU][eE]|[oO][nN])$ ]]
}

# lk_false VAR
#
# Return true if VAR or ${!VAR} is 'N', 'no', '0', 'false', or 'off' (not
# case-sensitive).
function lk_false() {
    [[ $1 =~ ^([nN][oO]?|0|[fF][aA][lL][sS][eE]|[oO][fF][fF])$ ]] ||
        [[ ${1:+${!1-}} =~ ^([nN][oO]?|0|[fF][aA][lL][sS][eE]|[oO][fF][fF])$ ]]
}

# lk_test TEST [VALUE...]
#
# Return true if every VALUE passes TEST, otherwise return false. If there are
# no VALUE arguments, return false.
function lk_test() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [[ -n ${COMMAND+1} ]] && (($#)) || return
    while (($#)); do
        "${COMMAND[@]}" "$1" || break
        shift
    done
    ((!$#))
}

# lk_test_any TEST [VALUE...]
#
# Return true if at least one VALUE passes TEST, otherwise return false.
function lk_test_any() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [[ -n ${COMMAND+1} ]] && (($#)) || return
    while (($#)); do
        ! "${COMMAND[@]}" "$1" || break
        shift
    done
    (($#))
}

# lk_paths_exist PATH [PATH...]
#
# Return true if every PATH exists.
function lk_paths_exist() { lk_test "lk_sudo test -e" "$@"; }

# lk_files_exist FILE [FILE...]
#
# Return true if every FILE exists.
function lk_files_exist() { lk_test "lk_sudo test -f" "$@"; }

# lk_dirs_exist DIR [DIR...]
#
# Return true if every DIR exists.
function lk_dirs_exist() { lk_test "lk_sudo test -d" "$@"; }

# lk_files_not_empty FILE [FILE...]
#
# Return true if every FILE exists and has a size greater than zero.
function lk_files_not_empty() { lk_test "lk_sudo test -s" "$@"; }

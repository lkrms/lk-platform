#!/usr/bin/env bash

# lk_is_script
#
# Check if a script file is running.
#
# Fails if Bash is reading commands from:
# - the standard input (e.g. `bash -i` or `write_list | bash`)
# - a string (`bash -c "list"`), or
# - a named pipe (`bash <(write_list)`)
function lk_is_script() {
    [[ ${BASH_SOURCE+${BASH_SOURCE[*]: -1}} == "$0" ]] && [[ -f $0 ]]
}

# lk_is_v [<minimum_verbosity>]
#
# Check if the level of output verbosity applied via LK_VERBOSE (0 if empty or
# unset) is greater than or equal to the given value (1 if not given).
function lk_is_v() {
    ((${LK_VERBOSE:-0} >= ${1-1}))
}

# lk_input_is_off
#
# Check if user input prompts should be skipped.
#
# Fails if:
# - the standard input is connected to a terminal and LK_NO_INPUT is not Y, or
# - LK_FORCE_INPUT=Y
function lk_input_is_off() {
    if [[ ${LK_FORCE_INPUT-} == Y ]]; then
        [[ -t 0 ]] || lk_err "LK_FORCE_INPUT=Y but /dev/stdin is not a terminal" || return
        return 1
    fi
    [[ ${LK_NO_INPUT-} == Y ]] || [[ ! -t 0 ]]
}

# lk_debug_is_on
#
# Check if debugging is enabled via LK_DEBUG=Y.
function lk_debug_is_on() {
    [[ ${LK_DEBUG-} == Y ]]
}

# lk_user_is_root
#
# Check if running as root.
function lk_user_is_root() {
    ((!EUID))
}

# lk_is_dryrun
#
# Check if running in dry-run mode via LK_DRYRUN=Y (preferred) or LK_DRY_RUN=Y
# (deprecated).
function lk_is_dryrun() {
    [[ ${LK_DRYRUN-} == Y ]] || [[ ${LK_DRY_RUN-} == Y ]]
}

# lk_is_true <value>
#
# Check if a value, or the variable it references, is 'Y', 'yes', '1', 'true',
# or 'on'. Not case-sensitive.
function lk_is_true() {
    (($#)) || lk_bad_args || return
    [[ $1 == @([yY]?([eE][sS])|1|[tT][rR][uU][eE]|[oO][nN]) ]] ||
        [[ ${!1-} == @([yY]?([eE][sS])|1|[tT][rR][uU][eE]|[oO][nN]) ]] 2>/dev/null
}

# lk_is_false <value>
#
# Check if a value, or the variable it references, is 'N', 'no', '0', 'false',
# or 'off'. Not case-sensitive.
function lk_is_false() {
    (($#)) || lk_bad_args || return
    [[ $1 == @([nN]?([oO])|0|[fF][aA][lL][sS][eE]|[oO][fF][fF]) ]] ||
        [[ ${!1-} == @([nN]?([oO])|0|[fF][aA][lL][sS][eE]|[oO][fF][fF]) ]] 2>/dev/null
}

# lk_test_all "<command> [<arg>...]" <value>...
#
# Check if all of the given values pass an IFS-delimited test command.
function lk_test_all() {
    (($# > 1)) || return
    local cmd
    read -ra cmd <<<"$1"
    shift
    while (($#)); do
        "${cmd[@]}" "$1" || break
        shift
    done
    ((!$#))
}

# lk_test_any "<command> [<arg>...]" <value>...
#
# Check if any of the given values pass an IFS-delimited test command.
function lk_test_any() {
    (($# > 1)) || return
    local cmd
    read -ra cmd <<<"$1"
    shift
    while (($#)); do
        ! "${cmd[@]}" "$1" || break
        shift
    done
    (($#))
}

# lk_test_all_e <file>...
#
# Check if every given file exists.
function lk_test_all_e() {
    lk_test_all "lk_sudo_on_fail test -e" "$@"
}

# lk_test_all_f <file>...
#
# Check if every given file exists and is a regular file.
function lk_test_all_f() {
    lk_test_all "lk_sudo_on_fail test -f" "$@"
}

# lk_test_all_d <file>...
#
# Check if every given file exists and is a directory.
function lk_test_all_d() {
    lk_test_all "lk_sudo_on_fail test -d" "$@"
}

# lk_test_all_s <file>...
#
# Check if every given file exists and has a size greater than zero.
function lk_test_all_s() {
    lk_test_all "lk_sudo_on_fail test -s" "$@"
}

#### Reviewed: 2025-12-03

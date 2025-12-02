#!/usr/bin/env bash

# lk_pass [-<status>] [--] [<command> [<arg>...]]
#
# Run a command and return the previous command's exit status, or <status> if
# given.
function lk_pass() {
    local status=$?
    if [[ ${1-} == -+([0-9]) ]]; then
        status=$((${1:1}))
        shift
    fi
    [[ ${1-} != -- ]] || shift
    "$@" || true
    return $status
}

# lk_err <message>
#
# Write "<caller>: <message>" to STDERR and return the previous command's exit
# status, or 1 if the previous command did not fail.
function lk_err() {
    local status=$?
    ((status)) || status=1
    printf '%s: %s\n' "$(_LK_STACK_DEPTH=0 lk_caller)" "${1-}" >&2
    return $status
}

# lk_bad_args
#
# Write "<caller>: invalid arguments" to STDERR and return the previous
# command's exit status, or 1 if the previous command did not fail.
function lk_bad_args() {
    local status=$?
    ((status)) || status=1
    printf '%s: invalid arguments\n' "$(_LK_STACK_DEPTH=0 lk_caller)" >&2
    return $status
}

# lk_script [<stack_depth>]
#
# Print the name of the script or function that's currently running.
function lk_script() {
    local depth=$((${_LK_STACK_DEPTH-0} + ${1-0})) name
    lk_script_running || {
        name=${FUNCNAME[depth + 1]+${FUNCNAME[*]: -1}}
        [[ $name != @(source|main) ]] || name=
    }
    printf '%s\n' "${name:-${0##*/}}"
}

# lk_caller [<stack_depth>]
#
# Print the name of the caller's caller.
function lk_caller() {
    local depth=$((${_LK_STACK_DEPTH-0} + ${1-0})) name
    name=${FUNCNAME[2 + depth]-}
    [[ $name != @(source|main) ]] || name=
    printf '%s\n' "${name:-${0##*/}}"
}

# lk_runnable ["<command> [<arg>...]"...]
#
# Print the first IFS-delimited command line that corresponds to an executable
# disk file, or fail if no <command> is found on the filesystem or in PATH.
function lk_runnable() {
    local cmd
    while (($#)); do
        read -ra cmd <<<"$1"
        ! type -P "${cmd[0]}" >/dev/null || break
        shift
    done
    (($#)) && printf '%s\n' "$1"
}

# lk_readable [<file>...]
#
# Print the first readable file, or fail if no <file> is readable by the current
# user.
function lk_readable() {
    while (($#)); do
        [[ ! -r $1 ]] || break
        shift
    done
    (($#)) && printf '%s\n' "$1"
}

# lk_writable_tty
#
# Print the first writable device of `/dev/tty` and `/dev/console`, or fail if
# neither is a character device that can be opened for writing.
function lk_writable_tty() {
    set -- /dev/tty /dev/console
    while (($#)); do
        [[ ! -c $1 ]] || ! : >"$1" || break
        shift
    done 2>/dev/null
    (($#)) && printf '%s\n' "$1"
}

# lk_readable_tty_open
#
# Reopen `/dev/tty` as STDIN, or fail if `/dev/tty` is not a readable character
# device.
function lk_readable_tty_open() {
    [[ -c /dev/tty ]] && [[ -r /dev/tty ]] &&
        { exec </dev/tty; } 2>/dev/null
}

# lk_plural [-v] (<count>|<array>) <single> [<plural>]
#
# Print the singular form of a noun if <count> or the length of an array is 1,
# otherwise print the noun's plural form (default: "<single>s"). If -v is given,
# insert "<count> " before the noun.
function lk_plural() {
    local _count _noun
    [[ ${1-} == -v ]] || set -- "" "$@"
    (($# > 2)) || lk_bad_args || return
    if [[ $2 == ?(+|-)+([0-9]) ]]; then
        _count=$2
    elif declare -pa "$2" &>/dev/null; then
        eval "_count=\${#$2[@]}"
    else
        lk_bad_args || return
    fi
    if ((_count == 1)); then
        _noun=$3
    else
        _noun=${4-${3}s}
    fi
    printf '%s%s\n' "${1:+$_count }" "$_noun"
}

# lk_assign <var>
#
# Read the contents of STDIN until EOF or NUL and assign them to a variable.
#
# Example:
#
#     lk_assign SQL <<"SQL"
#     SELECT id, name FROM table;
#     SQL
function lk_assign() {
    unset -v "${1-}" || lk_bad_args || return
    IFS= read -rd '' "$1" || true
}

# lk_grep <grep_arg>...
#
# Run `grep` and return zero whether lines are selected or not, failing only if
# there is an error.
function lk_grep() {
    local status
    grep "$@" || {
        status=$?
        ((status == 1)) || return $status
    }
}

#### Reviewed: 2025-10-28

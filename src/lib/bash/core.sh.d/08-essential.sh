#!/bin/bash

# lk_pass [-STATUS] COMMAND [ARG...]
#
# Run COMMAND without changing the previous command's exit status, or run
# COMMAND and return STATUS.
function lk_pass() {
    local STATUS=$?
    [[ $1 != -* ]] || { STATUS=${1:1} && shift; }
    "$@" || true
    return "$STATUS"
}

# lk_err MESSAGE
function lk_err() {
    lk_pass echo "${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-${0##*/}}: $1" >&2
}

# lk_bad_args [VALUE_NAME [VALUE]]
function lk_bad_args() {
    lk_pass printf '%s: invalid %s%s\n' \
        "${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-${0##*/}}" \
        "${1-arguments}" "${2+: $2}" >&2
}

# lk_script_name [STACK_DEPTH]
function lk_script_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    lk_script_running ||
        NAME=${FUNCNAME[1 + DEPTH]+"${FUNCNAME[*]: -1}"}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_caller_name [STACK_DEPTH]
function lk_caller_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    NAME=${FUNCNAME[2 + DEPTH]-}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_first_command ["COMMAND [ARG...]"...]
#
# Print the first command line where COMMAND is in PATH or return false if no
# COMMAND is found.
function lk_first_command() {
    local IFS=$' \t\n' CMD
    while (($#)); do
        CMD=($1)
        ! type -P "$CMD" >/dev/null || break
        shift
    done
    (($#)) && echo "$1"
}

# lk_first_file [FILE...]
#
# Print the first FILE that exists or return false if no FILE is found.
function lk_first_file() {
    while (($#)); do
        [[ ! -e $1 ]] || break
        shift
    done
    (($#)) && echo "$1"
}

# lk_first_writable_char [PATH...]
#
# Print the first PATH that is a writable character special file, or return
# false if no such PATH is found.
function lk_first_writable_char() {
    while (($#)); do
        { [[ ! -c $1 ]] || ! : >"$1"; } 2>/dev/null || break
        shift
    done
    (($#)) && echo "$1"
}

# lk_get_tty
#
# Print "/dev/tty" if Bash has a controlling terminal, otherwise print
# "/dev/console" if it is open for writing, or return false.
function lk_get_tty() {
    lk_first_writable_char /dev/tty /dev/console
}

# lk_reopen_tty_in
#
# Reopen /dev/stdin from /dev/tty if possible.
function lk_reopen_tty_in() {
    [[ ! -c /dev/tty ]] || [[ ! -r /dev/tty ]] || exec </dev/tty
}

# lk_plural [-v] <VALUE|ARRAY> SINGLE [PLURAL]
#
# Print SINGLE if VALUE or the length of ARRAY is 1, otherwise print PLURAL (or
# "${SINGLE}s" if PLURAL is omitted). If -v is set, include VALUE in the output.
function lk_plural() {
    local _VALUE _COUNT
    [[ $1 != -v ]] || { _VALUE=1 && shift; }
    [[ $1 =~ ^-?[0-9]+$ ]] && _COUNT=$1 ||
        { declare -p "$1" &>/dev/null && eval "_COUNT=\${#$1[@]}"; } ||
        lk_bad_args || return
    _VALUE="${_VALUE:+$_COUNT }"
    ((_COUNT == 1)) && echo "$_VALUE$2" || echo "$_VALUE${3-$2s}"
}

# lk_assign VAR
#
# Read standard input until EOF or NUL and assign it to VAR.
#
# Example:
#
#     lk_assign SQL <<"SQL"
#     SELECT id, name FROM table;
#     SQL
function lk_assign() {
    IFS= read -rd '' "$1" || true
}

# lk_safe_grep GREP_ARG...
#
# Run grep without returning an error if no lines were selected.
function lk_safe_grep() {
    grep "$@" || [[ $? -eq 1 ]] || return 2
}

# lk_counter_init [VAR...]
#
# Set each VAR in the caller's scope to whichever integer is greater:
# - The current value of VAR
# - 0 (zero)
function lk_counter_init() {
    while (($#)); do
        if [[ -n ${!1-} ]]; then
            eval "$1=\$(($1 < 0 ? 0 : $1))"
        else
            unset -v "$1" || lk_bad_args || return
            eval "$1=0"
        fi
        shift
    done
}

#### Reviewed: 2022-08-12

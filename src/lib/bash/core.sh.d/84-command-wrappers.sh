#!/usr/bin/env bash

# lk_maybe [-p] COMMAND [ARG...]
#
# Run COMMAND unless LK_DRY_RUN is set. If -p is set, print COMMAND if not
# running it.
function lk_maybe() {
    local PRINT
    [ "${1-}" != -p ] || { PRINT=1 && shift; }
    if lk_dry_run; then
        [ -z "${PRINT-}" ] && ! lk_verbose ||
            lk_tty_log \
                "${LK_YELLOW}[DRY RUN]${LK_RESET} Not running:" \
                "$(lk_quote_args "$@")"
    else
        "$@"
    fi
}

# lk_report_error [-q] COMMAND [ARG...]
#
# Run COMMAND and print an error message if it exits non-zero. If -q is set,
# discard output to stderr unless COMMAND fails.
function lk_report_error() {
    local QUIET STDERR
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    if [ -n "${QUIET-}" ]; then
        lk_mktemp_with STDERR || return
        "$@" 2>"$STDERR"
    else
        "$@"
    fi || {
        local STATUS=$? IFS=' '
        [ ! -s "${STDERR-}" ] || cat "$STDERR" >&2
        lk_tty_error "Exit status $STATUS:" "$*"
        return $STATUS
    }
}

# lk_faketty [exec] COMMAND [ARG...]
#
# Run COMMAND in a pseudo-terminal to satisfy tty checks even if output is being
# redirected.
function lk_faketty() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    if ! lk_is_macos; then
        SHELL=$BASH lk_sudo script -qfec "$(lk_quote_args "$@")" /dev/null
    else
        lk_sudo script -qt 0 /dev/null "$@"
    fi
}

# lk_keep_trying [-MAX_ATTEMPTS] COMMAND [ARG...]
#
# Execute COMMAND until its exit status is zero or MAX_ATTEMPTS have been made
# (default: 10). The delay between each attempt starts at 1 second and follows
# the Fibonnaci sequence (2 sec, 3 sec, 5 sec, 8 sec, 13 sec, etc.).
function lk_keep_trying() {
    local i=0 MAX_ATTEMPTS=10 WAIT=1 PREV=1 NEXT _IFS=${IFS-$' \t\n'}
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { MAX_ATTEMPTS=${1:1} && shift; }
    while :; do
        "$@" && return 0 || {
            local STATUS=$? IFS=' '
            ((++i < MAX_ATTEMPTS)) || break
            lk_tty_log "Failed (attempt $i of $MAX_ATTEMPTS):" "$*"
            lk_tty_detail "Trying again in $(lk_plural -v $WAIT second)"
            sleep "$WAIT"
            ((NEXT = WAIT + PREV, PREV = WAIT, WAIT = NEXT))
            lk_tty_print
            IFS=$_IFS
        }
    done
    return $STATUS
}

# lk_require_output [-q] COMMAND [ARG...]
#
# Return true if COMMAND succeeds with output other than newlines. If -q is set,
# suppress output.
#
# Return values:
# 1. if command fails with output
# 2. if command succeeds with no output
# 3. if command fails with no output
function lk_require_output() { (
    QUIET=0
    [[ ${1-} != -q ]] || { QUIET=1 && shift; }
    if ((!QUIET)); then
        "$@" | grep --color=never .
    else
        "$@" | grep . >/dev/null
    fi ||
        case "${PIPESTATUS[0]},${PIPESTATUS[1]}" in
        *,0) return 1 ;;
        0,*) return 2 ;;
        *) return 3 ;;
        esac
) }

# lk_env_clean COMMAND [ARG...]
#
# Remove _LK_* variables from the environment of COMMAND.
function lk_env_clean() {
    local _UNSET=("${!_LK_@}")
    if [ -n "${_UNSET+1}" ]; then
        env "${_UNSET[@]/#/--unset=}" "$@"
    else
        "$@"
    fi
}

# lk_v [-r] LEVEL COMMAND [ARG...]
#
# If LK_VERBOSE is at least LEVEL, run COMMAND and return its exit status.
# Otherwise:
# - if -r is set, return the exit status of the previous command
# - return true
#
# The exit status of the previous command is propagated to COMMAND.
function lk_v() {
    local STATUS=$? RETURN=0 _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [[ $1 != -r ]] || { RETURN=$STATUS && shift; }
    lk_verbose "$1" || return "$RETURN"
    shift
    if ((!STATUS)); then
        "$@"
    else
        (exit "$STATUS") || "$@"
    fi
}

# lk_stack COMMAND [ARG...]
#
# Run COMMAND with _LK_STACK_DEPTH incremented.
#
# The exit status of the previous command is propagated to COMMAND.
function lk_stack() {
    local STATUS=$? _LK_STACK_DEPTH=$((2 + ${_LK_STACK_DEPTH:-0}))
    if ((!STATUS)); then
        "$@"
    else
        (exit "$STATUS") || "$@"
    fi
}

# lk_output_diff [-i] <command1> [<arg1>...] -- <command2> [<arg2>...] [-- <arg>...]
#
# Run two commands, optionally passing the given arguments to both, and compare
# their output.
#
# If -i is given, occurrences of "{}" are replaced with <arg> in both commands,
# and there must be no additional arguments. Otherwise, <arg> and any subsequent
# arguments are added to the end of both commands.
function lk_output_diff() {
    local _arg _cmd1=() _cmd2=() _replace=0 _temp1 _temp2
    [[ ${1-} != -i ]] || {
        _replace=1
        shift
    }
    while (($#)); do
        _arg=$1
        shift
        [[ $_arg != -- ]] || break
        _cmd1[${#_cmd1[@]}]=$_arg
    done
    while (($#)); do
        _arg=$1
        shift
        [[ $_arg != -- ]] || break
        _cmd2[${#_cmd2[@]}]=$_arg
    done
    if ((_replace)); then
        (($# == 1)) && [[ ${_cmd1+1}${_cmd2+1} == 11 ]] || lk_bad_args || return
        _cmd1=("${_cmd1[@]//"{}"/$1}")
        _cmd2=("${_cmd2[@]//"{}"/$1}")
    elif (($#)); then
        _cmd1+=("$@")
        _cmd2+=("$@")
    else
        [[ ${_cmd1+1}${_cmd2+1} == 11 ]] || lk_bad_args || return
    fi
    lk_mktemp_with _temp1 "${_cmd1[@]}" &&
        lk_mktemp_with _temp2 "${_cmd2[@]}" || return
    local IFS=$' \t\n'
    lk_tty_diff -L "\`${_cmd1[*]}\`" -L "\`${_cmd2[*]}\`" "$_temp1" "$_temp2"
}

#### Reviewed: 2021-08-28

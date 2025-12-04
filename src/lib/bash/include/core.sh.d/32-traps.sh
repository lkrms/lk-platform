#!/usr/bin/env bash

# - lk_trap_add [-f] SIGNAL COMMAND [ARG...]
# - lk_trap_add -q [-f] SIGNAL QUOTED_COMMAND
#
# Create or extend a list of commands to run when a signal is received.
#
# - Identical commands are only called once per signal and subshell.
# - The same exit status is propagated via `$?` to each command that receives
#   the same signal.
# - If -f is set, the command is added or moved to the start of the list.
function lk_trap_add() {
    local first=0 i quote=1 trap traps=()
    [[ ${1-} != -q ]] || { quote=0 && shift; }
    [[ ${1-} != -f ]] || { first=1 && shift; }
    (($# > 1)) || lk_bad_args || return
    # Replace arguments with: SIGNAL QUOTED_COMMAND
    ((!quote)) ||
        set -- "$1" "$(shift && lk_quote_args "$@")"
    if ((first)); then
        traps[0]=$2
        _LK_TRAPS=("$BASH_SUBSHELL" "$1" "$2" ${_LK_TRAPS+"${_LK_TRAPS[@]}"})
    else
        _LK_TRAPS=(${_LK_TRAPS+"${_LK_TRAPS[@]}"})
    fi
    # Collect other traps from this subshell for this signal
    i=$((first ? 3 : 0))
    for (( ; i < ${#_LK_TRAPS[@]}; i += 3)); do
        ((_LK_TRAPS[i] == BASH_SUBSHELL)) &&
            [[ ${_LK_TRAPS[i + 1]} == "$1" ]] || continue
        trap=${_LK_TRAPS[i + 2]}
        # Skip this trap if it is already at the start of the list
        ((!first)) || [[ $trap != "$2" ]] || continue
        traps[${#traps[@]}]=$trap
        # Remove QUOTED_COMMAND argument if it is already in the list
        ((first)) || [[ $trap != "${2-}" ]] || set -- "$1"
    done
    ((first)) || (($# == 1)) || {
        traps[${#traps[@]}]=$2
        _LK_TRAPS+=("$BASH_SUBSHELL" "$1" "$2")
    }
    # Propagate the last exit status to each trap
    trap -- "declare _LK_TRAP_IN=\$? _LK_TRAP_OUT=0;$(
        for trap in "${traps[@]}"; do
            printf 'if ((!_LK_TRAP_IN));then { %s;};else (exit $_LK_TRAP_IN)||{ %s;};fi||_LK_TRAP_OUT=$?;' "$trap" "$trap"
        done
    )(exit \$_LK_TRAP_OUT)" "$1"
}

# _lk_on_exit_run_with_array QUOTED_COMMAND ARRAY [ARG...]
function _lk_on_exit_run_with_array() {
    local array=$2 command=$1 func
    shift 2
    array+=_$BASH_SUBSHELL
    func=${array}_trap
    [[ $(type -t "$func") == function ]] || {
        eval "function $func() {
    [[ -z \${${array}+1} ]] ||
        lk_sudo_on_fail $command \"\${${array}[@]}\" 2>/dev/null || true
}" && lk_trap_add EXIT "$func"
    } || return
    [[ -n ${!array+1} ]] || eval "$array=()"
    ((!$#)) || eval "$array+=(\"\$@\")"
}

# _lk_on_exit_run_with_array_undo ARRAY [ARG...]
function _lk_on_exit_run_with_array_undo() {
    local array=$1
    shift
    array+=_$BASH_SUBSHELL
    [[ -n ${!array+1} ]] || return 0
    while (($#)); do
        lk_arr_remove "$array" "$1" || return
        shift
    done
}

# lk_on_exit_delete FILE...
#
# Delete filesystem entries if they still exist when the shell exits.
function lk_on_exit_delete() {
    _lk_on_exit_run_with_array "rm -Rf --" _LK_DELETE "$@"
}

# lk_on_exit_undo_delete FILE...
#
# Remove entries from the list of files to delete when the shell exits.
function lk_on_exit_undo_delete() {
    _lk_on_exit_run_with_array_undo _LK_DELETE "$@"
}

# lk_on_exit_kill PID...
#
# Kill processes if they are still running when the shell exits.
function lk_on_exit_kill() {
    _lk_on_exit_run_with_array kill _LK_KILL "$@"
}

#### Global variables:
#### - _LK_DELETE_<subshell>: list of paths to delete when the shell exits
#### - _LK_KILL_<subshell>: list of process IDs to kill when the shell exits
#### - _LK_TRAPS: list with 3 values per entry: <subshell> <signal> <command>

#### Reviewed: 2025-05-27

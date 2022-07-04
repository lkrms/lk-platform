#!/bin/bash

# lk_trap_add SIGNAL COMMAND [ARG...]
function lk_trap_add() {
    (($# > 1)) || lk_err "invalid arguments" || return
    set -- "$1" "$2${3+ $(shift 2 && lk_quote_args "$@")}"
    _LK_TRAPS=(${_LK_TRAPS+"${_LK_TRAPS[@]}"})
    local i TRAPS=()
    for ((i = 0; i < ${#_LK_TRAPS[@]}; i += 3)); do
        ((_LK_TRAPS[i] == BASH_SUBSHELL)) &&
            [[ ${_LK_TRAPS[i + 1]} == "$1" ]] || continue
        TRAPS[${#TRAPS[@]}]=${_LK_TRAPS[i + 2]}
        [[ ${_LK_TRAPS[i + 2]} != "${2-}" ]] ||
            set -- "$1"
    done
    (($# == 1)) || {
        TRAPS[${#TRAPS[@]}]=$2
        _LK_TRAPS+=("$BASH_SUBSHELL" "$1" "$2")
    }
    trap -- "declare _LK_TRAP_STATUS=0;$(
        printf '{ %s;}||_LK_TRAP_STATUS=$?;' "${TRAPS[@]}"
    )(exit \$_LK_TRAP_STATUS)" "$1"
}

function _lk_cleanup_on_exit() {
    local ARRAY=$1 COMMAND=$2
    shift 2
    [ -n "${!ARRAY+1}" ] ||
        eval "function ${ARRAY}_trap() {
    local STATUS=\$?
    { [ -z \"\${${ARRAY}+1}\" ] ||
        $COMMAND \"\${${ARRAY}[@]}\" || [ \"\$EUID\" -eq 0 ] ||
        sudo $COMMAND \"\${${ARRAY}[@]}\" || true; } 2>/dev/null
    return \"\$STATUS\"
} && $ARRAY=() && lk_trap_add EXIT ${ARRAY}_trap" || return
    eval "$ARRAY+=(\"\$@\")"
}

function lk_kill_on_exit() {
    _lk_cleanup_on_exit "_LK_EXIT_KILL_$BASH_SUBSHELL" "kill" "$@"
}

function lk_delete_on_exit() {
    _lk_cleanup_on_exit "_LK_EXIT_DELETE_$BASH_SUBSHELL" "rm -Rf --" "$@"
}

# lk_delete_on_exit_withdraw FILE...
function lk_delete_on_exit_withdraw() {
    while [ $# -gt 0 ]; do
        lk_arr_remove "_LK_EXIT_DELETE_$BASH_SUBSHELL" "$1" || return
        shift
    done
}

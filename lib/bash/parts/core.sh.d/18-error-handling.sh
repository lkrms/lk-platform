#!/bin/bash

function _lk_caller() {
    local CALLER
    if lk_script_is_running; then
        CALLER=("${0##*/}")
    else
        CALLER=(${FUNCNAME+"${FUNCNAME[*]: -1}"})
        [ -n "${CALLER+1}" ] || CALLER=("{main}")
    fi
    CALLER[0]=$LK_BOLD$CALLER$LK_RESET
    lk_verbose || {
        echo "$CALLER"
        return
    }
    local CONTEXT REGEX='^([0-9]*) [^ ]* (.*)$' SOURCE= LINE=
    if [[ ${1-} =~ $REGEX ]]; then
        SOURCE=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    else
        SOURCE=${BASH_SOURCE[2]-}
        LINE=${BASH_LINENO[3]-}
    fi
    [ -z "$SOURCE" ] || [ "$SOURCE" = main ] || [ "$SOURCE" = "$0" ] ||
        CALLER+=("$(lk_tty_path "$SOURCE")")
    [ -z "$LINE" ] ||
        CALLER[${#CALLER[@]} - 1]+=$LK_DIM:$LINE$LK_RESET
    lk_implode_args "$LK_DIM->$LK_RESET" "${CALLER[@]}"
}

# lk_warn [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as a warning and return the most recent exit status.
function lk_warn() {
    local STATUS=$?
    lk_console_warning "$(LK_VERBOSE= _lk_caller): ${1-execution failed}"
    return "$STATUS"
}

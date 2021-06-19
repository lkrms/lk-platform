#!/bin/bash

function _lk_caller() {
    local CALLER
    if lk_script_is_running; then
        CALLER=("${0##*/}")
    else
        CALLER=("${FUNCNAME+${FUNCNAME[*]: -1:1}}")
        [ -n "$CALLER" ] || CALLER=("{main}")
    fi
    CALLER[0]=$LK_BOLD$CALLER$LK_RESET
    lk_verbose || {
        echo "$CALLER"
        return
    }
    local CONTEXT REGEX='^([0-9]*) ([^ ]*) (.*)$' SOURCE= FUNC= LINE=
    if CONTEXT=${1-$(caller 1)} && [[ $CONTEXT =~ $REGEX ]]; then
        SOURCE=${BASH_REMATCH[3]}
        FUNC=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    else
        SOURCE=${BASH_SOURCE[2]-}
        FUNC=${FUNCNAME[2]-}
        LINE=${BASH_LINENO[3]-}
    fi
    [ -z "$SOURCE" ] || [ "$SOURCE" = main ] || [ "$SOURCE" = "$0" ] ||
        CALLER+=("$(lk_pretty_path "$SOURCE")")
    [ -z "$LINE" ] ||
        CALLER[${#CALLER[@]} - 1]+=$LK_DIM:$LINE$LK_RESET
    lk_implode "$LK_DIM->$LK_RESET" CALLER
}

# lk_warn [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as a warning and return the most recent exit status.
function lk_warn() {
    local STATUS=$?
    lk_console_warning "$(LK_VERBOSE= _lk_caller): ${1-execution failed}"
    return "$STATUS"
}

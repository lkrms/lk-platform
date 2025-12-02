#!/usr/bin/env bash

function _lk_caller() {
    local CALLER
    CALLER=("$(lk_script 2)")
    CALLER[0]=$LK_BOLD$CALLER$LK_RESET
    lk_verbose || {
        echo "$CALLER"
        return
    }
    local REGEX='^([0-9]*) [^ ]* (.*)$' SOURCE LINE
    if [[ ${1-} =~ $REGEX ]]; then
        SOURCE=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    else
        SOURCE=${BASH_SOURCE[2]-}
        LINE=${BASH_LINENO[3]-}
    fi
    [[ -z $SOURCE ]] || [[ $SOURCE == main ]] || [[ $SOURCE == "$0" ]] ||
        CALLER+=("$(lk_tty_path "$SOURCE")")
    [[ -z $LINE ]] || [[ $LINE -eq 1 ]] ||
        CALLER[${#CALLER[@]} - 1]+=$LK_DIM:$LINE$LK_UNBOLD_UNDIM
    lk_implode_arr "$LK_DIM->$LK_UNBOLD_UNDIM" CALLER
}

# lk_warn [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as a warning and return the most recent exit status.
function lk_warn() {
    lk_pass -$? \
        lk_tty_warning "$(LK_VERBOSE= _lk_caller): ${1-command failed}"
}

# lk_die [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as an error and return or exit non-zero with the
# most recent exit status or 1. If MESSAGE is the empty string, suppress output.
function lk_die() {
    local status=$?
    ((status)) || status=1
    (($#)) || set -- "command failed"
    [[ -z $1 ]] || lk_tty_error "$(_lk_caller): $1"
    if [[ $- != *i* ]]; then
        exit $status
    else
        return $status
    fi
}

#### Reviewed: 2021-11-02

#!/bin/bash

function _lk_caller() {
    local CONTEXT REGEX='^([0-9]*) ([^ ]*) (.*)$' SOURCE= FUNC= LINE= \
        CALLER=("$LK_BOLD${0##*/}$LK_RESET")
    ! CONTEXT=${1-$(caller 1)} || [[ ! $CONTEXT =~ $REGEX ]] || {
        SOURCE=${BASH_REMATCH[3]}
        FUNC=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    }
    ! lk_verbose 2 || {
        [ -z "$SOURCE" ] || [ "$SOURCE" = main ] || [ "$SOURCE" = "$0" ] ||
            CALLER+=("$(lk_pretty_path "$SOURCE")")
        [ -z "$LINE" ] ||
            CALLER[${#CALLER[@]} - 1]+=$LK_DIM:$LINE$LK_RESET
        [ -z "$FUNC" ] || [ "$FUNC" = main ] ||
            CALLER+=("$FUNC$LK_DIM()$LK_RESET")
    }
    lk_implode "$LK_DIM->$LK_RESET" CALLER
}

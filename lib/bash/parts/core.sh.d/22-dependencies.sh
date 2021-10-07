#!/bin/bash

function lk_include() {
    local FILE
    while [ $# -gt 0 ]; do
        [[ ,$_LK_INCLUDES, == *,$1,* ]] || {
            FILE=${_LK_INST:-$LK_BASE}/lib/bash/include/$1.sh
            [ -r "$FILE" ] || lk_err "file not found: $FILE" || return
            . "$FILE" || return
        }
        shift
    done
}

function lk_provide() {
    [[ ,$_LK_INCLUDES, == *,$1,* ]] ||
        _LK_INCLUDES=$_LK_INCLUDES,$1
}

#### Reviewed: 2021-10-04

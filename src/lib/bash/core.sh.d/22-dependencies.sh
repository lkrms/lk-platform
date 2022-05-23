#!/bin/bash

function lk_require() {
    local FILE
    while (($#)); do
        [[ ,$_LK_SOURCED, == *,$1,* ]] || {
            FILE=$LK_BASE/lib/bash/include/$1.sh
            [[ -r $FILE ]] || lk_err "file not found: $FILE" || return
            _LK_SOURCED+=,$1
            . "$FILE" || return
        }
        shift
    done
}

_LK_SOURCED=core

#### Reviewed: 2022-05-23

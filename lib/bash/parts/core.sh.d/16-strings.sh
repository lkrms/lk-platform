#!/bin/bash

function lk_ere_escape() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_ere_escape
    else
        sed -E 's/[]$()*+.?\^{|}[]/\\&/g'
    fi
}

function lk_sed_escape() {
    local DELIM=${_LK_SED_DELIM-/}
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_sed_escape
    else
        sed -E "s/[]\$()*+.$DELIM?\\^{|}[]/\\\\&/g"
    fi
}

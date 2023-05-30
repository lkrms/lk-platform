#!/bin/bash

# lk_squeeze_whitespace [FILE...]
function lk_squeeze_whitespace() {
    local AWK
    lk_awk_load AWK sh-squeeze-whitespace || return
    awk -f "$AWK" "$@"
}

# lk_pv [-s SIZE] [FILE...]
function lk_pv() {
    local OTHER_ARGS=0
    [[ ${1-} != -s ]] || OTHER_ARGS=2
    if (($# - OTHER_ARGS)); then
        pv "$@"
    else
        trap "" SIGINT
        exec pv "$@"
    fi
}

# lk_tee [FILE...]
function lk_tee() {
    trap "" SIGINT
    exec tee "$@"
}

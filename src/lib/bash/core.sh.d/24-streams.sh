#!/bin/bash

# lk_squeeze_whitespace [FILE...]
function lk_squeeze_whitespace() {
    local AWK
    lk_awk_load AWK sh-squeeze-whitespace || return
    awk -f "$AWK" "$@"
}

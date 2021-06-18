#!/bin/bash

# lk_fd_is_open FD
function lk_fd_is_open() {
    [ -n "${1-}" ] && { : >&"$1"; } 2>/dev/null
}

# lk_fd_next
#
# In lieu of Bash 4.1's file descriptor variable syntax ({var}>, {var}<, etc.),
# output the number of the next available file descriptor greater than or equal
# to 10.
function lk_fd_next() {
    local USED FD=10 i=0
    [ -d /dev/fd ] &&
        USED=($(ls -1 /dev/fd/ | sort -n)) && [ ${#USED[@]} -ge 3 ] ||
        lk_warn "not supported: /dev/fd" || return
    while ((i < ${#USED[@]})); do
        ((FD >= USED[i])) || break
        ((FD > USED[i])) || ((FD++))
        ((++i))
    done
    echo "$FD"
}

#!/usr/bin/env bash

# lk_fd_is_open <fd>
#
# Check if the given file descriptor is open.
function lk_fd_is_open() {
    [[ ${1-} ]] && { : >&"$1"; } 2>/dev/null
}

# lk_fd_next
#
# Print the number of the next unallocated file descriptor greater than or equal
# to 10.
function lk_fd_next() {
    local fd file open=()
    for file in /dev/fd/*; do
        fd=${file##*/}
        open[fd]=1
    done
    fd=10
    while [[ ${open[fd]-} ]]; do
        ((++fd))
    done
    printf '%d\n' $fd
}

#### Reviewed: 2025-12-24

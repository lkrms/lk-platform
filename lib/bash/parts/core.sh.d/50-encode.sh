#!/bin/bash

# lk_hash [ARG...]
#
# Compute the hash of the arguments or input using the most efficient algorithm
# available (xxHash, SHA or MD5), joining multiple arguments to form one string
# with a space between each argument.
function lk_hash() {
    _LK_HASH_COMMAND=${_LK_HASH_COMMAND:-${LK_HASH_COMMAND:-$(
        lk_command_first xxhsum shasum md5sum md5
    )}} || lk_warn "checksum command not found" || return
    if [ $# -gt 0 ]; then
        local IFS
        unset IFS
        printf '%s' "$*" | "$_LK_HASH_COMMAND"
    else
        "$_LK_HASH_COMMAND"
    fi | awk '{print $1}'
} #### Reviewed: 2021-07-15

function lk_md5() {
    local _LK_HASH_COMMAND
    _LK_HASH_COMMAND=$(lk_command_first md5sum md5) ||
        lk_warn "md5 command not found" || return
    lk_hash "$@"
} #### Reviewed: 2021-07-15

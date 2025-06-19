#!/usr/bin/env bash

# lk_gpg_check_key_validity [GPG_ARG...] KEY_ID
#
# Return true if KEY_ID is valid, 2 if it is installed but invalid, 3 if it is
# invalid and not installed.
function lk_gpg_check_key_validity() {
    local IFS=$' \t\n' AWK
    lk_awk_load AWK sh-gpg-check-key-validity || return
    lk_sudo gpg "${@:1:$#-1}" --batch --with-colons --list-keys "${*: -1}" |
        awk -v key_id="${*: -1}" -f "$AWK"
}

#!/bin/bash

# lk_postconf_get PARAM
function lk_postconf_get() {
    # `postconf -nh` prints a newline if the parameter has an empty value, and
    # nothing at all if the parameter is not set in main.cf
    (($(postconf -nh "$1" | wc -c))) && postconf -nh "$1"
}

# lk_postconf_set PARAM VALUE
function lk_postconf_set() {
    lk_postconf_get "$1" | grep -Fx "$2" >/dev/null ||
        { lk_elevate postconf -e "$1 = $2" &&
            lk_mark_dirty "postfix.service"; }
}

# lk_postconf_unset PARAM
function lk_postconf_unset() {
    ! lk_postconf_get "$1" >/dev/null ||
        { lk_elevate postconf -X "$1" &&
            lk_mark_dirty "postfix.service"; }
}

# lk_postmap SOURCE_PATH DB_PATH [FILE_MODE]
#
# Safely install or update the Postfix database at DB_PATH with the content of
# SOURCE_PATH.
function lk_postmap() {
    local LK_SUDO=1 FILE=$2.in
    lk_install -m "${3:-00644}" "$FILE" &&
        lk_elevate cp "$1" "$FILE" &&
        lk_elevate postmap "$FILE" || return
    if ! lk_elevate diff -qN "$2" "$FILE" >/dev/null ||
        ! diff -qN \
            <(lk_elevate postmap -s "$2" | sort) \
            <(lk_elevate postmap -s "$FILE" | sort) >/dev/null; then
        lk_elevate mv -f "$FILE.db" "$2.db" &&
            lk_elevate mv -f "$FILE" "$2" &&
            lk_mark_dirty "postfix.service"
    else
        lk_elevate rm -f "$FILE"{,.db}
    fi
}

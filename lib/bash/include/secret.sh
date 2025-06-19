#!/usr/bin/env bash

# _lk_secret_set VALUE LABEL [SERVICE]
function _lk_secret_set() {
    if lk_is_macos; then
        security add-generic-password -a "$1" -l "$2" -s "${3:-${0##*/}}" -U -w
    elif lk_command_exists secret-tool; then
        secret-tool store --label="$2" -- service "${3:-${0##*/}}" value "$1"
    else
        false
    fi
}

# _lk_secret_get VALUE [SERVICE]
function _lk_secret_get() {
    if lk_is_macos; then
        security find-generic-password -a "$1" -s "${2:-${0##*/}}" -w
    elif lk_command_exists secret-tool; then
        secret-tool lookup -- service "${2:-${0##*/}}" value "$1"
    else
        false
    fi
}

# _lk_secret_forget VALUE [SERVICE]
function _lk_secret_forget() {
    if lk_is_macos; then
        security delete-generic-password -a "$1" -s "${2:-${0##*/}}"
    elif lk_command_exists secret-tool; then
        secret-tool clear -- service "${2:-${0##*/}}" value "$1"
    else
        false
    fi
}

# lk_secret VALUE LABEL [SERVICE]
#
# Print the given secret without a trailing newline. If it does not already
# exist, prompt the user to add it first.
function lk_secret() {
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    set -- "$1" "$2" "${3:-$(lk_caller_name)}"
    local KEYCHAIN=keychain PASSWORD SECRET=$LK_DIM$3/$LK_UNDIM$1
    lk_is_macos || KEYCHAIN=keyring
    if ! PASSWORD=$(_lk_secret_get "$1" "$3" 2>/dev/null); then
        ! lk_no_input ||
            lk_warn "password not found: $SECRET" || return
        lk_tty_print "Password requested:" "$SECRET"
        lk_tty_detail "Label:" "$2"
        lk_tty_yn "Add this password to your $KEYCHAIN?" Y &&
            _lk_secret_set "$@" &&
            PASSWORD=$(_lk_secret_get "$1" "$3") || return
    fi
    printf '%s' "$PASSWORD"
}

# lk_secret_remove VALUE [SERVICE]
function lk_secret_remove() {
    [ $# -ge 1 ] || lk_warn "invalid arguments" || return
    set -- "$1" "${2:-$(lk_caller_name)}"
    local SECRET=$LK_DIM$2/$LK_UNDIM$1
    _lk_secret_get "$@" &>/dev/null ||
        lk_warn "password not found: $SECRET" || return 0
    _lk_secret_forget "$@" >/dev/null &&
        lk_tty_print "Password removed:" "$SECRET"
}

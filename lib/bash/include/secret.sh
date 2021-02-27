#!/bin/bash

if lk_is_macos; then
    # lk_secret_set VALUE LABEL [SERVICE]
    function lk_secret_set() {
        security add-generic-password -a "$1" -l "$2" -s "${3:-${0##*/}}" -U -w
    }
    # lk_secret_get VALUE [SERVICE]
    function lk_secret_get() {
        security find-generic-password -a "$1" -s "${2:-${0##*/}}" -w
    }
    # lk_secret_forget VALUE [SERVICE]
    function lk_secret_forget() {
        security delete-generic-password -a "$1" -s "${2:-${0##*/}}"
    }
else
    # lk_secret_set VALUE LABEL [SERVICE]
    function lk_secret_set() {
        secret-tool store --label="$2" -- service "${3:-${0##*/}}" value "$1"
    }
    # lk_secret_get VALUE [SERVICE]
    function lk_secret_get() {
        secret-tool lookup -- service "${2:-${0##*/}}" value "$1"
    }
    # lk_secret_forget VALUE [SERVICE]
    function lk_secret_forget() {
        secret-tool clear -- service "${2:-${0##*/}}" value "$1"
    }
fi

# lk_secret VALUE LABEL [SERVICE]
function lk_secret() {
    local SERVICE=${3:-$(lk_myself 1)} KEYCHAIN=keychain PASSWORD
    [ -n "${1:-}" ] || lk_warn "no value" || return
    [ -n "${2:-}" ] || lk_warn "no label" || return
    lk_is_macos || KEYCHAIN=keyring
    if ! PASSWORD=$(lk_secret_get "$1" "$SERVICE" 2>/dev/null); then
        ! lk_no_input ||
            lk_warn "no password for $SERVICE->$1 found in $KEYCHAIN" ||
            return
        lk_console_message \
            "Enter the password for $2 to add it to your $KEYCHAIN"
        lk_secret_set "$1" "$2" "$SERVICE" &&
            PASSWORD=$(lk_secret_get "$1" "$SERVICE") || return
    fi
    printf '%s' "$PASSWORD"
}

# lk_remove_secret VALUE [SERVICE]
function lk_remove_secret() {
    [ -n "${1:-}" ] || lk_warn "no value" || return
    lk_secret_get "$@" &>/dev/null ||
        lk_warn "password not found" || return 0
    lk_secret_forget "$@" || return
    lk_console_message "Password removed successfully"
}

lk_provide secret

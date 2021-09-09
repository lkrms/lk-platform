#!/bin/bash

function _lk_openssl_verify() { (
    # Disable xtrace if its output would break the test below
    [[ $- != *x* ]] ||
        { lk_bash_at_least 4 1 && [ "${BASH_XTRACEFD:-2}" -gt 2 ]; } ||
        set +x
    # In case openssl is too old to exit non-zero when `verify` fails, return
    # false if there are multiple lines of output (NB: some versions send errors
    # to stderr)
    lk_sudo openssl verify "$@" 2>&1 |
        awk '{print} END {exit NR > 1 ? 1 : 0}'
); }

# lk_ssl_is_cert_self_signed CERT_FILE
function lk_ssl_is_cert_self_signed() {
    lk_mktemp_dir_with -c _LK_EMPTY_DIR || return
    # "-CApath /empty/dir" is more portable than "-no-CApath"
    _lk_openssl_verify -CApath "$_LK_EMPTY_DIR" -CAfile "$1" "$1" >/dev/null
}

# lk_ssl_verify_cert [-s] CERT_FILE [KEY_FILE [CA_FILE]]
#
# If -s is set, return true if the certificate is trusted, even if it is
# self-signed.
function lk_ssl_verify_cert() {
    local SS_OK
    [ "${1-}" != -s ] || { SS_OK=1 && shift; }
    lk_files_exist "$@" || lk_usage "\
Usage: $FUNCNAME [-s] CERT_FILE [KEY_FILE [CA_FILE]]" || return
    local CERT=$1 KEY=${2-} CA=${3-} CERT_MODULUS KEY_MODULUS
    # If no CA file has been provided but CERT contains multiple certificates,
    # copy the first to a temp CERT file and the others to a temp CA file
    [ -n "$CA" ] || [ "$(grep -Ec "^-+BEGIN$S" "$CERT")" -le 1 ] ||
        { lk_mktemp_with CA \
            lk_sudo awk "/^-+BEGIN$S/ {c++} c > 1 {print}" "$CERT" &&
            lk_mktemp_with CERT \
                lk_sudo awk "/^-+BEGIN$S/ {c++} c <= 1 {print}" "$CERT" ||
            return; }
    if [ -n "$CA" ]; then
        _lk_openssl_verify "$CA" &&
            _lk_openssl_verify -untrusted "$CA" "$CERT"
    else
        _lk_openssl_verify "$CERT"
    fi >/dev/null ||
        lk_warn "invalid certificate chain" || return
    [ -z "$KEY" ] || {
        CERT_MODULUS=$(lk_sudo openssl x509 -noout -modulus -in "$CERT") &&
            KEY_MODULUS=$(lk_sudo openssl rsa -noout -modulus -in "$KEY") &&
            [ "$CERT_MODULUS" = "$KEY_MODULUS" ] ||
            lk_warn "certificate and private key do not match" || return
    }
    [ -n "${SS_OK-}" ] || ! lk_ssl_is_cert_self_signed "$CERT" ||
        lk_warn "certificate is self-signed" || return
}

#### Reviewed: 2021-09-10

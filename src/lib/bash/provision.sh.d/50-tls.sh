#!/usr/bin/env bash

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
    lk_mktemp_dir_with -r _LK_EMPTY_DIR || return
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
    [ -n "$CA" ] || [ "$(grep -Ec "^-+BEGIN$LK_h" "$CERT")" -le 1 ] ||
        { lk_mktemp_with CA \
            lk_sudo awk "/^-+BEGIN$LK_h/ {c++} c > 1 {print}" "$CERT" &&
            lk_mktemp_with CERT \
                lk_sudo awk "/^-+BEGIN$LK_h/ {c++} c <= 1 {print}" "$CERT" ||
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

# lk_ssl_create_self_signed_cert DOMAIN...
function lk_ssl_create_self_signed_cert() {
    [ $# -gt 0 ] || lk_usage "Usage: $FUNCNAME DOMAIN..." || return
    lk_test lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    lk_tty_print "Creating a self-signed TLS certificate for:" \
        $'\n'"$(printf '%s\n' "$@")"
    local CA_FILE=${LK_SSL_CA:+$1-${LK_SSL_CA##*/}}
    lk_no_input || {
        local FILES=("$1".{key,csr,cert} ${CA_FILE:+"$CA_FILE"})
        lk_remove_missing_or_empty FILES || return
        [ ${#FILES[@]} -eq 0 ] || {
            lk_tty_detail "Files to overwrite:" \
                $'\n'"$(printf '%s\n' "${FILES[@]}")"
            lk_confirm "Proceed?" Y || return
        }
    }
    local CONF
    lk_mktemp_with CONF cat /etc/ssl/openssl.cnf &&
        printf "\n[ %s ]\n%s = %s" san subjectAltName \
            "$(lk_implode_args ", " "${@/#/DNS:}")" >>"$CONF" || return
    lk_install -m 00644 "$1.cert" ${CA_FILE:+"$CA_FILE"} &&
        lk_install -m 00640 "$1".{key,csr} || return
    local ARGS=(-signkey "$1.key")
    [ -z "$CA_FILE" ] || {
        local ARGS=(-CA "$LK_SSL_CA" -CAcreateserial)
        [ -z "${LK_SSL_CA_KEY:+1}" ] ||
            ARGS+=(-CAkey "$LK_SSL_CA_KEY")
    }
    lk_sudo openssl req -new \
        -newkey rsa:2048 \
        -nodes \
        -keyout "$1.key" \
        -subj "/OU=lk-platform/CN=$1" \
        -reqexts san \
        -config "$CONF" \
        -out "$1.csr" &&
        lk_sudo openssl x509 -req \
            -days 365 \
            -in "$1.csr" \
            -extensions san \
            -extfile "$CONF" \
            -out "$1.cert" \
            "${ARGS[@]}" &&
        lk_sudo rm -f "$1.csr" || return
    [ -z "$CA_FILE" ] || {
        lk_sudo openssl x509 -in "$LK_SSL_CA" -out "$CA_FILE" &&
            LK_VERBOSE= lk_file_replace \
                "$1.cert" < <(lk_sudo cat "$1.cert" "$CA_FILE")
    }
}

# lk_ssl_install_ca_certificate CERT_FILE
function lk_ssl_install_ca_certificate() {
    local DIR COMMAND CERT FILE \
        _LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE-}
    unset LK_FILE_REPLACE_NO_CHANGE
    DIR=$(lk_first_file \
        /usr/local/share/ca-certificates/ \
        /etc/ca-certificates/trust-source/anchors/) &&
        COMMAND=$(LK_SUDO= && lk_first_command \
            update-ca-certificates \
            update-ca-trust) ||
        lk_warn "CA certificate store not found" || return
    lk_mktemp_with CERT \
        lk_sudo openssl x509 -in "$1" || return
    FILE=$DIR${1##*/}
    FILE=${FILE%.*}.crt
    local LK_SUDO=1
    lk_install -m 00644 "$FILE" &&
        LK_FILE_NO_DIFF=1 \
            lk_file_replace -mf "$1" "$FILE" || return
    if lk_false LK_FILE_REPLACE_NO_CHANGE; then
        lk_elevate "$COMMAND"
    else
        LK_FILE_REPLACE_NO_CHANGE=$_LK_FILE_REPLACE_NO_CHANGE
    fi
}

#### Reviewed: 2021-09-10

#!/bin/bash

# lk_postconf_get PARAM
#
# Print the value of a Postfix parameter or return false if it is not explicitly
# configured.
function lk_postconf_get() {
    # `postconf -nh` prints a newline if the parameter has an empty value, and
    # nothing at all if the parameter is not set in main.cf, so:
    # 1. suppress error output from postconf
    # 2. clone stdout to stderr
    # 3. fail if there is no output (expression will resolve to `((0))`)
    # 4. redirect cloned output to stdout
    (($(postconf -nh "$1" 2>/dev/null | tee /dev/stderr | wc -c))) 2>&1
}

# lk_postconf_get_effective PARAM
#
# Expand and print the value of a Postfix parameter or return false if it is
# unknown.
function lk_postconf_get_effective() {
    # `postconf -h` never exits non-zero, but if an error occurs it explains on
    # stderr, so:
    # 1. flip stdout and stderr
    # 2. fail on output to stderr (expression will resolve to `! ((0))`)
    # 3. redirect stderr back to stdout
    ! (($(postconf -xh "$1" 3>&1 1>&2 2>&3 | wc -c))) 2>&1
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

function lk_postfix_provision() {
    lk_postconf_set header_size_limit 409600
    lk_postconf_set smtpd_tls_security_level may
    lk_postconf_set smtp_tls_security_level may
}

# lk_postfix_apply_transport_maps [DB_PATH]
#
# Install or update the Postfix transport_maps database at DB_PATH or
# /etc/postfix/transport from LK_SMTP_TRANSPORT_MAPS.
function lk_postfix_apply_transport_maps() {
    local IFS=, FILE=${1:-/etc/postfix/transport} TEMP i=0 \
        MAPS MAP _FROM FROM TO
    lk_mapfile MAPS < <(tr ';' '\n' <<<"${LK_SMTP_TRANSPORT_MAPS-}")
    lk_mktemp_with TEMP
    for MAP in ${MAPS+"${MAPS[@]}"}; do
        [[ $MAP == *=* ]] || continue
        TO=${MAP##*=}
        [[ -n $TO ]] || continue
        [[ $TO =~ ^(relay|smtp):* ]] || TO=relay:$TO
        _FROM=(${MAP%=*})
        for FROM in ${_FROM+"${_FROM[@]}"}; do
            [[ -n $FROM ]] || continue
            printf '%s\t%s\n' "$FROM" "$TO"
            ((++i))
        done
    done >"$TEMP"
    lk_postmap "$TEMP" "$FILE" &&
        if ((i)); then
            lk_postconf_set transport_maps "hash:$FILE"
        else
            lk_postconf_unset transport_maps
        fi
}

# lk_postfix_apply_tls_certificate WEBROOT [DOMAIN...]
function lk_postfix_apply_tls_certificate() {
    [[ -d ${1-} ]] || lk_warn "invalid arguments" || return
    local IFS=$' \t\n' WEBROOT=$1 POSTFIX
    POSTFIX=$(type -P postfix) || lk_warn "command not found: postfix" || return
    shift
    set -- $({
        lk_postconf_get_effective myhostname
        lk_args "$@"
    } | lk_uniq)
    lk_is_fqdn "$@" || lk_warn "invalid $(lk_plural $# domain): $*" || return
    lk_tty_print "Checking Postfix TLS certificate:" "$*"
    lk_certbot_maybe_install -w "$WEBROOT" "$@" &&
        [[ -n ${LK_CERTBOT_INSTALLED:+1} ]] &&
        lk_certbot_register_deploy_hook "$POSTFIX" reload -- "$@" || return

    # Fields (see `lk_certbot_list`):
    # 4. Certificate path
    # 5. Private key path
    IFS=$'\t'
    local CERT=($LK_CERTBOT_INSTALLED)
    lk_postconf_set smtpd_tls_cert_file "${CERT[3]}"
    lk_postconf_set smtpd_tls_key_file "${CERT[4]}"
    lk_postconf_set smtp_tls_cert_file '$smtpd_tls_cert_file'
    lk_postconf_set smtp_tls_key_file '$smtpd_tls_key_file'
    lk_postconf_set smtp_tls_loglevel 1
}

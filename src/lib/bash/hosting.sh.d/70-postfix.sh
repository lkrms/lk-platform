#!/bin/bash

function _lk_hosting_postfix_provision() {
    local SITES RELAYHOST PASSWD \
        RELAYHOST_PATH=/etc/postfix/sender_relayhost \
        PASSWD_PATH=/etc/postfix/sasl_passwd
    lk_mktemp_with SITES lk_hosting_list_sites -j &&
        lk_mktemp_with RELAYHOST lk_jq -r 'include "core";
[ sort_by(.domain)[] | select(.smtp_relay.host != null) |
    [ .domain, .smtp_relay.host ] as [ $domain, $host ] | .smtp_relay |
    .senders // [ $domain ] | .[] | [ ., $host ] ] | to_hash[] | @tsv' \
            <"$SITES" || return
    if [[ -s $RELAYHOST ]]; then
        lk_mktemp_with PASSWD lk_jq -r 'include "core";
[ sort_by(.domain)[] | select(.smtp_relay.credentials != null) |
    [ .domain, .smtp_relay.credentials ] as [ $domain, $credentials ] | .smtp_relay |
    .senders // [ $domain ] | .[] | [ ., $credentials ] ] | to_hash[] | @tsv' \
            <"$SITES" &&
            lk_postmap "$PASSWD" "$PASSWD_PATH" 00600 &&
            lk_postmap "$RELAYHOST" "$RELAYHOST_PATH" || return
        lk_postconf_set sender_dependent_relayhost_maps "$RELAYHOST_PATH" &&
            lk_postconf_set smtp_sasl_password_maps "$PASSWD_PATH" &&
            lk_postconf_set smtp_sasl_auth_enable yes &&
            lk_postconf_set smtp_sasl_tls_security_options noanonymous
    else
        lk_postconf_unset smtp_sasl_tls_security_options &&
            lk_postconf_unset smtp_sasl_auth_enable &&
            lk_postconf_unset smtp_sasl_password_maps &&
            lk_postconf_unset sender_dependent_relayhost_maps
    fi
}

function _lk_hosting_postfix_test_config() {
    ! { lk_elevate postconf >/dev/null; } 2>&1 | grep . >/dev/null &&
        [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == 01 ]]
}

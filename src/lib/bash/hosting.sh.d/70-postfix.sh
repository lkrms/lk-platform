#!/bin/bash

function _lk_hosting_postfix_provision() {
    local SITES TEMP \
        RELAY=${LK_SMTP_RELAY:+"relay:$LK_SMTP_RELAY"} \
        TRANSPORT=/etc/postfix/transport \
        SENDER_TRANSPORT=/etc/postfix/sender_transport \
        PASSWD=/etc/postfix/sasl_passwd \
        ACCESS=/etc/postfix/sender_access

    lk_postfix_apply_transport_maps "$TRANSPORT" || return

    lk_postfix_apply_tls_certificate /var/www/html ||
        [[ -z ${LK_CERTBOT_INSTALLED-} ]] || return

    lk_mktemp_with SITES lk_hosting_list_sites -e -j &&
        lk_mktemp_with TEMP || return

    # 1. Use `sender_dependent_default_transport_maps` to deliver mail to
    #    destinations configured in LK_SMTP_* and SITE_SMTP_*. For reference:
    #
    #    "In order of decreasing precedence, the nexthop destination is taken
    #    from $sender_dependent_default_transport_maps, $default_transport,
    #    $sender_dependent_relayhost_maps, $relayhost, or from the recipient
    #    domain."
    {
        # If LK_SMTP_RELAY only applies to mail sent by LK_SMTP_SENDERS, it
        # belongs here too
        #
        # TODO: move this to provision.sh and maintain separate maps
        if [[ -n ${LK_SMTP_RELAY:+${LK_SMTP_SENDERS:+1}} ]]; then
            local IFS=,
            for SENDER in $LK_SMTP_SENDERS; do
                [[ $SENDER == *@* ]] ||
                    lk_warn "not an email address or @domain: $SENDER" ||
                    continue
                printf '%s\t%s\n' "$SENDER" "$RELAY"
            done
            unset IFS
        else
            RELAY=${RELAY:-smtp:}
            printf '%s\t%s\n' "@${LK_NODE_FQDN-}" "$RELAY"
        fi

        # For each domain and sender configured, add an `smtp:` entry to deliver
        # mail directly if:
        # - LK_SMTP_RELAY is unset or doesn't apply to the sender; and
        # - SITE_SMTP_RELAY is not configured
        #
        # Otherwise, add a `relay:<SMTP_RELAY>` entry.
        jq -r --arg relayhost "$RELAY" '
sort_by(.domain)[] |
  [ [ ( .domain,
      if .www_enabled then "www.\(.domain)" else empty end,
      .alias_domains[] ) | "@\(.)" ],
    if .smtp_relay.host
    then "relay:\(.smtp_relay.host)"
    else $relayhost end ] as [ $domains, $host ] |
  .smtp_relay | .senders // $domains | .[] | [ ., $host ] | @tsv' <"$SITES"
    } | awk -F '\t' \
        'seen[$1]++{print"Duplicate key: "$0>"/dev/stderr";next}{print}' \
        >"$TEMP" &&
        lk_postmap "$TEMP" "$SENDER_TRANSPORT" &&
        lk_postconf_set relayhost "" &&
        lk_postconf_unset sender_dependent_relayhost_maps &&
        lk_postconf_set \
            default_transport "${LK_SMTP_UNKNOWN_SENDER_TRANSPORT:-defer:}" &&
        lk_postconf_set \
            sender_dependent_default_transport_maps "hash:$SENDER_TRANSPORT" || return

    # 2. Install relay credentials and configure SMTP client parameters
    {
        # Add system-wide SMTP relay credentials if configured
        #
        # TODO: move this to provision.sh and maintain separate maps
        if [[ -n ${LK_SMTP_RELAY:+${LK_SMTP_CREDENTIALS:+1}} ]]; then
            local IFS=,
            for SENDER in ${LK_SMTP_SENDERS:-"$LK_SMTP_RELAY"}; do
                printf '%s\t%s\n' "$SENDER" "$LK_SMTP_CREDENTIALS"
            done
            unset IFS
        fi

        jq -r '
sort_by(.domain)[] | select(.smtp_relay.credentials != null) |
  [ [ ( .domain,
      if .www_enabled then "www.\(.domain)" else empty end,
      .alias_domains[] ) | "@\(.)" ],
    .smtp_relay.credentials ] as [ $domains, $cred ] |
  .smtp_relay | .senders // $domains | .[] | [ ., $cred ] | @tsv' <"$SITES" ||
            return
    } | awk -F '\t' \
        'seen[$1]++{print"Duplicate key: "$0>"/dev/stderr";next}{print}' \
        >"$TEMP" || return
    if [[ -s $TEMP ]]; then
        lk_postmap "$TEMP" "$PASSWD" 00600 &&
            lk_postconf_set smtp_sender_dependent_authentication "yes" &&
            lk_postconf_set smtp_sasl_password_maps "hash:$PASSWD" &&
            lk_postconf_set smtp_sasl_auth_enable "yes" &&
            lk_postconf_set smtp_sasl_tls_security_options "noanonymous"
    else
        lk_postconf_unset smtp_sasl_tls_security_options &&
            lk_postconf_unset smtp_sasl_auth_enable &&
            lk_postconf_unset smtp_sasl_password_maps &&
            lk_postconf_unset smtp_sender_dependent_authentication
    fi || return

    # 3. Reject mail from unknown senders in the context of `RCPT TO`. (This has
    #    no effect on sendmail, which bypasses smtpd_* restrictions.)
    #
    # TODO: move this to provision.sh
    awk -v OFS='\t' \
        '{sub("^@","");print$1,"permit_sender_relay"}' \
        <"$SENDER_TRANSPORT" >"$TEMP" || return
    lk_postmap "$TEMP" "$ACCESS" &&
        lk_postconf_set smtpd_restriction_classes \
            "permit_sender_relay" &&
        lk_postconf_set permit_sender_relay \
            "permit_mynetworks, permit_sasl_authenticated" 2>/dev/null &&
        lk_postconf_set smtpd_relay_restrictions \
            "check_sender_access hash:$ACCESS, defer_unauth_destination" || return
}

function _lk_hosting_postfix_test_config() {
    ! { lk_elevate postconf >/dev/null; } 2>&1 | grep . >/dev/null &&
        [[ ${PIPESTATUS[0]}${PIPESTATUS[1]} == 01 ]]
}

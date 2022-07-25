#!/bin/bash

function lk_hosting_certbot_maybe_install() {
    local SITE_DOMAINS CERT_DOMAINS NO_CERT_DOMAINS REGEX REQUESTS
    lk_arr_from SITE_DOMAINS lk_hosting_list_all_domains -e || return
    [[ -n ${SITE_DOMAINS+1} ]] || return 0
    lk_tty_print "Checking TLS certificates for" \
        "$(lk_plural -v SITE_DOMAINS domain)"
    lk_arr_from CERT_DOMAINS lk_certbot_list_all_domains &&
        lk_arr_from NO_CERT_DOMAINS lk_arr_diff SITE_DOMAINS CERT_DOMAINS ||
        return
    [[ -n ${NO_CERT_DOMAINS+1} ]] || {
        lk_tty_success "No certificates to acquire"
        return
    }
    # 1. Create a regex for the system's public IP address(es)
    REGEX=$(lk_system_get_public_ips | lk_ere_implode_input -e) || return
    [[ -n ${REGEX:+1} ]] || lk_warn "no public IP address found" || return 0
    # 2. Create a regex for NO_CERT_DOMAINS entries that resolve to the system
    REGEX=$(lk_dns_resolve_names -d "${NO_CERT_DOMAINS[@]}" |
        awk -v "regex=^${REGEX//\\/\\\\}\$" '$1 ~ regex { print $2 }' |
        lk_uniq | lk_ere_implode_input -e) || return
    [[ -n ${REGEX:+1} ]] || return 0
    lk_mktemp_with REQUESTS || return
    # 3. Create a list of sites with at least one domain that appears in
    #    NO_CERT_DOMAINS and resolves to the system
    lk_hosting_list_sites -e |
        awk -v "regex=(^|,)${REGEX//\\/\\\\}(\$|,)" \
            '$10~regex{print}' >"$REQUESTS" &&
        [[ -s $REQUESTS ]] ||
        lk_warn "error building certificate request list" || return
    local IFS=, DOMAIN SITE_ROOT ALL_DOMAINS CERT
    while IFS=$'\t' read -r DOMAIN SITE_ROOT ALL_DOMAINS; do
        lk_tty_detail "Requesting TLS certificate for" "${ALL_DOMAINS//,/ }"
        lk_certbot_maybe_install -w "$SITE_ROOT/public_html" $ALL_DOMAINS
        [[ -z ${LK_CERTBOT_INSTALLED:+1} ]] || {
            CERT=(${LK_CERTBOT_INSTALLED//$'\t'/,})
            lk_hosting_site_configure -n \
                -s SITE_SSL_CERT_FILE=${CERT[3]} \
                -s SITE_SSL_KEY_FILE=${CERT[4]} \
                -s SITE_SSL_CHAIN_FILE= || return
        }
    done < <(cut -f1,3,10 "$REQUESTS")
}

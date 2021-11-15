#!/bin/bash

# lk_certbot_list [DOMAIN...]
function lk_certbot_list() {
    local ARGS IFS=,
    [ $# -eq 0 ] ||
        ARGS=(--domains "$*")
    lk_elevate certbot certificates ${ARGS[@]+"${ARGS[@]}"} |
        awk -f "$LK_BASE/lib/awk/certbot-parse-certificates.awk"
}

# lk_certbot_install [-w WEBROOT_PATH] DOMAIN... [-- CERTBOT_ARG...]
function lk_certbot_install() {
    local WEBROOT WEBROOT_PATH ERRORS=0 \
        EMAIL=${LK_LETSENCRYPT_EMAIL-${LK_ADMIN_EMAIL-}} DOMAIN DOMAINS=()
    unset WEBROOT
    [ "${1-}" != -w ] || { WEBROOT= && WEBROOT_PATH=$2 && shift 2; }
    while [ $# -gt 0 ]; do
        [ "$1" != -- ] || {
            shift
            break
        }
        DOMAINS+=("$1")
        shift
    done
    [ ${#DOMAINS[@]} -gt 0 ] ||
        lk_usage "$FUNCNAME [-w WEBROOT_PATH] DOMAIN... [-- CERTBOT_ARG...]" ||
        return
    lk_is_fqdn "${DOMAINS[@]}" || lk_warn "invalid arguments" || return
    [ -z "${WEBROOT+1}" ] || lk_elevate test -d "$WEBROOT_PATH" ||
        lk_warn "directory not found: $WEBROOT_PATH" || return
    [ -n "$EMAIL" ] || lk_warn "email address not set" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    [ -n "${_LK_LETSENCRYPT_IGNORE_DNS-}" ] || {
        local IFS=' '
        lk_tty_print "Checking DNS"
        lk_tty_detail "Resolving $(lk_plural DOMAINS domain):" "${DOMAINS[*]}"
        for DOMAIN in "${DOMAINS[@]}"; do
            lk_node_is_host "$DOMAIN" ||
                lk_tty_error -r "System address not matched:" "$DOMAIN" ||
                ((++ERRORS))
        done
        ((!ERRORS)) || lk_confirm "Ignore DNS errors?" N || return
    }
    local IFS=,
    lk_run lk_elevate certbot \
        ${WEBROOT-run} \
        ${WEBROOT+certonly} \
        --non-interactive \
        --keep-until-expiring \
        --expand \
        --agree-tos \
        --email "$EMAIL" \
        --no-eff-email \
        ${WEBROOT---no-redirect} \
        ${WEBROOT---"${_LK_CERTBOT_PLUGIN:-apache}"} \
        ${WEBROOT+--webroot} \
        ${WEBROOT+--webroot-path "$WEBROOT_PATH"} \
        --domains "${DOMAINS[*]}" \
        ${LK_CERTBOT_OPTIONS[@]:+"${LK_CERTBOT_OPTIONS[@]}"} \
        "$@"
}

# lk_certbot_install_asap DOMAIN...
function lk_certbot_install_asap() {
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    local IFS=' ' RESOLVED FAILED CHANGED DOMAIN DOTS=0 LAST_RESOLVED=() i=0
    lk_tty_print "Preparing Let's Encrypt request"
    lk_tty_detail "Checking $(lk_plural $# domain):" "$*"
    while :; do
        RESOLVED=()
        FAILED=()
        CHANGED=0
        for DOMAIN in "$@"; do
            ! lk_node_is_host "$DOMAIN" || {
                RESOLVED+=("$DOMAIN")
                continue
            }
            FAILED+=("$DOMAIN")
        done
        [ "${RESOLVED[*]-}" = "${LAST_RESOLVED[*]-}" ] || {
            ((!DOTS)) || echo >&2
            ((DOTS = 0, CHANGED = 1))
            ((!i)) || lk_tty_log "Change detected at" "$(lk_date_log)"
            LAST_RESOLVED=(${RESOLVED+"${RESOLVED[@]}"})
        }
        [ -n "${FAILED+1}" ] || break
        ((i && !CHANGED)) ||
            lk_tty_error "System address not matched:" "${FAILED[*]}"
        ((i)) || lk_tty_detail "Checking DNS every 60 seconds"
        [ ! -t 2 ] || {
            echo -n . >&2
            ((++DOTS))
        }
        sleep 60
        ((++i))
    done
    _LK_LETSENCRYPT_IGNORE_DNS=1 lk_certbot_install "$@"
}

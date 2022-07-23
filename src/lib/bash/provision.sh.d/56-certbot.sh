#!/bin/bash

# lk_certbot_list [DOMAIN...]
#
# Parse `certbot certificates` output to tab-separated fields:
# 1. Certificate name
# 2. Domains (format: <name>[,www.<name>][,<other_domain>...])
# 3. Expiry date (format: %Y-%m-%d %H:%M:%S%z)
# 4. Certificate path
# 5. Private key path
function lk_certbot_list() {
    local ARGS AWK IFS=,
    ((!$#)) || ARGS=(--domains "$*")
    lk_awk_load AWK sh-certbot-list || return
    lk_elevate certbot certificates ${ARGS+"${ARGS[@]}"} 2>/dev/null |
        awk -f "$AWK"
}

# lk_certbot_list_all_domains [DOMAIN...]
function lk_certbot_list_all_domains() {
    lk_certbot_list "$@" | cut -f2 | tr ',' '\n'
}

# lk_certbot_install [-w WEBROOT_PATH] DOMAIN...
function lk_certbot_install() {
    local WEBROOT WEBROOT_PATH DOMAIN ERRORS=0 \
        EMAIL=${LK_CERTBOT_EMAIL-${LK_ADMIN_EMAIL-}}
    unset WEBROOT
    [[ ${1-} != -w ]] || { WEBROOT= && WEBROOT_PATH=$2 && shift 2; }
    (($#)) ||
        lk_usage "$FUNCNAME [-w WEBROOT_PATH] DOMAIN..." ||
        return
    lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    [[ -z ${WEBROOT+1} ]] || lk_elevate test -d "$WEBROOT_PATH" ||
        lk_warn "directory not found: $WEBROOT_PATH" || return
    [[ -n $EMAIL ]] || lk_warn "email address not set" || return
    lk_is_email "$EMAIL" || lk_warn "invalid email address: $EMAIL" || return
    [[ -n ${_LK_CERTBOT_IGNORE_DNS-} ]] || {
        local IFS=' '
        lk_tty_print "Checking DNS"
        lk_tty_detail "Resolving $(lk_plural $# domain):" "$*"
        for DOMAIN in "$@"; do
            lk_node_is_host "$DOMAIN" ||
                lk_tty_error -r "System address not matched:" "$DOMAIN" ||
                ((++ERRORS))
        done
        ((!ERRORS)) || lk_tty_yn "Ignore DNS errors?" N || return
    }
    local IFS=,
    lk_tty_run lk_elevate certbot \
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
        ${WEBROOT+--webroot-path} \
        ${WEBROOT+"$WEBROOT_PATH"} \
        --domains "$*" \
        ${LK_CERTBOT_OPTIONS+"${LK_CERTBOT_OPTIONS[@]}"}
}

# lk_certbot_install_asap [-w WEBROOT_PATH] DOMAIN...
function lk_certbot_install_asap() {
    local ARGS=()
    { [[ ${1-} != -w ]] || { ARGS+=("$1" "$2") && shift 2; }; } &&
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
        [[ "${RESOLVED[*]-}" == "${LAST_RESOLVED[*]-}" ]] || {
            ((!DOTS)) || echo >&2
            ((DOTS = 0, CHANGED = 1))
            ((!i)) || lk_tty_log "Change detected at" "$(lk_date_log)"
            LAST_RESOLVED=(${RESOLVED+"${RESOLVED[@]}"})
        }
        [[ -n ${FAILED+1} ]] || break
        ((i && !CHANGED)) ||
            lk_tty_error "System address not matched:" "${FAILED[*]}"
        ((i)) || lk_tty_detail "Checking DNS every 60 seconds"
        [[ ! -t 2 ]] || {
            echo -n . >&2
            ((++DOTS))
        }
        sleep 60
        ((++i))
    done
    _LK_CERTBOT_IGNORE_DNS=1 lk_certbot_install ${ARGS+"${ARGS[@]}"} "$@"
}

# lk_certbot_maybe_install [-w WEBROOT_PATH] DOMAIN...
#
# Provision a Let's Encrypt certificate for the given domains unless:
# - they are covered by an existing certificate, or
# - they don't resolve to the system.
function lk_certbot_maybe_install() {
    local ARGS=() DOMAIN
    { [[ ${1-} != -w ]] || { ARGS+=("$1" "$2") && shift 2; }; } &&
        lk_is_fqdn "$@" || lk_warn "invalid arguments" || return
    ! LK_CERTBOT_INSTALLED=$(lk_certbot_list "$@" | grep .) || return 0
    lk_test lk_node_is_host "$@" || return 0
    _LK_CERTBOT_IGNORE_DNS=1 lk_certbot_install ${ARGS+"${ARGS[@]}"} "$@" &&
        LK_CERTBOT_INSTALLED=$(lk_certbot_list "$@" | grep .)
}

# lk_certbot_register_deploy_hook COMMAND [ARG...] -- DOMAIN...
#
# Register a command to run whenever Certbot renews or installs a certificate
# for the given domains.
function lk_certbot_register_deploy_hook() {
    local LK_SUDO=1 ARGS=("$@") COMMAND=() FILE
    while (($#)); do
        [[ $1 != -- ]] || { shift && break; }
        COMMAND[${#COMMAND[@]}]=$1
        shift
    done
    [[ -n ${COMMAND+1} ]] && (($#)) || lk_warn "invalid arguments" || return
    FILE=/etc/letsencrypt/renewal-hooks/deploy/$(lk_md5 "${ARGS[@]}").sh &&
        lk_install -d -m 00755 "${FILE%/*}" &&
        lk_install -m 00755 "$FILE" &&
        lk_file_replace "$FILE" <<EOF
#!/bin/bash

set -euo pipefail

if comm -23 \\
    <(printf '%s\\n' $(IFS=' ' && echo "$*") | sort) \\
    <(printf '%s\\n' \$RENEWED_DOMAINS | sort) | grep .; then
    exit
fi

$(lk_quote_arr COMMAND)
EOF
}

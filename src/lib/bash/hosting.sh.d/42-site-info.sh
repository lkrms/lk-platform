#!/bin/bash

function _lk_hosting_site_json() {
    local JQ
    lk_assign JQ <<"EOF"
{
  "enabled":                ($siteEnable                | to_bool),
  "domain":                 ($siteDomain),
  "alias_domains":          ($siteAliases               | split(",")),
  "www_enabled":            ($siteDisableWww            | to_bool | not),
  "https_enabled":          ($siteDisableHttps          | to_bool | not),
  "staging_mode_enabled":   ($siteEnableStaging         | to_bool),
  "site_root":              ($siteRoot),
  "site_inode":             ($siteInode                 | to_number),
  "is_child_site":          ($siteIsChild               | to_bool),
  "site_name":              ($siteName),
  "child_name":             ($siteChild                 | maybe_null),
  "owner": {
    "user":                 ($siteUser),
    "group":                ($siteGroup)
  },
  "ssl": {
    "cert_file":            ($siteSslCertFile           | maybe_null),
    "key_file":             ($siteSslKeyFile            | maybe_null),
    "chain_file":           ($siteSslChainFile          | maybe_null)
  },
  "upstream_proxy":         ($siteDownstreamFrom        | maybe_null),
  "upstream_only":          ($siteDownstreamForce       | to_bool),
  "php_fpm": {
    "pool":                 ($sitePhpFpmPool),
    "user":                 ($sitePhpFpmUser),
    "max_children":         ($sitePhpFpmMaxChildren     | to_number),
    "max_requests":         ($sitePhpFpmMaxRequests     | to_number),
    "timeout":              ($sitePhpFpmTimeout         | to_number),
    "opcache_size":         ($sitePhpFpmOpcacheSize     | to_number),
    "admin_settings":       ($sitePhpFpmAdminSettings   | split(",")),
    "settings":             ($sitePhpFpmSettings        | split(",")),
    "env":                  ($sitePhpFpmEnv             | split(",")),
    "php_version":          ($sitePhpVersion)
  },
  "smtp_relay": {
    "host":                 ($siteSmtpRelay             | maybe_null),
    "credentials":          ($siteSmtpCredentials       | maybe_null),
    "senders":              ($siteSmtpSenders           | maybe_split(","))
  },
  "sort_order":             ($siteOrder                 | to_number),
  "settings_file":          ($siteFile)
}
EOF
    lk_jq_var -n 'include "core"; '"$JQ" -- \
        _SITE_CHILD \
        _SITE_DOMAIN \
        _SITE_FILE \
        _SITE_GROUP \
        _SITE_INODE \
        _SITE_IS_CHILD \
        _SITE_NAME \
        _SITE_USER \
        SITE_ALIASES \
        SITE_DISABLE_HTTPS \
        SITE_DISABLE_WWW \
        SITE_DOWNSTREAM_FORCE \
        SITE_DOWNSTREAM_FROM \
        SITE_ENABLE \
        SITE_ENABLE_STAGING \
        SITE_ORDER \
        SITE_PHP_FPM_ADMIN_SETTINGS \
        SITE_PHP_FPM_ENV \
        SITE_PHP_FPM_MAX_CHILDREN \
        SITE_PHP_FPM_MAX_REQUESTS \
        SITE_PHP_FPM_OPCACHE_SIZE \
        SITE_PHP_FPM_POOL \
        SITE_PHP_FPM_SETTINGS \
        SITE_PHP_FPM_TIMEOUT \
        SITE_PHP_FPM_USER \
        SITE_PHP_VERSION \
        SITE_ROOT \
        SITE_SMTP_CREDENTIALS \
        SITE_SMTP_RELAY \
        SITE_SMTP_SENDERS \
        SITE_SSL_CERT_FILE \
        SITE_SSL_CHAIN_FILE \
        SITE_SSL_KEY_FILE
}

# _lk_hosting_list_domains
function _lk_hosting_list_domains() { (
    shopt -s nullglob
    eval "$(lk_get_regex DOMAIN_NAME_LOWER_REGEX)"
    set -- "$LK_BASE"/etc/{lk-platform/,}sites/*.conf
    lk_mapfile INVALID <(((!$#)) || printf '%s\n' "$@" |
        grep -Ev "/$DOMAIN_NAME_LOWER_REGEX\\.conf\$")
    [ -z "${INVALID+1}" ] ||
        lk_tty_list INVALID "Ignored (invalid domain in filename):" \
            file files "$LK_RED"
    printf '%s\n' "$@" |
        sed -En "s/.*\/($DOMAIN_NAME_LOWER_REGEX)\\.conf\$/\1/p" | sort -u
); }

# lk_hosting_list_sites [-e] [-j]
#
# For each configured site, print the fields below (tab-delimited, one site per
# line, sorted by IS_CHILD, ORDER, DOMAIN). If -e is set, limit output to
# enabled sites. If -j is set, print an array of site objects in JSON format
# instead.
#
# 1. DOMAIN
# 2. ENABLED
# 3. SITE_ROOT
# 4. INODE
# 5. OWNER
# 6. IS_CHILD
# 7. PHP_FPM_POOL
# 8. PHP_FPM_USER
# 9. ORDER
# 10. ALL_DOMAINS (sorted, comma-separated)
# 11. DISABLE_HTTPS
# 12. PHP_VERSION
function lk_hosting_list_sites() { (
    declare ENABLED_ONLY=0 JSON=0
    while (($#)); do
        [ "${1-}" != -e ] || ENABLED_ONLY=1
        [ "${1-}" != -j ] || JSON=1
        shift
    done
    eval "$(lk_get_regex HOST_NAME_REGEX LINUX_USERNAME_REGEX)"
    unset IFS
    for DOMAIN in $(_lk_hosting_list_domains); do
        unset "${!SITE_@}" "${!_SITE_@}"
        SH=$(_lk_hosting_site_settings_sh "$DOMAIN") && eval "$SH" &&
            _lk_hosting_site_check_root &&
            _lk_hosting_site_load_settings ||
            lk_warn "unable to load settings: $DOMAIN" || return
        ((!ENABLED_ONLY)) || [[ $SITE_ENABLE == Y ]] || continue
        if ((!JSON)); then
            WWW=
            [[ $SITE_DISABLE_WWW == Y ]] || WWW=,www.$DOMAIN
            DOMAINS=$DOMAIN$WWW${SITE_ALIASES:+,$SITE_ALIASES}
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$DOMAIN" \
                "$SITE_ENABLE" \
                "$SITE_ROOT" \
                "$_SITE_INODE" \
                "$_SITE_USER" \
                "$_SITE_IS_CHILD" \
                "$SITE_PHP_FPM_POOL" \
                "$SITE_PHP_FPM_USER" \
                "$SITE_ORDER" \
                "$DOMAINS" \
                "$SITE_DISABLE_HTTPS" \
                "$SITE_PHP_VERSION"
        else
            _lk_hosting_site_json
        fi
    done | if ((!JSON)); then
        sort -t$'\t' -k6 -k9n -k1
    else
        jq -s 'sort_by(.is_child_site, .sort_order, .domain)'
    fi
); }

#### Reviewed: 2022-01-12

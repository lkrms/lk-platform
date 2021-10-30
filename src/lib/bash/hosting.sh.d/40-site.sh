#!/bin/bash

# _lk_hosting_site_list_known_settings [FORMAT]
#
# Print the names of all known SITE_* settings.
function _lk_hosting_site_list_known_settings() {
    printf "${1:-%s\\n}" \
        SITE_ALIASES \
        SITE_ROOT \
        SITE_ENABLE \
        SITE_ORDER \
        SITE_DISABLE_WWW \
        SITE_DISABLE_HTTPS \
        SITE_ENABLE_STAGING \
        SITE_SSL_CERT_FILE \
        SITE_SSL_KEY_FILE \
        SITE_SSL_CHAIN_FILE \
        SITE_PHP_FPM_POOL \
        SITE_PHP_FPM_USER \
        SITE_PHP_FPM_MAX_CHILDREN \
        SITE_PHP_FPM_MAX_REQUESTS \
        SITE_PHP_FPM_TIMEOUT \
        SITE_PHP_FPM_OPCACHE_SIZE \
        SITE_PHP_FPM_ADMIN_SETTINGS \
        SITE_PHP_FPM_SETTINGS \
        SITE_PHP_FPM_ENV \
        SITE_PHP_VERSION \
        SITE_DOWNSTREAM_FROM \
        SITE_DOWNSTREAM_FORCE \
        SITE_SMTP_RELAY \
        SITE_SMTP_CREDENTIALS \
        SITE_SMTP_SENDERS
}

# _lk_hosting_site_assign_file DOMAIN
#
# Assign the absolute path of the lk-platform site config file for DOMAIN to
# _SITE_FILE.
function _lk_hosting_site_assign_file() {
    local DEFAULT_FILE=$LK_BASE/etc/lk-platform/sites/$1.conf
    _SITE_FILE=$(lk_first_file \
        "$DEFAULT_FILE" \
        "$LK_BASE/etc/sites/$1.conf") || _SITE_FILE=$DEFAULT_FILE
}

# _lk_hosting_site_settings_sh DOMAIN
#
# Print Bash variable assignments for _SITE_DOMAIN, _SITE_FILE, and each SITE_*
# setting for DOMAIN.
#
# Output from this function should be evaluated before calling other
# site-specific _lk_hosting_* functions.
function _lk_hosting_site_settings_sh() { (
    unset "${!SITE_@}"
    _SITE_DOMAIN=${1,,}
    _lk_hosting_site_assign_file "$_SITE_DOMAIN"
    readonly _SITE_DOMAIN _SITE_FILE
    [ ! -e "$_SITE_FILE" ] ||
        . "$_SITE_FILE" || return
    _LK_STACK_DEPTH=1 lk_var_sh_q -a _SITE_DOMAIN _SITE_FILE \
        $({ _lk_hosting_site_list_known_settings &&
            printf '%s\n' "${!SITE_@}"; } | sort -u)
); }

# _lk_hosting_site_check_root
#
# Resolve and validate SITE_ROOT, and set each of the following variables:
# - _SITE_USER
# - _SITE_GROUP
# - _SITE_CHILD
# - _SITE_IS_CHILD
# - _SITE_NAME
function _lk_hosting_site_check_root() {
    lk_var_not_null _SITE_DOMAIN _SITE_FILE ||
        lk_warn "values required: _SITE_DOMAIN _SITE_FILE" || return
    local LK_SUDO=1
    [ -n "${LINUX_USERNAME_REGEX+1}" ] ||
        eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    [ -n "${SITE_ROOT-}" ] &&
        lk_elevate test -d "$SITE_ROOT" &&
        SITE_ROOT=$(lk_elevate realpath "$SITE_ROOT") &&
        _SITE_INODE=$(lk_elevate gnu_stat -c %i "$SITE_ROOT") &&
        _SITE_USER=$(lk_file_owner "$SITE_ROOT") &&
        _SITE_GROUP=$(id -gn "$_SITE_USER") &&
        [[ $SITE_ROOT =~ ^/srv/www/$_SITE_USER(/($LINUX_USERNAME_REGEX))?$ ]] &&
        _SITE_CHILD=${BASH_REMATCH[2]} &&
        _SITE_IS_CHILD=${_SITE_CHILD:+Y} &&
        _SITE_IS_CHILD=${_SITE_IS_CHILD:-N} &&
        [[ ! ${BASH_REMATCH[2]} =~ ^(public_html|log|backup|ssl|\..*)$ ]] &&
        _SITE_NAME=$_SITE_USER${_SITE_CHILD:+_$_SITE_CHILD}-$_SITE_DOMAIN ||
        lk_warn "invalid SITE_ROOT: ${SITE_ROOT-}"
}

# _lk_hosting_site_assign_defaults
#
# Assign default values for some site settings to _SITE_*.
#
# These values should not be saved in site config files.
function _lk_hosting_site_assign_defaults() {
    _SITE_ORDER=0
    _SITE_PHP_FPM_POOL=$_SITE_USER
    if lk_user_in_group adm "$_SITE_USER"; then
        _SITE_PHP_FPM_USER=www-data
    else
        _SITE_PHP_FPM_USER=$_SITE_USER
    fi
    _SITE_PHP_FPM_MAX_CHILDREN=${LK_SITE_PHP_FPM_MAX_CHILDREN:-30}
    _SITE_PHP_FPM_MAX_REQUESTS=${LK_SITE_PHP_FPM_MAX_REQUESTS:-10000}
    _SITE_PHP_FPM_TIMEOUT=${LK_SITE_PHP_FPM_TIMEOUT:-300}
    _SITE_PHP_FPM_OPCACHE_SIZE=${LK_OPCACHE_MEMORY_CONSUMPTION:-128}
    _SITE_PHP_VERSION=$(lk_hosting_php_get_default_version)
}

# _lk_hosting_site_load_settings
#
# Sanitise SITE_* values and assign defaults to any unconfigured settings.
function _lk_hosting_site_load_settings() {
    _lk_hosting_site_assign_defaults || return
    [ -n "${HOST_NAME_REGEX+1}" ] ||
        eval "$(lk_get_regex HOST_NAME_REGEX)"
    SITE_ALIASES=$(IFS=, && lk_string_sort -u \
        "$(lk_string_remove "${SITE_ALIASES,,}" {,www.}"$_SITE_DOMAIN")") &&
        [[ $SITE_ALIASES =~ ^($HOST_NAME_REGEX(,$HOST_NAME_REGEX)*)?$ ]] ||
        lk_warn "invalid aliases: $SITE_ALIASES" || return
    SITE_ENABLE=${SITE_ENABLE:-${LK_SITE_ENABLE:-Y}}
    lk_var_to_bool SITE_ENABLE
    lk_var_to_int SITE_ORDER "$_SITE_ORDER"
    SITE_DISABLE_WWW=${SITE_DISABLE_WWW:-${LK_SITE_DISABLE_WWW:-N}}
    lk_var_to_bool SITE_DISABLE_WWW
    SITE_DISABLE_HTTPS=${SITE_DISABLE_HTTPS:-${LK_SITE_DISABLE_HTTPS:-N}}
    lk_var_to_bool SITE_DISABLE_HTTPS
    if lk_true LK_SITE_ENABLE_STAGING; then
        SITE_ENABLE_STAGING=Y
    else
        SITE_ENABLE_STAGING=${SITE_ENABLE_STAGING:-N}
        lk_var_to_bool SITE_ENABLE_STAGING
    fi
    SITE_PHP_FPM_POOL=${SITE_PHP_FPM_POOL:-$_SITE_PHP_FPM_POOL}
    SITE_PHP_FPM_USER=${SITE_PHP_FPM_USER:-$_SITE_PHP_FPM_USER}
    lk_var_to_int SITE_PHP_FPM_MAX_CHILDREN "$_SITE_PHP_FPM_MAX_CHILDREN"
    ((SITE_PHP_FPM_MAX_CHILDREN > 0)) || SITE_PHP_FPM_MAX_CHILDREN=1
    lk_var_to_int SITE_PHP_FPM_MAX_REQUESTS "$_SITE_PHP_FPM_MAX_REQUESTS"
    ((SITE_PHP_FPM_MAX_REQUESTS >= 0)) || SITE_PHP_FPM_MAX_REQUESTS=0
    lk_var_to_int SITE_PHP_FPM_TIMEOUT "$_SITE_PHP_FPM_TIMEOUT"
    ((SITE_PHP_FPM_TIMEOUT >= 0)) || SITE_PHP_FPM_TIMEOUT=0
    lk_var_to_int SITE_PHP_FPM_OPCACHE_SIZE "$_SITE_PHP_FPM_OPCACHE_SIZE"
    ((SITE_PHP_FPM_OPCACHE_SIZE >= 8)) || SITE_PHP_FPM_OPCACHE_SIZE=8
    SITE_PHP_VERSION=${SITE_PHP_VERSION:-$_SITE_PHP_VERSION}
    [ -d "/etc/php/$SITE_PHP_VERSION/fpm/pool.d" ] ||
        lk_warn "PHP version not available: $SITE_PHP_VERSION"
}

# _lk_hosting_site_load_dynamic_settings
#
# Similar to _lk_hosting_site_load_settings, but for settings where the
# configuration of other sites must be considered.
function _lk_hosting_site_load_dynamic_settings() {
    local IFS=$' \t\n' _SITE_LIST SAME_ROOT SAME_DOMAIN PHP_FPM_POOLS
    lk_mktemp_with _SITE_LIST lk_hosting_list_sites -j || return
    SAME_ROOT=($(jq -r \
        --arg domain "$_SITE_DOMAIN" \
        --arg inode "$_SITE_INODE" '
[ .[] | select(.domain != $domain and .site_inode == ($inode | tonumber)) ] |
  ( .[].domain, if length > 0 then ([ .[].sort_order ] | max) + 1
                else empty end )' <"$_SITE_LIST")) || return
    [ -z "${SAME_ROOT+1}" ] || {
        lk_tty_detail "Other sites with the same site root:" \
            $'\n'"$(printf '%s\n' "${SAME_ROOT[@]:0:${#SAME_ROOT[@]}-1}")" \
            "$LK_BOLD$LK_MAGENTA"
        ((SITE_ORDER > 0)) || SITE_ORDER=${SAME_ROOT[${#SAME_ROOT[@]} - 1]}
    }
    SAME_DOMAIN=($(comm -12 \
        <({ echo "$_SITE_DOMAIN" &&
            { [[ $SITE_DISABLE_WWW == Y ]] || echo "www.$_SITE_DOMAIN"; } &&
            IFS=, && printf '%s\n' $SITE_ALIASES; } | sort -u) \
        <(jq -r \
            --arg domain "$_SITE_DOMAIN" '
.[] | select(.domain != $domain) |
  ( .domain, if .www_enabled then "www.\(.domain)" else empty end,
    .alias_domains[] )' <"$_SITE_LIST" | sort -u))) || return
    [ -z "${SAME_DOMAIN+1}" ] ||
        lk_warn "domains already in use: ${SAME_DOMAIN[*]}" || return
    PHP_FPM_POOLS=$(jq -r --arg pool "$SITE_PHP_FPM_POOL" '
( [ .[] | select(.php_fpm.pool != $pool) | .php_fpm.pool ] |
    unique | length ) + 1' <"$_SITE_LIST") || return
    # Rationale:
    # - `dynamic` responds to bursts in traffic by spawning one child per
    #   second--appropriate for staging servers
    # - `ondemand` spawns children more aggressively--recommended for multi-site
    #   production servers running mod_qos or similar
    # - `static` spawns every child at startup, sacrificing idle capacity for
    #   burst performance--recommended for single-site production servers
    _SITE_PHP_FPM_PM=static
    [ "$PHP_FPM_POOLS" -eq 1 ] ||
        { ! lk_is_true SITE_ENABLE_STAGING &&
            ! lk_is_true LK_SITE_ENABLE_STAGING &&
            _SITE_PHP_FPM_PM=ondemand ||
            _SITE_PHP_FPM_PM=dynamic; }
}

# _lk_hosting_site_write_settings
#
# Write SITE_* variable assignments to the preferred lk-platform site config
# file.
#
# Defaults that shouldn't be saved are commented out, and if a config file for
# the site is found at a deprecated path, it's moved before being updated.
function _lk_hosting_site_write_settings() {
    local REGEX STATUS=0 \
        FILE=$LK_BASE/etc/lk-platform/sites/$_SITE_DOMAIN.conf \
        OLD_FILE=$LK_BASE/etc/sites/$_SITE_DOMAIN.conf
    REGEX=$(_lk_hosting_site_assign_defaults &&
        for SETTING in \
            SITE_PHP_FPM_{POOL,USER,MAX_CHILDREN,MAX_REQUESTS,TIMEOUT,OPCACHE_SIZE} \
            SITE_PHP_VERSION; do
            DEFAULT=_$SETTING
            [[ ${!SETTING-} != "${!DEFAULT-}" ]] || echo "$SETTING"
        done | lk_ere_implode_input) || return
    lk_file_maybe_move "$OLD_FILE" "$FILE" &&
        lk_install -m 00660 -g adm "$FILE" &&
        lk_file_replace -lp "$FILE" \
            "$(lk_var_sh "${!SITE_@}" | sed -E "s/^$REGEX=/#&/")" || STATUS=$?
    return "$STATUS"
}

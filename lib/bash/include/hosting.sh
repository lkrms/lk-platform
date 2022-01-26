#!/bin/bash

lk_require debian git linux provision

# lk_hosting_user_add_admin LOGIN [AUTHORIZED_KEY...]
function lk_hosting_user_add_admin() {
    local _GROUP _HOME
    [ -n "${1-}" ] || lk_usage "\
Usage: $FUNCNAME LOGIN" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    lk_tty_print "Creating administrator account:" "$1"
    lk_tty_detail "Supplementary groups:" "adm, sudo"
    lk_elevate useradd \
        --groups adm,sudo \
        --create-home \
        --shell /bin/bash \
        --key UMASK=027 \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_tty_print "Account created successfully"
    lk_tty_detail "Login group:" "$_GROUP"
    lk_tty_detail "Home directory:" "$_HOME"
    [ $# -lt 2 ] || {
        local LK_SUDO=1 FILE=$_HOME/.ssh/authorized_keys
        lk_install -d -m 00700 -o "$1" -g "$_GROUP" "${FILE%/*}"
        lk_install -m 00600 -o "$1" -g "$_GROUP" "$FILE"
        lk_file_replace "$FILE" "$(lk_echo_args "${@:2}")"
    }
    lk_sudo_add_nopasswd "$1"
}

# lk_hosting_user_add LOGIN
function lk_hosting_user_add() {
    local _GROUP _HOME SKEL
    [ -n "${1-}" ] || lk_usage "\
Usage: $FUNCNAME LOGIN" || return
    [ -d /srv/www ] || lk_warn "directory not found: /srv/www" || return
    ! lk_user_exists "$1" || lk_warn "user already exists: $1" || return
    for SKEL in /etc/skel{.${LK_PATH_PREFIX%-},}; do
        [ -d "$SKEL" ] && break || unset SKEL
    done
    lk_tty_print "Creating user account:" "$1"
    lk_tty_detail "Skeleton directory:" "${SKEL-<none>}"
    lk_elevate useradd \
        --base-dir /srv/www \
        ${SKEL+--skel "$SKEL"} \
        --create-home \
        --shell /bin/bash \
        --key UMASK=027 \
        "$1" &&
        _GROUP=$(id -gn "$1") &&
        _HOME=$(lk_expand_path "~$1") || return
    lk_tty_print "Account created successfully"
    lk_tty_detail "Login group:" "$_GROUP"
    lk_tty_detail "Home directory:" "$_HOME"
}

function _lk_hosting_is_quiet() {
    [ -n "${_LK_HOSTING_QUIET-}" ]
}

function _lk_hosting_check() {
    lk_is_ubuntu &&
        lk_dirs_exist /srv/www/{.tmp,.opcache} ||
        lk_warn "system not configured for hosting"
}

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
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
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
                "$SITE_DISABLE_HTTPS"
        else
            _lk_hosting_site_json
        fi
    done | if ((!JSON)); then
        sort -t$'\t' -k6 -k9n -k1
    else
        jq -s 'sort_by(.is_child_site, .sort_order, .domain)'
    fi
); }

function lk_hosting_migrate_legacy_sites() { (
    shopt -s nullglob
    eval "$(lk_get_regex HOST_NAME_REGEX LINUX_USERNAME_REGEX)"
    lk_mktemp_dir_with PHP_TMP || return
    s=/
    for APACHE_FILE in /etc/apache2/sites-available/*.conf; do
        [[ ! $APACHE_FILE =~ /(000-|$LK_PATH_PREFIX)?default.*\.conf$ ]] ||
            continue
        unset "${!SITE_@}" "${!_SITE_@}"
        SH=$(_lk_hosting_site_list_known_settings '%s=\n' &&
            awk -f "$LK_BASE/lib/awk/hosting/get-site-settings.awk" \
                "$APACHE_FILE") && eval "$SH" || return
        lk_is_fqdn "${_SITE_DOMAIN-}" ||
            lk_warn "invalid ServerName in $APACHE_FILE" || return
        _SITE_DOMAIN=${_SITE_DOMAIN,,}
        _lk_hosting_site_assign_file "$_SITE_DOMAIN"
        [ ! -f "$_SITE_FILE" ] || continue
        _lk_hosting_site_check_root ||
            lk_warn "invalid DocumentRoot in $APACHE_FILE" || return
        VER=${SITE_PHP_VERSION:-$(lk_hosting_php_get_default_version)} &&
            POOL=${SITE_PHP_FPM_POOL:-${_SITE_SITENAME:-$(sed -E \
                's/.*\/([^/]+)\.conf$/\1/' <<<"$APACHE_FILE")}} || return
        FILE=/etc/php/$VER/fpm/pool.d/$POOL.conf
        [ ! -f "$FILE" ] || {
            # Use a copy of the original file in case the pool is serving
            # multiple sites and has already been migrated
            _PHP_FILE=$PHP_TMP/${FILE//"$s"/__}
            [ -f "$_PHP_FILE" ] || cp "$FILE" "$_PHP_FILE" || return
            SH=$(awk -f "$LK_BASE/lib/awk/hosting/get-site-settings.awk" \
                "$APACHE_FILE" "$_PHP_FILE") && eval "$SH" || return
            _SITE_DOMAIN=${_SITE_DOMAIN,,}
        }
        # If max_children and memory_limit match one of the legacy script's
        # default configurations, clear both values; defaults will be applied
        # during provisioning
        MEM=
        [[ ! ,${SITE_PHP_FPM_ADMIN_SETTINGS-}, =~ ,memory_limit=([^,]+), ]] ||
            MEM=${BASH_REMATCH[1]}
        [[ ! ${SITE_PHP_FPM_MAX_CHILDREN-},$MEM =~ ^(8,|50,|30,80M)$ ]] || {
            SITE_PHP_FPM_MAX_CHILDREN=
            SITE_PHP_FPM_ADMIN_SETTINGS=$(sed -E \
                's/(,|^)memory_limit=[^,]*/\1/g; s/,+/,/g; s/(^,+|,+$)//g' \
                <<<"$SITE_PHP_FPM_ADMIN_SETTINGS")
        }
        _SITE_NAME=${APACHE_FILE##*/}
        _SITE_NAME=${_SITE_NAME%.conf}
        SITE_ENABLE=Y
        a2query -q -s "$_SITE_NAME" || SITE_ENABLE=N
        lk_tty_log "Migrating legacy site:" "$_SITE_NAME"
        # If the migration fails, delete the site settings file to ensure
        # another attempt will be made on a subsequent run
        lk_delete_on_exit "$_SITE_FILE" &&
            # Run this again in case get-site-settings changed something
            _lk_hosting_site_check_root &&
            _lk_hosting_site_load_settings &&
            _lk_hosting_site_load_dynamic_settings &&
            _lk_hosting_site_write_settings &&
            lk_hosting_site_provision "$_SITE_DOMAIN" &&
            lk_delete_on_exit_withdraw "$_SITE_FILE" || return
    done
    lk_tty_success "Legacy sites migrated successfully"
); }

function _lk_hosting_httpd_test_config() {
    lk_tty_detail "Testing Apache configuration"
    lk_elevate apachectl configtest ||
        lk_warn "invalid configuration"
}

function lk_hosting_php_get_default_version() { (
    . /etc/lsb-release || return
    case "$DISTRIB_RELEASE" in
    18.04)
        echo "7.2"
        ;;
    20.04)
        echo "7.4"
        ;;
    *)
        false
        ;;
    esac || lk_warn "Ubuntu release not supported: $DISTRIB_RELEASE"
); }

function lk_hosting_php_get_versions() {
    systemctl --full --no-legend --no-pager list-units --all "php*.service" |
        awk '{print $1}' |
        sed -En 's/^php([0-9.]+)-fpm.service$/\1/p' | sort -V
}

# _lk_hosting_php_test_config [PHP_VERSION]
function _lk_hosting_php_test_config() {
    local PHPVER
    PHPVER=${1:-$(lk_hosting_php_get_default_version)} || return
    lk_tty_detail "Testing PHP-FPM $PHPVER configuration"
    lk_elevate "php-fpm$PHPVER" --test ||
        lk_warn "invalid configuration"
}

# _lk_hosting_php_get_settings PREFIX SETTING=VALUE...
#
# Print each PHP setting as a PHP-FPM pool directive. If the same SETTING is
# given more than once, only use the first VALUE.
#
# Example:
#
#     $ _lk_hosting_php_get_settings php_admin_ log_errors=On memory_limit=80M
#     php_admin_flag[log_errors] = On
#     php_admin_value[memory_limit] = 80M
function _lk_hosting_php_get_settings() {
    [ $# -gt 1 ] || lk_warn "no settings" || return
    printf '%s\n' "${@:2}" | awk -F= -v prefix="$1" -v null='""' '
/^[^[:space:]=]+=/ {
  setting = $1
  if(!arr[setting]) {
    sub("^[^=]+=", "")
    arr[setting] = $0 ? $0 : null
    keys[i++] = setting }
  next }
{ status = 2 }
END {
  for (i = 0; i < length(keys); i++) {
    setting = keys[i]
    if(prefix == "env") {
      suffix = "" }
    else if(tolower(arr[setting]) ~ "^(on|true|yes|off|false|no)$") {
      suffix = "flag" }
    else {
      suffix = "value" }
    if (arr[setting] == null) {
      arr[setting] = "" }
    printf("%s%s[%s] = %s\n", prefix, suffix, setting, arr[setting]) }
  exit status }'
}

function _lk_hosting_postfix_provision() {
    local SITES TEMP \
        RELAY=${LK_SMTP_RELAY:+"relay:$LK_SMTP_RELAY"} \
        TRANSPORT=/etc/postfix/sender_transport \
        PASSWD=/etc/postfix/sasl_passwd \
        ACCESS=/etc/postfix/sender_access

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
        lk_postmap "$TEMP" "$TRANSPORT" &&
        lk_postconf_set relayhost "" &&
        lk_postconf_unset sender_dependent_relayhost_maps &&
        lk_postconf_set \
            default_transport "${LK_SMTP_UNKNOWN_SENDER_TRANSPORT:-defer:}" &&
        lk_postconf_set \
            sender_dependent_default_transport_maps "hash:$TRANSPORT" || return

    # 2. Install relay credentials and configure SMTP client parameters
    {
        # Add system-wide SMTP relay credentials if configured
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
    awk -v OFS='\t' \
        '{sub("^@","");print$1,"permit_sender_relay"}' \
        <"$TRANSPORT" >"$TEMP" || return
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

function _lk_hosting_service_apply() {
    while (($#)); do
        if lk_is_bootstrap; then
            lk_systemctl_enable "$1"
        else
            lk_systemctl_reload_or_restart "$1" &&
                lk_systemctl_enable "$1"
        fi &&
            lk_mark_clean "$1" || return
        shift
    done
}

function _lk_hosting_service_disable() {
    while (($#)); do
        if lk_is_bootstrap; then
            lk_systemctl_disable "$1"
        else
            lk_systemctl_disable_now "$1"
        fi &&
            lk_mark_clean "$1" || return
        shift
    done
}

function lk_hosting_apply_config() {
    local IFS=$' \t\n' PHP_VER VER SERVICE APPLY=() DISABLE=()
    lk_tty_log "Checking hosting services"
    _lk_hosting_check &&
        PHP_VER=($(lk_hosting_php_get_versions)) || return
    for VER in ${PHP_VER+"${PHP_VER[@]}"}; do
        lk_tty_print "PHP-FPM $VER"
        SERVICE=php$VER-fpm.service
        if lk_is_dirty "$SERVICE"; then
            if lk_files_exist "/etc/php/$VER/fpm/pool.d"/*.conf; then
                _lk_hosting_php_test_config "$PHPVER" || return
                APPLY+=("$SERVICE")
            else
                DISABLE+=("$SERVICE")
            fi
        fi
    done

    SERVICE=apache2.service
    if lk_systemctl_exists "$SERVICE"; then
        lk_tty_print "Apache 2.4"
        if lk_is_dirty "$SERVICE"; then
            _lk_hosting_httpd_test_config || return
            APPLY+=("$SERVICE")
        fi
    fi

    SERVICE=postfix.service
    if lk_systemctl_exists "$SERVICE"; then
        lk_tty_print "Postfix"
        _lk_hosting_postfix_provision || return
        if lk_is_dirty "$SERVICE"; then
            _lk_hosting_postfix_test_config || return
            APPLY+=("$SERVICE")
        fi
    fi

    _lk_hosting_service_apply ${APPLY+"${APPLY[@]}"} &&
        _lk_hosting_service_disable ${DISABLE+"${DISABLE[@]}"} &&
        lk_tty_success "Site provisioning complete"
}

# lk_hosting_site_configure [options] <DOMAIN> [SITE_ROOT]
function lk_hosting_site_configure() { (
    declare LK_SUDO=1 LK_VERBOSE=${LK_VERBOSE-1} \
        NO_WWW=0 WWW=0 ALIASES=() CLEAR_ALIASES=0 SETTINGS=() SKIP_APPLY=0
    LK_USAGE="\
Usage:
  $FUNCNAME [options] <DOMAIN> [SITE_ROOT]

Options:
  -w                Disable www.<DOMAIN>
  -W                Enable www.<DOMAIN> if currently disabled
  -a <ALIAS>        Add an alternative domain name for the site
  -A                Clear configured aliases
  -s <SETTING>      Add or update a site setting
                    (format: SITE_<SETTING>=[VALUE])
  -n                Skip applying changes to services"
    while getopts ":wWa:As:n" OPT; do
        case "$OPT" in
        w)
            NO_WWW=1
            ;;
        W)
            WWW=1
            ;;
        a)
            lk_is_fqdn "$OPTARG" ||
                lk_usage -e "invalid domain: $OPTARG" || return
            ALIASES[${#ALIASES[@]}]=${OPTARG,,}
            ;;
        A)
            CLEAR_ALIASES=1
            ;;
        s)
            [[ $OPTARG =~ ^(SITE_[a-zA-Z0-9_]+)=(.*) ]] &&
                SETTINGS[${#SETTINGS[@]}]=${BASH_REMATCH[1]}=$(
                    printf '%q\n' "${BASH_REMATCH[2]}"
                ) || lk_usage -e "invalid setting: $OPTARG" || return
            ;;
        n)
            SKIP_APPLY=1
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -ge 1 ] || lk_usage || return
    lk_is_fqdn "$1" || lk_usage -e "invalid domain: $1" || return
    _lk_hosting_check || return
    unset IFS "${!SITE_@}" "${!_SITE_@}"
    SH=$(_lk_hosting_site_settings_sh "${1#www.}") && eval "$SH" || return
    if [ -z "${2-}" ]; then
        [ -f "$_SITE_FILE" ] ||
            lk_warn "file not found: $_SITE_FILE" || return
    else
        [ ! -f "$_SITE_FILE" ] || [ "$SITE_ROOT" -ef "$2" ] ||
            lk_warn "domain already configured in $_SITE_FILE" || return
        SITE_ROOT=$2
    fi
    _lk_hosting_site_check_root &&
        _lk_hosting_site_load_settings || return
    [ -z "${SETTINGS+1}" ] ||
        eval "$(printf '%s\n' "${SETTINGS[@]}")"
    ((!NO_WWW)) || SITE_DISABLE_WWW=Y
    ((!WWW)) || SITE_DISABLE_WWW=N
    ((!CLEAR_ALIASES)) || SITE_ALIASES=
    SITE_ALIASES+=",$(lk_implode_arr , ALIASES)"
    _lk_hosting_site_provision || return
    ((SKIP_APPLY)) || lk_hosting_apply_config
); }

# lk_hosting_site_provision <DOMAIN> [SITE_ROOT]
function lk_hosting_site_provision() { (
    [ -n "${1-}" ] || lk_warn "invalid arguments" || return
    _lk_hosting_check || return
    unset "${!SITE_@}" "${!_SITE_@}"
    SH=$(_lk_hosting_site_settings_sh "$1") && eval "$SH" || return
    [ -f "$_SITE_FILE" ] || [ -n "${2-}" ] ||
        lk_warn "file not found: $_SITE_FILE" || return
    SITE_ROOT=${SITE_ROOT:-${2-}}
    _lk_hosting_site_check_root &&
        _lk_hosting_site_provision
); }

# _lk_hosting_site_provision
#
# 1. Write settings to the site config file.
# 2. Provision directories and files required to serve the site.
# 3. Update Apache and PHP-FPM's config files, marking services "dirty" if their
#    configuration has changed
function _lk_hosting_site_provision() {
    _lk_hosting_site_load_settings &&
        _lk_hosting_site_load_dynamic_settings || return
    _lk_hosting_is_quiet || {
        lk_tty_print "Provisioning site:" "$_SITE_DOMAIN"
        [ -z "$SITE_ALIASES" ] ||
            lk_tty_detail "Aliases:" "${SITE_ALIASES//,/, }"
        lk_tty_detail "Site root:" \
            "$SITE_ROOT$([[ $_SITE_IS_CHILD == N ]] || echo " (child site)")"
    }
    local IFS=$' \t\n' LOG_DIR=$SITE_ROOT/log \
        DOMAINS APACHE ALIAS OLD_SITE_NAME OLD_FILE SSL SSL_FILES SSL_TMP \
        LK_FILE_REPLACE_NO_CHANGE LK_FILE_REPLACE_DECLINED
    lk_install -d -m 00750 -o "$_SITE_USER" -g "$_SITE_GROUP" \
        "$SITE_ROOT"/{,public_html,ssl} || return
    lk_install -d -m 02750 -o root -g "$_SITE_GROUP" "$LOG_DIR" || return
    lk_install -m 00640 -o "$_SITE_USER" -g "$_SITE_GROUP" \
        "$LOG_DIR/cron.log" || return
    DOMAINS=("$_SITE_DOMAIN")
    APACHE=(ServerName "$_SITE_DOMAIN")
    [[ $SITE_DISABLE_WWW == Y ]] || {
        DOMAINS+=("www.$_SITE_DOMAIN")
        APACHE+=(ServerAlias "www.$_SITE_DOMAIN")
    }
    for ALIAS in ${SITE_ALIASES//,/ }; do
        DOMAINS+=("${ALIAS,,}")
        APACHE+=(ServerAlias "${ALIAS,,}")
    done
    [[ $SITE_DISABLE_HTTPS == Y ]] || {
        SSL=1
        # Use a Let's Encrypt certificate if one is available
        IFS=$'\n'
        SSL_FILES=($(IFS=, &&
            lk_certbot_list "${DOMAINS[@]}" 2>/dev/null |
            awk -F$'\t' -v "domains=${DOMAINS[*]}" \
                '!p && $2 == domains {print $4; print $5; p = 1}')) ||
            SSL_FILES=()
        unset IFS
        # If not, use the configured certificate
        [ -n "${SSL_FILES+1}" ] ||
            [ "${SITE_SSL_CERT_FILE:+1}${SITE_SSL_KEY_FILE:+1}" != 11 ] ||
            SSL_FILES=(
                "$SITE_SSL_CERT_FILE"
                "$SITE_SSL_KEY_FILE"
                ${SITE_SSL_CHAIN_FILE:+"$SITE_SSL_CHAIN_FILE"}
            )
        # Failing that, use SITE_ROOT/ssl/DOMAIN.cert, creating it if needed
        lk_files_exist ${SSL_FILES+"${SSL_FILES[@]}"} || {
            SSL_FILES=("$SITE_ROOT/ssl/$_SITE_DOMAIN".{cert,key})
            lk_install -m 00644 -o "$_SITE_USER" -g "$_SITE_GROUP" \
                "${SSL_FILES[0]}" &&
                lk_install -m 00640 -o "$_SITE_USER" -g "$_SITE_GROUP" \
                    "${SSL_FILES[1]}" || return
            lk_files_not_empty "${SSL_FILES[@]}" || {
                [ -n "${LK_SSL_CA-}" ] ||
                    printf '%s\n' "${DOMAINS[@]}" |
                    grep -Ev '\.(test|localhost)$' >/dev/null ||
                    local LK_SSL_CA=$LK_BASE/share/ssl/hosting-CA.cert \
                        LK_SSL_CA_KEY=$LK_BASE/share/ssl/hosting-CA.key
                lk_mktemp_dir_with SSL_TMP \
                    lk_ssl_create_self_signed_cert "${DOMAINS[@]}" || return
                LK_VERBOSE= lk_file_replace -bf \
                    "$SSL_TMP/$_SITE_DOMAIN.cert" "${SSL_FILES[0]}" &&
                    LK_VERBOSE= lk_file_replace -bf \
                        "$SSL_TMP/$_SITE_DOMAIN.key" "${SSL_FILES[1]}" || return
                if [ -z "${LK_SSL_CA-}" ]; then
                    lk_tty_detail \
                        "Adding self-signed certificate to local trust store"
                    lk_ssl_install_ca_certificate "${SSL_FILES[0]}"
                else
                    lk_tty_detail "Checking local trust store"
                    lk_ssl_install_ca_certificate "$LK_SSL_CA"
                fi || return
            }
        }
        SITE_SSL_CERT_FILE=${SSL_FILES[0]}
        SITE_SSL_KEY_FILE=${SSL_FILES[1]}
        [ -n "${SSL_FILES[2]:+1}" ] ||
            SITE_SSL_CHAIN_FILE=
    }
    _lk_hosting_site_write_settings || return
    ! lk_is_true SITE_ENABLE_STAGING ||
        APACHE+=(Use Staging)
    [ -z "${SITE_DOWNSTREAM_FROM-}" ] || {
        MACRO=${SITE_DOWNSTREAM_FROM,,}
        PARAMS=
        case "$MACRO" in
        cloudflare) ;;
        *)
            eval "$(lk_get_regex IP_OPT_PREFIX_REGEX HTTP_HEADER_NAME)"
            REGEX="$IP_OPT_PREFIX_REGEX"
            REGEX="($HTTP_HEADER_NAME):($REGEX(,$REGEX)*)"
            [[ $SITE_DOWNSTREAM_FROM =~ ^$REGEX$ ]] ||
                lk_warn "invalid SITE_DOWNSTREAM_FROM: $SITE_DOWNSTREAM_FROM" ||
                return
            MACRO=proxy
            PARAMS=" \"${BASH_REMATCH[2]//,/ }\" ${BASH_REMATCH[1]}"
            ;;
        esac
        lk_is_true SITE_DOWNSTREAM_FORCE &&
            APACHE+=(Use "Require${MACRO^}$PARAMS") ||
            APACHE+=(Use "Trust${MACRO^}$PARAMS")
    }
    [ -z "${_SITE_PHP_FPM_PM-}" ] ||
        # Configure PHP-FPM if this is the first site using this pool
        ! lk_hosting_list_sites | awk \
            -v "d=$_SITE_DOMAIN" \
            -v "p=$SITE_PHP_FPM_POOL" \
            '$7 == p && !f {f = 1; if ($1 == d) s = 1} END {exit 1 - s}' || (
        lk_install -d -m 02750 \
            -o "$SITE_PHP_FPM_USER" -g "$_SITE_GROUP" "/srv/www/.opcache/$SITE_PHP_FPM_POOL"
        lk_install -d -m 02770 \
            -o "$SITE_PHP_FPM_USER" -g "$_SITE_GROUP" "/srv/www/.tmp/$SITE_PHP_FPM_POOL"
        lk_install -m 00640 \
            -o root -g "$_SITE_GROUP" "$LOG_DIR/php$SITE_PHP_VERSION-fpm.access.log"
        lk_install -m 00640 \
            -o "$SITE_PHP_FPM_USER" -g "$_SITE_GROUP" \
            "$LOG_DIR/php$SITE_PHP_VERSION-fpm.error.log" \
            "$LOG_DIR/php$SITE_PHP_VERSION-fpm.xdebug.log"
        SITE_PHP_FPM_PM=${SITE_PHP_FPM_PM:-$_SITE_PHP_FPM_PM}
        PHP_SETTINGS=$(
            IFS=,
            # The numeric form of the error_reporting value below is 4597
            _lk_hosting_php_get_settings php_admin_ \
                opcache.memory_consumption="$SITE_PHP_FPM_OPCACHE_SIZE" \
                error_log="$LOG_DIR/php$SITE_PHP_VERSION-fpm.error.log" \
                ${LK_PHP_ADMIN_SETTINGS-} \
                ${SITE_PHP_FPM_ADMIN_SETTINGS-} \
                opcache.interned_strings_buffer=16 \
                opcache.max_accelerated_files=20000 \
                opcache.validate_timestamps=On \
                opcache.revalidate_freq=0 \
                opcache.file_cache=/srv/www/.opcache/\$pool \
                error_reporting="E_ALL & ~E_WARNING & ~E_NOTICE & ~E_USER_WARNING & ~E_USER_NOTICE & ~E_STRICT & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
                disable_functions="error_reporting" \
                log_errors=On \
                memory_limit=80M
            _lk_hosting_php_get_settings php_ \
                ${LK_PHP_SETTINGS-} \
                ${SITE_PHP_FPM_SETTINGS-} \
                display_errors=Off \
                display_startup_errors=Off \
                upload_max_filesize=24M \
                post_max_size=50M
            _lk_hosting_php_get_settings env \
                TMPDIR=/srv/www/.tmp/\$pool \
                ${SITE_PHP_FPM_ENV-}
        )
        unset LK_FILE_REPLACE_NO_CHANGE LK_FILE_REPLACE_DECLINED
        FILE=/etc/php/$SITE_PHP_VERSION/fpm/pool.d/$SITE_PHP_FPM_POOL.conf
        _FILE=$(DOMAIN=$_SITE_DOMAIN lk_expand_template -e \
            "$LK_BASE/share/php-fpm.d/default-hosting.template.conf")
        lk_install -m 00644 "$FILE" &&
            lk_file_replace -bpi "^$S*(;.*)?\$" -s \
                "s/^$S*([^[:blank:]=]+)$S*=$S*($NS+($S+$NS+)*)$S*\$/\1 = \2/" \
                "$FILE" "$_FILE" ||
            lk_is_true LK_FILE_REPLACE_DECLINED || return
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_mark_dirty "php$SITE_PHP_VERSION-fpm.service"
    )
    if [ -d /etc/apache2/sites-available ]; then
        lk_install -m 00640 \
            -o root -g "$_SITE_GROUP" "$LOG_DIR/error.log" &&
            lk_install -m 00640 \
                -o root -g "$_SITE_GROUP" "$LOG_DIR/access.log" || return
        lk_user_in_group "$_SITE_GROUP" www-data || {
            lk_tty_detail "Adding user 'www-data' to group:" "$_SITE_GROUP"
            lk_elevate usermod --append --groups "$_SITE_GROUP" www-data || return
        }
        FILE=/etc/apache2/sites-available/$_SITE_NAME.conf
        _FILE=$(
            for PORT in "" ${SSL:+443}; do
                _APACHE=("${APACHE[@]}")
                [ -n "$PORT" ] || [ -z "${SSL-}" ] || {
                    _APACHE+=(
                        Use SslRedirect
                    )
                }
                [ -z "${_SITE_PHP_FPM_PM-}" ] || _APACHE+=(
                    Use "PhpFpmVirtualHost${PORT:+Ssl}${_SITE_CHILD:+Child} $_SITE_USER${_SITE_CHILD:+ $_SITE_CHILD}"
                )
                [ -z "$PORT" ] || {
                    _APACHE+=(
                        SSLEngine On
                        SSLCertificateFile "${SSL_FILES[0]}"
                        SSLCertificateKeyFile "${SSL_FILES[1]}"
                    )
                }
                printf '<VirtualHost *:%s>\n' "${PORT:-80}"
                printf '    %s %s\n' "${_APACHE[@]}"
                printf '</VirtualHost>\n'
            done
            [ -z "${_SITE_PHP_FPM_PM-}" ] || {
                printf 'Define fpm_proxy_%s%s %s\n' \
                    "$_SITE_USER" \
                    "${_SITE_CHILD:+/$_SITE_CHILD}/" \
                    "$SITE_PHP_FPM_POOL"
                printf 'Use PhpFpmProxy %s %s %s %s %s\n' \
                    "$SITE_PHP_VERSION" \
                    "$SITE_PHP_FPM_POOL" \
                    "$_SITE_USER" \
                    "${_SITE_CHILD:+/$_SITE_CHILD}/" \
                    "$SITE_PHP_FPM_TIMEOUT"
            }
        ) || return
        OLD_SITE_NAME=${_SITE_NAME%"-$_SITE_DOMAIN"}
        OLD_FILE=/etc/apache2/sites-available/$OLD_SITE_NAME.conf
        [ ! -f "$OLD_FILE" ] || [ -e "$FILE" ] ||
            if a2query -q -s "$OLD_SITE_NAME"; then
                lk_elevate a2dissite "$OLD_SITE_NAME" &&
                    lk_elevate mv -nv "$OLD_FILE" "$FILE"
            else
                lk_elevate mv -nv "$OLD_FILE" "$FILE"
            fi || return
        lk_install -m 00644 "$FILE" &&
            lk_file_replace -bpi "^$S*(#.*)?\$" -s "s/^$S+//" \
                "$FILE" "$_FILE" ||
            lk_is_true LK_FILE_REPLACE_DECLINED || return
        lk_is_true LK_FILE_REPLACE_DECLINED ||
            if lk_is_true SITE_ENABLE && ! a2query -q -s "$_SITE_NAME"; then
                lk_tty_success "Enabling Apache site:" "$_SITE_NAME"
                lk_elevate a2ensite "$_SITE_NAME"
                LK_FILE_REPLACE_NO_CHANGE=0
            elif ! lk_is_true SITE_ENABLE && a2query -q -s "$_SITE_NAME"; then
                lk_tty_warning "Disabling Apache site:" "$_SITE_NAME"
                lk_elevate a2dissite "$_SITE_NAME"
                LK_FILE_REPLACE_NO_CHANGE=0
            fi
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_mark_dirty "apache2.service"
    fi
}

function lk_hosting_site_configure_all() {
    local DOMAINS DOMAIN i=0 STATUS=0
    DOMAINS=($(lk_hosting_list_sites | awk '{print $1}')) || return
    for DOMAIN in ${DOMAINS+"${DOMAINS[@]}"}; do
        lk_tty_log "Checking site $((++i)) of ${#DOMAINS[@]}"
        LK_NO_INPUT=1 \
            lk_hosting_site_provision "$DOMAIN" || STATUS=$?
    done
    [ "$STATUS" -eq 0 ] || lk_warn "one or more sites could not be configured"
}

function lk_hosting_configure_modsecurity() {
    lk_apt_install libapache2-mod-security2 &&
        lk_git_provision_repo -fs \
            -o root:adm \
            -b "${LK_OWASP_CRS_BRANCH:-v3.3/master}" \
            -n "OWASP ModSecurity Core Rule Set" \
            https://github.com/coreruleset/coreruleset.git \
            /opt/coreruleset || return
}

# lk_hosting_configure_backup
function lk_hosting_configure_backup() {
    local LK_SUDO=1 BACKUP_SCHEDULE=${LK_AUTO_BACKUP_SCHEDULE-} \
        AUTO_REBOOT=${LK_AUTO_REBOOT-} \
        AUTO_REBOOT_TIME=${LK_AUTO_REBOOT_TIME-} \
        REGEX INHIBIT_PATH
    REGEX=$(printf '%s\n' "$LK_BASE/lib/hosting/backup-all.sh" \
        "${LK_BASE%/*}/${LK_PATH_PREFIX}platform/lib/hosting/backup-all.sh" |
        sort -u | lk_ere_implode_input -e)
    lk_tty_print "Configuring automatic backups"
    if lk_is_false LK_AUTO_BACKUP; then
        lk_tty_error \
            "Automatic backups are disabled (LK_AUTO_BACKUP=$LK_AUTO_BACKUP)"
        lk_crontab_remove "$REGEX"
    else
        # If LK_AUTO_BACKUP_SCHEDULE is not set, default to "0 1 * * *" (daily
        # at 1 a.m.) unless LK_AUTO_REBOOT is enabled, in which case default to
        # "((REBOOT_MINUTE)) ((REBOOT_HOUR - 1)) * * *" (daily, 1 hour before
        # any automatic reboots)
        [ -n "$BACKUP_SCHEDULE" ] || ! lk_is_true AUTO_REBOOT ||
            [[ ! $AUTO_REBOOT_TIME =~ ^0*([0-9]+):0*([0-9]+)$ ]] ||
            BACKUP_SCHEDULE="${BASH_REMATCH[2]} $(((BASH_REMATCH[1] + 23) % 24)) * * *"
        BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-"0 1 * * *"}
        INHIBIT_PATH=$(command -pv systemd-inhibit) &&
            lk_crontab_apply "$REGEX" "$(printf \
                '%s %s >%q 2>&1 || echo "Scheduled backup failed"' \
                "$BACKUP_SCHEDULE" \
                "$(lk_quote_args "$INHIBIT_PATH" \
                    --what=shutdown \
                    --mode=block \
                    --why="Allow scheduled backup to complete" \
                    "$LK_BASE/lib/hosting/backup-all.sh")" \
                "/var/log/${LK_PATH_PREFIX:-lk-}last-backup.log")"
    fi
}

lk_provide hosting

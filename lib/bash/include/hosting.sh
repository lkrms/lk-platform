#!/bin/bash

lk_include debian git linux provision

# lk_hosting_user_add_admin LOGIN [AUTHORIZED_KEY...]
function lk_hosting_user_add_admin() {
    local _GROUP _HOME
    [ -n "${1-}" ] || lk_usage "\
Usage: $(lk_myself -f) LOGIN" || return
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
Usage: $(lk_myself -f) LOGIN" || return
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

function lk_hosting_service_apply() {
    if lk_is_bootstrap; then
        lk_systemctl_enable "$1"
    elif lk_systemctl_running "$1"; then
        lk_systemctl_reload "$1"
    else
        lk_systemctl_enable_now "$1"
    fi || return
    lk_mark_clean "$1"
}

function lk_hosting_service_disable() {
    if lk_is_bootstrap; then
        lk_systemctl_disable "$1"
    else
        lk_systemctl_disable_now "$1"
    fi || return
    lk_mark_clean "$1"
}

function lk_hosting_php_get_default_version() { (
    . /etc/lsb-release || return
    case "$DISTRIB_RELEASE" in
    16.04)
        echo "7.0"
        ;;
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

# lk_hosting_php_get_settings PREFIX SETTING=VALUE...
function lk_hosting_php_get_settings() {
    [ $# -gt 1 ] || lk_warn "no settings" || return
    lk_echo_args "${@:2}" | awk -F= -v "p=$1" \
        '/^[^[:space:]=]+=/ {o=$1; if(!a[o]){
  sub("^[^=]+=", ""); sub("^$", "\"\""); a[o]=$0; k[i++]=o
}
next}
{e=2}
END{for (i = 0; i < length(k); i++) {o=k[i]; if(p=="env")
  s=""
else if(tolower(a[o]) ~ "^(on|true|yes|off|false|no)$")
  s="flag"
else
  s="value"
sub("^\"\"$", "", a[o])
printf("%s%s[%s] = %s\n", p, s, o, a[o])}
exit e}'
}

# lk_hosting_php_fpm_pool_list [PHP_VERSION]
function lk_hosting_php_fpm_pool_list() { (
    PHPVER=${1:-$(lk_hosting_php_get_default_version)} || return
    shopt -s nullglob
    lk_echo_args "/etc/php/$PHPVER/fpm/pool.d"/*.conf |
        sed -E 's/.*\/([^\]+)\.conf$/\1/'
); }

# lk_hosting_php_fpm_config_test [PHP_VERSION]
function lk_hosting_php_fpm_config_test() {
    local PHPVER
    PHPVER=${1:-$(lk_hosting_php_get_default_version)} || return
    lk_tty_detail "Testing PHP-FPM $PHPVER configuration file"
    lk_files_exist "/etc/php/$PHPVER/fpm/pool.d"/*.conf || return 0
    lk_elevate "php-fpm$PHPVER" --test ||
        lk_warn "invalid configuration: php-fpm$PHPVER"
}

# lk_hosting_php_fpm_config_apply [PHP_VERSION]
function lk_hosting_php_fpm_config_apply() {
    local SKIP_TEST PHPVER
    [ "${1-}" != -s ] || { SKIP_TEST=1 && shift; }
    PHPVER=${1:-$(lk_hosting_php_get_default_version)} || return
    lk_tty_print "Applying settings:" PHP-FPM
    if lk_files_exist "/etc/php/$PHPVER/fpm/pool.d"/*.conf; then
        lk_is_true SKIP_TEST ||
            lk_hosting_php_fpm_config_test "$PHPVER" || return
        lk_hosting_service_apply "php$PHPVER-fpm.service"
    else
        lk_hosting_service_disable "php$PHPVER-fpm.service"
    fi
}

function lk_hosting_httpd_config_test() {
    lk_tty_detail "Testing Apache configuration file syntax"
    lk_elevate apachectl configtest ||
        lk_warn "invalid configuration: apache2"
}

function lk_hosting_httpd_config_apply() {
    local SKIP_TEST
    [ "${1-}" != -s ] || SKIP_TEST=1
    lk_tty_print "Applying settings:" Apache
    lk_is_true SKIP_TEST ||
        lk_hosting_httpd_config_test || return
    lk_hosting_service_apply apache2.service
}

#### BEGIN hosting.sh.d

function _lk_hosting_check() {
    lk_is_ubuntu &&
        lk_dirs_exist /srv/www{,/.tmp,/.opcache} ||
        lk_warn "system not configured for hosting"
}

# _lk_hosting_site_list_settings [FORMAT [EXTRA_SETTING...]]
function _lk_hosting_site_list_settings() {
    local FORMAT=${1:-'%s\n'}
    printf "$FORMAT" \
        SITE_ALIASES \
        SITE_ROOT \
        SITE_ENABLE \
        SITE_ORDER \
        SITE_DISABLE_{WWW,HTTPS} \
        SITE_ENABLE_STAGING \
        SITE_SSL_{CERT,KEY,CHAIN}_FILE \
        SITE_PHP_FPM_{POOL,USER,MAX_CHILDREN,TIMEOUT,OPCACHE_SIZE} \
        SITE_PHP_FPM_{{ADMIN_,}SETTINGS,ENV} \
        SITE_PHP_VERSION \
        SITE_DOWNSTREAM_{FROM,FORCE} \
        "${@:2}"
}

# _lk_hosting_site_check_root
#
# - Resolve and validate SITE_ROOT
# - Set _SITE_USER and _SITE_IS_CHILD from SITE_ROOT's owner and path
# - LINUX_USERNAME_REGEX must be set
function _lk_hosting_site_check_root() {
    [ -n "${LINUX_USERNAME_REGEX:+1}" ] || return
    [ -n "${SITE_ROOT-}" ] &&
        SITE_ROOT=$(lk_elevate realpath "$SITE_ROOT") &&
        _SITE_USER=$(LK_SUDO=1 lk_file_owner "$SITE_ROOT") &&
        [[ $SITE_ROOT =~ ^/srv/www/$_SITE_USER(/$LINUX_USERNAME_REGEX)?$ ]] &&
        _SITE_IS_CHILD=${BASH_REMATCH[1]:+1}
}

# lk_hosting_site_list [-e]
#
# For each configured site, print the fields below (tab-delimited, one site per
# line, sorted by IS_CHILD, ORDER, DOMAIN). If -e is set, limit output to
# enabled sites.
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
function lk_hosting_site_list() { (
    unset ENABLED
    [ "${1-}" != -e ] || ENABLED=1
    shopt -s nullglob
    eval "$(lk_get_regex DOMAIN_NAME_REGEX LINUX_USERNAME_REGEX)"
    for FILE in "$LK_BASE/etc/sites"/*.conf; do
        [[ $FILE =~ /($DOMAIN_NAME_REGEX)\.conf$ ]] ||
            lk_warn "invalid domain in filename: $FILE" || continue
        DOMAIN=${BASH_REMATCH[1],,}
        unset "${!SITE_@}" "${!_SITE_@}"
        SH=$(
            . "$FILE" && _lk_hosting_site_check_root ||
                lk_warn "invalid settings: $FILE" || return
            SITE_ORDER=${SITE_ORDER:--1}
            SITE_PHP_FPM_POOL=${SITE_PHP_FPM_POOL:-$_SITE_USER}
            [ -n "${SITE_PHP_FPM_USER-}" ] ||
                if lk_user_in_group adm "$_SITE_USER"; then
                    SITE_PHP_FPM_USER=www-data
                else
                    SITE_PHP_FPM_USER=$_SITE_USER
                fi
            lk_get_quoted_var SITE_ENABLE SITE_ROOT SITE_ORDER SITE_ALIASES \
                _SITE_IS_CHILD SITE_PHP_FPM_POOL SITE_PHP_FPM_USER \
                SITE_DISABLE_WWW SITE_DISABLE_HTTPS
        ) && eval "$SH" || continue
        lk_is_true SITE_ENABLE && SITE_ENABLE=Y ||
            { [ -z "${ENABLED-}" ] && SITE_ENABLE=N || continue; }
        lk_is_true _SITE_IS_CHILD && _SITE_IS_CHILD_H=Y || _SITE_IS_CHILD_H=N
        DOMAINS=$({
            IFS=,
            echo "$DOMAIN"
            SITE_DISABLE_WWW=${SITE_DISABLE_WWW:-${LK_SITE_DISABLE_WWW:-N}}
            lk_is_true SITE_DISABLE_WWW ||
                echo "www.$DOMAIN"
            [ -z "$SITE_ALIASES" ] ||
                printf '%s\n' $SITE_ALIASES
        } | sort -u | lk_implode_input ",")
        SITE_DISABLE_HTTPS=${SITE_DISABLE_HTTPS:-${LK_SITE_DISABLE_HTTPS:-N}}
        lk_is_true SITE_DISABLE_HTTPS &&
            SITE_DISABLE_HTTPS=Y || SITE_DISABLE_HTTPS=N
        lk_elevate gnu_stat -L \
            --printf "$DOMAIN\\t$SITE_ENABLE\\t%n\\t%i\\t%U\\t$_SITE_IS_CHILD_H\\t$SITE_PHP_FPM_POOL\\t$SITE_PHP_FPM_USER\\t$SITE_ORDER\\t$DOMAINS\\t$SITE_DISABLE_HTTPS\\n" \
            "$SITE_ROOT" || return
    done | sort -t$'\t' -k6 -k9n -k1
); }

#### END hosting.sh.d

function lk_hosting_site_migrate_legacy() { (
    shopt -s nullglob
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    PHP_TMP=$(lk_mktemp_dir) && lk_delete_on_exit "$PHP_TMP" || return
    s=/
    for APACHE_FILE in /etc/apache2/sites-available/*.conf; do
        [[ ! $APACHE_FILE =~ /(000-|$LK_PATH_PREFIX)?default.*\.conf$ ]] ||
            continue
        unset "${!SITE_@}" "${!_SITE_@}"
        eval "$(_lk_hosting_site_list_settings '%s=\n')"
        SH=$(awk -f "$LK_BASE/lib/awk/hosting-get-site-settings.awk" \
            "$APACHE_FILE") && eval "$SH" || return
        [ -n "${SITE_ROOT-}" ] ||
            lk_warn "no site root in $APACHE_FILE" ||
            return
        _lk_hosting_site_check_root ||
            lk_warn "invalid site root in '$APACHE_FILE': $SITE_ROOT" ||
            return
        DOMAIN=$_SITE_DOMAIN
        ETC_FILE=$LK_BASE/etc/sites/$DOMAIN.conf
        [ ! -f "$ETC_FILE" ] || continue
        PHP_FILE=/etc/php/${SITE_PHP_VERSION:-$(
            lk_hosting_php_get_default_version
        )}/fpm/pool.d || return
        PHP_FILE+=/${SITE_PHP_FPM_POOL:-${_SITE_SITENAME:-${APACHE_FILE##*/}}}
        PHP_FILE=${PHP_FILE%.conf}.conf
        [ ! -f "$PHP_FILE" ] || {
            # Use a copy of the original file in case the pool is serving
            # multiple sites and has already been migrated
            _PHP_FILE=$PHP_TMP/${PHP_FILE//"$s"/__}
            [ -f "$_PHP_FILE" ] || cp "$PHP_FILE" "$_PHP_FILE" || return
            SH=$(awk -f "$LK_BASE/lib/awk/hosting-get-site-settings.awk" \
                "$APACHE_FILE" "$_PHP_FILE") && eval "$SH" || return
        }
        # If no memory_limit has been set and max_children matches one of the
        # legacy script's default values, use the default max_children value
        [[ ! ${SITE_PHP_FPM_MAX_CHILDREN-} =~ ^(50|30)$ ]] ||
            [[ ,$SITE_PHP_FPM_ADMIN_SETTINGS, == *,memory_limit=* ]] ||
            SITE_PHP_FPM_MAX_CHILDREN=${LK_SITE_PHP_FPM_MAX_CHILDREN:-30}
        _SITE_NAME=${APACHE_FILE##*/}
        _SITE_NAME=${_SITE_NAME%.conf}
        SITE_ENABLE=Y
        a2query -q -s "$_SITE_NAME" || SITE_ENABLE=N
        lk_tty_print
        lk_console_log "Migrating legacy site:" "$_SITE_NAME"
        # If the migration fails after creating a new site settings file, delete
        # it to ensure another attempt will be made on a subsequent run
        lk_delete_on_exit "$ETC_FILE" &&
            lk_hosting_site_set_settings "$DOMAIN" &&
            lk_hosting_site_configure "$DOMAIN" &&
            lk_delete_on_exit_withdraw "$ETC_FILE" || return
    done
    lk_console_success "Legacy sites migrated successfully"
    lk_mark_clean "legacy-sites.migration"
); } #### Reviewed: 2021-06-20

# _lk_hosting_site_read_settings DOMAIN
#
# Output variable assignments for _SITE_FILE and any SITE_* variables therein.
function _lk_hosting_site_read_settings() { (
    [ $# -gt 0 ] || lk_warn "no domain" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    unset "${!SITE_@}"
    readonly _SITE_FILE=$LK_BASE/etc/sites/${1,,}.conf
    [ ! -e "$_SITE_FILE" ] || . "$_SITE_FILE" || return
    _LK_STACK_DEPTH=1 lk_get_quoted_var \
        $(_lk_hosting_site_list_settings "" _SITE_FILE "${!SITE_@}" | sort -u)
); } #### Reviewed: 2021-07-12

# _lk_hosting_site_write_settings DOMAIN
function _lk_hosting_site_write_settings() {
    local FILE=$LK_BASE/etc/sites/${1,,}.conf
    lk_install -m 00660 -g adm "$FILE" &&
        lk_file_replace -lp "$FILE" "$(lk_get_shell_var "${!SITE_@}")"
} #### Reviewed: 2021-07-12

# lk_hosting_site_set_settings [-n] DOMAIN
function lk_hosting_site_set_settings() {
    local WRITE=1
    [ "${1-}" != -n ] || { WRITE= && shift; }
    [ $# -gt 0 ] || lk_warn "no domain" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    local LK_SUDO=1 INODE _SITE_LIST SAME_ROOT ALIASES=() SAME_DOMAIN
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    _lk_hosting_site_check_root &&
        INODE=$(lk_elevate gnu_stat -Lc %i "$SITE_ROOT") ||
        lk_warn "invalid SITE_ROOT: ${SITE_ROOT-}" || return
    _SITE_LIST=$(lk_mktemp_file) &&
        lk_delete_on_exit "$_SITE_LIST" &&
        lk_hosting_site_list >"$_SITE_LIST" || return
    SAME_ROOT=$(awk -v "d=${1,,}" -v "i=$INODE" \
        '$1 != d && $4 == i {print $1}' "$_SITE_LIST") || return
    [ -z "$SAME_ROOT" ] || {
        lk_tty_detail "Other sites have the same site root:" \
            $'\n'"$SAME_ROOT" "$LK_BOLD$LK_MAGENTA"
        SAME_ROOT=${SAME_ROOT//$'\n'/$'.conf\n'}.conf
        SITE_ORDER=${SITE_ORDER:-$(IFS=$'\n' &&
            cd "$LK_BASE/etc/sites" && awk -F "[=\"']+" '
BEGIN                   { max = -1 }
$1 == "SITE_ORDER" &&
    $2 ~ /^[0-9]+$/     { max = ($2 > max ? $2 : max) }
END                     { print max + 1 }' $SAME_ROOT)} || return
    }
    local IFS=,
    for ALIAS in $SITE_ALIASES; do
        lk_is_fqdn "$ALIAS" || lk_warn "invalid alias: $ALIAS" || return
        [[ ,$1,www.$1,${ALIASES[*]-}, != *,$ALIAS,* ]] ||
            lk_warn "repeated alias removed: $ALIAS" || continue
        SAME_DOMAIN=$(awk -v "d=${1,,}" -v "a=,$ALIAS," \
            '$1 != d && index("," $10 ",", a) {print $1}' \
            "$_SITE_LIST") || return
        [ -z "$SAME_DOMAIN" ] ||
            lk_warn "alias already in use: $ALIAS" || return
        ALIASES+=("$ALIAS")
    done
    SITE_ALIASES=${ALIASES[*]-}
    unset IFS
    [ -z "$WRITE" ] ||
        _lk_hosting_site_write_settings "$1"
} #### Reviewed: 2021-07-12

function _lk_hosting_site_check_settings() {
    local OLD_SITE_NAME OLD_FILE NEW_FILE PHPVER=${SITE_PHP_VERSION-} PHP_POOLS
    [ -n "${LINUX_USERNAME_REGEX:+1}" ] || return
    [ -n "${SITE_ROOT-}" ] && lk_elevate test -d "$SITE_ROOT" &&
        SITE_ROOT=$(lk_elevate realpath "$SITE_ROOT") ||
        lk_warn "invalid SITE_ROOT: ${SITE_ROOT-}" ||
        return
    _SITE_USER=$(lk_file_owner "$SITE_ROOT") &&
        _SITE_GROUP=$(id -gn "$_SITE_USER") ||
        return
    [[ $SITE_ROOT =~ ^/srv/www/$_SITE_USER(/($LINUX_USERNAME_REGEX))?/?$ ]] &&
        _SITE_CHILD=${BASH_REMATCH[2]} &&
        [[ ! ${BASH_REMATCH[1]} =~ ^/(public_html|log|backup|ssl|\..*)$ ]] ||
        lk_warn "invalid SITE_ROOT for user '$_SITE_USER': $SITE_ROOT" ||
        return
    OLD_SITE_NAME=$_SITE_USER${_SITE_CHILD:+_$_SITE_CHILD}
    OLD_FILE=/etc/apache2/sites-available/$OLD_SITE_NAME.conf
    _SITE_NAME=$OLD_SITE_NAME-$_SITE_DOMAIN
    NEW_FILE=/etc/apache2/sites-available/$_SITE_NAME.conf
    [ ! -f "$OLD_FILE" ] || [ -e "$NEW_FILE" ] || {
        lk_tty_detail "Renaming:" "$OLD_FILE -> $NEW_FILE"
        if a2query -q -s "$OLD_SITE_NAME"; then
            lk_elevate a2dissite "$OLD_SITE_NAME" &&
                lk_elevate mv -v "$OLD_FILE" "$NEW_FILE" &&
                lk_elevate a2ensite "$_SITE_NAME"
        else
            lk_elevate mv -v "$OLD_FILE" "$NEW_FILE"
        fi || return
    }
    _SITE_IS_CHILD_H=${_SITE_CHILD:+yes}
    _SITE_IS_CHILD_H=${_SITE_IS_CHILD_H:-no}
    SITE_ENABLE=${SITE_ENABLE:-${LK_SITE_ENABLE:-Y}}
    SITE_DISABLE_WWW=${SITE_DISABLE_WWW:-${LK_SITE_DISABLE_WWW:-N}}
    SITE_DISABLE_HTTPS=${SITE_DISABLE_HTTPS:-${LK_SITE_DISABLE_HTTPS:-N}}
    SITE_ENABLE_STAGING=${SITE_ENABLE_STAGING:-${LK_SITE_ENABLE_STAGING:-N}}
    # Rationale:
    # - `dynamic` responds to bursts in traffic by spawning one child per
    #   second--appropriate for staging servers
    # - `ondemand` spawns children more aggressively--recommended for multi-site
    #   production servers running mod_qos or similar
    # - `static` spawns every child at startup, sacrificing idle capacity for
    #   burst performance--recommended for single-site production servers
    PHPVER=${PHPVER:-$(lk_hosting_php_get_default_version)}
    if [ -d "/etc/php/$PHPVER/fpm/pool.d" ]; then
        SITE_PHP_FPM_POOL=${SITE_PHP_FPM_POOL:-$_SITE_USER}
        [ -n "${SITE_PHP_FPM_USER-}" ] ||
            if lk_user_in_group adm "$_SITE_USER"; then
                SITE_PHP_FPM_USER=www-data
            else
                SITE_PHP_FPM_USER=$_SITE_USER
            fi
        SITE_PHP_FPM_MAX_CHILDREN=${SITE_PHP_FPM_MAX_CHILDREN:-${LK_SITE_PHP_FPM_MAX_CHILDREN:-30}}
        SITE_PHP_FPM_TIMEOUT=${SITE_PHP_FPM_TIMEOUT:-${LK_SITE_PHP_FPM_TIMEOUT:-300}}
        SITE_PHP_FPM_OPCACHE_SIZE=${SITE_PHP_FPM_OPCACHE_SIZE:-${LK_OPCACHE_MEMORY_CONSUMPTION:-128}}
        SITE_PHP_VERSION=${SITE_PHP_VERSION:-$PHPVER}
        PHP_POOLS=$(($(lk_hosting_site_list |
            cut -f7 | sort -u | wc -l))) || return
        _SITE_PHP_FPM_PM=static
        [ "$PHP_POOLS" -le 1 ] ||
            { ! lk_is_true SITE_ENABLE_STAGING &&
                ! lk_is_true LK_SITE_ENABLE_STAGING &&
                _SITE_PHP_FPM_PM=ondemand ||
                _SITE_PHP_FPM_PM=dynamic; }
    fi
} #### Reviewed: 2021-06-19

# lk_hosting_site_configure [-w] DOMAIN [SITE_ROOT [ALIAS...]]
function lk_hosting_site_configure() { (
    declare LK_SUDO=1 LK_VERBOSE=${LK_VERBOSE-1} NO_WWW= SSL=
    [ "${1-}" != -w ] || { NO_WWW=1 && shift; }
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME [-w] DOMAIN [SITE_ROOT [ALIAS...]]" || return
    _lk_hosting_check || return
    unset IFS "${!SITE_@}" "${!_SITE_@}"
    _SITE_DOMAIN=${1#www.}
    SH=$(_lk_hosting_site_read_settings "$_SITE_DOMAIN") &&
        eval "$SH" || return
    if [ -z "${2-}" ]; then
        [ -f "$_SITE_FILE" ] ||
            lk_warn "file not found: $_SITE_FILE" || return
    else
        [ ! -f "$_SITE_FILE" ] || [ "$SITE_ROOT" -ef "$2" ] ||
            lk_warn "domain already configured in $_SITE_FILE" || return
        SITE_ROOT=$2
    fi
    [ -z "$NO_WWW" ] ||
        SITE_DISABLE_WWW=Y
    SITE_ALIASES=$(printf '%s\n' "${@:3}" ${SITE_ALIASES//,/ } |
        sort -u | lk_implode_input ",")
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    lk_tty_print "Configuring site:" "$_SITE_DOMAIN"
    # TODO: move _lk_hosting_site_check_settings here
    _lk_hosting_site_check_settings &&
        lk_hosting_site_set_settings -n "$_SITE_DOMAIN" || return
    LOG_DIR=$SITE_ROOT/log
    lk_install -d -m 00750 \
        -o "$_SITE_USER" -g "$_SITE_GROUP" "$SITE_ROOT"/{,public_html,ssl} &&
        lk_install -d -m 02750 \
            -o root -g "$_SITE_GROUP" "$LOG_DIR" &&
        lk_install -m 00640 \
            -o "$_SITE_USER" -g "$_SITE_GROUP" "$LOG_DIR/cron.log" || return
    DOMAINS=("$_SITE_DOMAIN")
    APACHE=(ServerName "$_SITE_DOMAIN")
    lk_is_true SITE_DISABLE_WWW || {
        DOMAINS+=("www.$_SITE_DOMAIN")
        APACHE+=(ServerAlias "www.$_SITE_DOMAIN")
    }
    for ALIAS in ${SITE_ALIASES//,/ }; do
        DOMAINS+=("$ALIAS")
        APACHE+=(ServerAlias "$ALIAS")
    done
    DOMAINS=($(printf '%s\n' "${DOMAINS[@]}" | sort -u))
    unset LK_FILE_REPLACE_NO_CHANGE LK_FILE_REPLACE_DECLINED
    lk_is_true SITE_DISABLE_HTTPS || {
        SSL=1
        # Use a Let's Encrypt certificate if one is available
        IFS=$'\n'
        SSL_FILES=($(IFS=, &&
            lk_certbot_list_certificates "${DOMAINS[@]}" 2>/dev/null |
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
                    declare LK_SSL_CA=$LK_BASE/share/ssl/hosting-CA.cert \
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
            unset SITE_SSL_CHAIN_FILE
        _lk_hosting_site_write_settings "$_SITE_DOMAIN" || return
    }
    _SITE_ALIASES=${SITE_ALIASES//,/, }
    lk_tty_detail "Aliases:" "${_SITE_ALIASES:-<none>}"
    lk_tty_detail "User account:" "$LK_BOLD$_SITE_USER$LK_RESET"
    lk_tty_detail "Child site?" "$_SITE_IS_CHILD_H"
    lk_tty_detail "Site name:" "$_SITE_NAME"
    lk_tty_detail "Settings file:" "$_SITE_FILE"
    lk_tty_detail "Site root:" "$SITE_ROOT"
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
        ! lk_hosting_site_list | awk \
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
            lk_hosting_php_get_settings php_admin_ \
                opcache.memory_consumption="$SITE_PHP_FPM_OPCACHE_SIZE" \
                error_log="$LOG_DIR/php$SITE_PHP_VERSION-fpm.error.log" \
                ${LK_PHP_ADMIN_SETTINGS-} \
                ${SITE_PHP_FPM_ADMIN_SETTINGS-} \
                opcache.file_cache=/srv/www/.opcache/\$pool \
                error_reporting="E_ERROR|E_RECOVERABLE_ERROR|E_CORE_ERROR|E_COMPILE_ERROR" \
                log_errors=On \
                memory_limit=80M
            lk_hosting_php_get_settings php_ \
                ${LK_PHP_SETTINGS-} \
                ${SITE_PHP_FPM_SETTINGS-} \
                display_errors=Off \
                display_startup_errors=Off \
                upload_max_filesize=24M \
                post_max_size=50M
            lk_hosting_php_get_settings env \
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
        lk_install -m 00644 "$FILE" &&
            lk_file_replace -bpi "^$S*(#.*)?\$" -s "s/^$S+//" \
                "$FILE" "$_FILE" ||
            lk_is_true LK_FILE_REPLACE_DECLINED || return
        lk_is_true LK_FILE_REPLACE_DECLINED ||
            if lk_is_true SITE_ENABLE && ! a2query -q -s "$_SITE_NAME"; then
                lk_console_success "Enabling Apache site:" "$_SITE_NAME"
                lk_elevate a2ensite "$_SITE_NAME"
                LK_FILE_REPLACE_NO_CHANGE=0
            elif ! lk_is_true SITE_ENABLE && a2query -q -s "$_SITE_NAME"; then
                lk_console_warning "Disabling Apache site:" "$_SITE_NAME"
                lk_elevate a2dissite "$_SITE_NAME"
                LK_FILE_REPLACE_NO_CHANGE=0
            fi
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            lk_mark_dirty "apache2.service"
    fi
); }

function lk_hosting_site_configure_all() {
    local DOMAINS DOMAIN i=0 STATUS=0
    DOMAINS=($(lk_hosting_site_list | awk '{print $1}')) || return
    for DOMAIN in ${DOMAINS[@]+"${DOMAINS[@]}"}; do
        ! ((i++)) || lk_tty_print
        lk_console_log "Checking site $i of ${#DOMAINS[@]}"
        LK_NO_INPUT=1 \
            lk_hosting_site_configure "$DOMAIN" || STATUS=$?
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
    REGEX="($({ lk_escape_ere "\
$LK_BASE/lib/hosting/backup-all.sh" &&
        lk_escape_ere "\
${LK_BASE%/*}/${LK_PATH_PREFIX}platform/lib/hosting/backup-all.sh"; } |
        sort -u | lk_implode_input "|"))"
    lk_tty_print "Configuring automatic backups"
    if lk_is_false LK_AUTO_BACKUP; then
        lk_console_error \
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

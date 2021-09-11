#!/bin/bash

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
        SITE_PHP_FPM_{POOL,USER,MAX_CHILDREN,TIMEOUT,OPCACHE_SIZE} \
        SITE_PHP_FPM_{{ADMIN_,}SETTINGS,ENV} \
        SITE_PHP_VERSION \
        "${@:2}"
} #### Reviewed: 2021-07-12

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
); } #### Reviewed: 2021-07-12

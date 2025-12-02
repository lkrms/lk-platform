#!/usr/bin/env bash

function lk_hosting_php_get_default_version() { (
    . /etc/lsb-release || return
    case "$DISTRIB_RELEASE" in
    18.04)
        echo 7.2
        ;;
    20.04)
        echo 7.4
        ;;
    22.04)
        echo 8.1
        ;;
    24.04)
        echo 8.3
        ;;
    *)
        false
        ;;
    esac || lk_warn "Ubuntu release not supported: $DISTRIB_RELEASE"
); }

function lk_hosting_php_get_versions() {
    basename -a /lib/systemd/system/php*-fpm.service |
        lk_safe_grep -Eo '[0-9][0-9.]*' | sort -V
}

function _lk_hosting_php_check_pools() { (
    shopt -s nullglob extglob
    lk_mktemp_with _SITE_LIST lk_hosting_list_sites || return
    # Work around Bash IDE not parsing extglob syntax properly
    eval 'DREK=(/etc/php/*/fpm/pool.d/!(*.conf|*.orig|*.dpkg-dist))'
    [[ -z ${DREK+1} ]] ||
        lk_elevate rm -fv "${DREK[@]}"
    for PHPVER in $(lk_hosting_php_get_versions); do
        POOLS=(/etc/php/"$PHPVER"/fpm/pool.d/*.conf)
        [[ -n ${POOLS+1} ]] || continue
        POOLS=("${POOLS[@]##*/}")
        POOLS=("${POOLS[@]%.conf}")
        DISABLE=($(comm -23 \
            <(lk_arr POOLS | sort -u) \
            <(awk -v version="$PHPVER" \
                '$2 == "Y" && $12 == version { print $7 }' <"$_SITE_LIST" |
                sort -u))) || return
        [[ -n ${DISABLE+1} ]] || continue
        lk_tty_detail "Disabling inactive PHP-FPM $PHPVER pools:" \
            $'\n'"$(lk_arr DISABLE)"
        for POOL in "${DISABLE[@]}"; do
            lk_elevate rm -v "/etc/php/$PHPVER/fpm/pool.d/$POOL.conf" ||
                return
        done
        lk_mark_dirty "php$PHPVER-fpm.service"
    done
); }

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

#### Reviewed: 2021-10-07

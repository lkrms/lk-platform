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
    lk_sudo_nopasswd_add "$1"
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

#### INCLUDE hosting.sh.d

# lk_hosting_site_configure [options] <DOMAIN> [SITE_ROOT]
function lk_hosting_site_configure() { (
    declare LK_VERBOSE=${LK_VERBOSE-1} \
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
    _lk_hosting_site_assign_settings "${1#www.}" || return
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
    _lk_hosting_site_assign_settings "$1" || return
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
    _lk_hosting_is_quiet ||
        lk_tty_print "Provisioning site:" "$_SITE_DOMAIN"
    _lk_hosting_site_load_settings &&
        _lk_hosting_site_load_dynamic_settings || return
    _lk_hosting_is_quiet || {
        [ -z "$SITE_ALIASES" ] ||
            lk_tty_detail "Aliases:" "${SITE_ALIASES//,/, }"
        lk_tty_detail "Site root:" \
            "$SITE_ROOT$([[ $_SITE_IS_CHILD == N ]] || echo " (child site)")"
    }
    local LK_SUDO=1 IFS=$' \t\n' LOG_DIR=$SITE_ROOT/log \
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
    _lk_hosting_site_write_settings &&
        _lk_hosting_site_cache_settings || return
    ! lk_is_true SITE_ENABLE_STAGING ||
        APACHE+=(Use Staging)
    [[ -z $SITE_DOWNSTREAM_FROM ]] || {
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
    # Configure PHP-FPM if this is the first enabled site using this pool
    [[ $SITE_PHP_VERSION == -1 ]] ||
        ! lk_hosting_list_sites -e | awk \
            -v "d=$_SITE_DOMAIN" \
            -v "v=$SITE_PHP_VERSION" \
            -v "p=$SITE_PHP_FPM_POOL" \
            '$12 == v && $7 == p && !f {f = 1; if ($1 == d) s = 1} END {exit 1 - s}' || (
        lk_install -d -m 02770 -o "$SITE_PHP_FPM_USER" -g "$_SITE_GROUP" \
            "/srv/www/.tmp/$SITE_PHP_VERSION/$SITE_PHP_FPM_POOL" &&
            lk_install -m 00640 -o root -g "$_SITE_GROUP" \
                "$LOG_DIR/php$SITE_PHP_VERSION-fpm.access.log" &&
            lk_install -m 00640 -o "$SITE_PHP_FPM_USER" -g "$_SITE_GROUP" \
                "$LOG_DIR/php$SITE_PHP_VERSION-fpm.error.log" \
                "$LOG_DIR/php$SITE_PHP_VERSION-fpm.xdebug.log"
        SITE_PHP_FPM_PM=${SITE_PHP_FPM_PM:-$_SITE_PHP_FPM_PM}
        PHP_SETTINGS=$(
            IFS=,
            # The numeric form of the error_reporting value below is 4597
            _lk_hosting_php_get_settings php_admin_ \
                opcache.memory_consumption="$SITE_PHP_FPM_OPCACHE_SIZE" \
                opcache.file_cache= \
                memory_limit="${SITE_PHP_FPM_MEMORY_LIMIT}M" \
                error_log="$LOG_DIR/php$SITE_PHP_VERSION-fpm.error.log" \
                ${LK_PHP_ADMIN_SETTINGS-} \
                ${SITE_PHP_FPM_ADMIN_SETTINGS-} \
                user_ini.filename= \
                opcache.interned_strings_buffer=16 \
                opcache.max_accelerated_files=20000 \
                opcache.validate_timestamps=On \
                opcache.revalidate_freq=0 \
                opcache.enable_file_override=On \
                opcache.log_verbosity_level=2 \
                error_reporting="E_ALL & ~E_WARNING & ~E_NOTICE & ~E_USER_WARNING & ~E_USER_NOTICE & ~E_STRICT & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
                disable_functions="error_reporting" \
                log_errors=On
            _lk_hosting_php_get_settings php_ \
                ${LK_PHP_SETTINGS-} \
                ${SITE_PHP_FPM_SETTINGS-} \
                display_errors=Off \
                display_startup_errors=Off \
                upload_max_filesize=24M \
                post_max_size=50M
            _lk_hosting_php_get_settings env \
                TMPDIR="/srv/www/.tmp/$SITE_PHP_VERSION/\$pool" \
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
                [[ -n $PORT ]] || [[ -z ${SSL-} ]] || {
                    _APACHE+=(
                        Use SslRedirect
                    )
                }
                [[ $SITE_PHP_VERSION == -1 ]] || _APACHE+=(
                    Use "PhpFpmVirtualHost${PORT:+Ssl}${_SITE_CHILD:+Child} $_SITE_USER${_SITE_CHILD:+ $_SITE_CHILD}"
                )
                [[ -z $PORT ]] || {
                    _APACHE+=(
                        SSLEngine On
                        SSLCertificateFile "${SSL_FILES[0]}"
                        SSLCertificateKeyFile "${SSL_FILES[1]}"
                    )
                }
                [[ -z $SITE_CANONICAL_DOMAIN ]] ||
                    _APACHE+=(
                        RewriteEngine On
                        RewriteCond "%{HTTP_HOST} !=$_SITE_DOMAIN"
                        RewriteRule "^(.*)\$ http${SSL:+s}://$_SITE_DOMAIN\$1 [R=301,L]"
                    )
                printf '<VirtualHost *:%s>\n' "${PORT:-80}"
                printf '    %s %s\n' "${_APACHE[@]}"
                printf '</VirtualHost>\n'
            done
            [[ $SITE_PHP_VERSION == -1 ]] || {
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

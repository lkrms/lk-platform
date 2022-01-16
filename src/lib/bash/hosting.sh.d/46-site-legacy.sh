#!/bin/bash

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

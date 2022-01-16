#!/bin/bash

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

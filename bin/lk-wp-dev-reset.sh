#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_include provision wordpress

DEACTIVATE_PLUGINS=(
    #
    hide_my_wp
    wordfence
    wp-admin-no-show

    #
    all-in-one-redirection

    #
    zopim-live-chat
)

lk_console_message "Checking WordPress"

# Connect to MySQL
SH=$(lk_wp_db_get_vars) && eval "$SH"
TABLE_PREFIX=$(lk_wp_get_table_prefix)
lk_mysql_write_cnf
lk_mysql_connects "$DB_NAME"

# Retrieve particulars
function get_state() {
    local SH
    SITE_ADDR=$(lk_wp_get_site_address) &&
        SH=$(lk_uri_parts "$SITE_ADDR" _HOST) &&
        eval "$SH" || lk_die "unable to retrieve site address"
    SITE_HOST=$_HOST
    [[ $SITE_HOST =~ ^(www[^.]*|local|dev|staging)\.(.+)$ ]] &&
        SITE_DOMAIN=${BASH_REMATCH[2]} ||
        SITE_DOMAIN=$SITE_HOST
    SITE_ROOT=$(lk_wp_get_site_root) &&
        ACTIVE_PLUGINS=($(lk_wp plugin list --status=active --field=name)) &&
        STALE=0
}
get_state

# Check plugins
TO_DEACTIVATE=($(
    comm -12 \
        <(lk_echo_array ACTIVE_PLUGINS | sort -u) \
        <(lk_echo_array DEACTIVATE_PLUGINS | sort -u)
))

if [ ${#TO_DEACTIVATE[@]} -gt 0 ]; then
    lk_echo_array TO_DEACTIVATE | lk_console_detail_list \
        "Production-only $(lk_plural ${#TO_DEACTIVATE[@]} \
            plugin plugins) must be deactivated to continue:"
    lk_confirm "Proceed?" Y || lk_die ""
    lk_wp plugin deactivate "${TO_DEACTIVATE[@]}"
    STALE=1
fi

IP=$(LK_DIG_SERVER=1.1.1.1 lk_hosts_get_records A,AAAA "$SITE_DOMAIN")
if [ -n "$IP" ] && ! lk_node_is_host "$SITE_HOST"; then
    NEW_SITE_ADDR=$(lk_console_read "New site address:" "" \
        -i "http://${SITE_DOMAIN%%.*}.hosting")
    if [ -n "$NEW_SITE_ADDR" ] && [ "$NEW_SITE_ADDR" != "$SITE_ADDR" ]; then
        _LK_WP_QUIET=1 LK_WP_REPLACE=1 LK_WP_REAPPLY=0 LK_WP_FLUSH=0 \
            _LK_WP_REPLACE_COMMAND=wp \
            lk_wp_rename_site "$NEW_SITE_ADDR"
        STALE=1
    fi
fi

lk_is_false STALE ||
    get_state

HOSTS=("$SITE_HOST")
EXTRA_HOST=www.${SITE_HOST#www.}
[ "$EXTRA_HOST" = "$SITE_HOST" ] ||
    HOSTS+=("$EXTRA_HOST")

lk_console_message "Preparing to reset for local development"
ADMIN_EMAIL="admin@$SITE_DOMAIN"
lk_console_detail "Site address:" "$SITE_ADDR"
lk_console_detail "Domain:" "$SITE_DOMAIN"
lk_console_detail "Installed at:" "$SITE_ROOT"
[ ${#ACTIVE_PLUGINS[@]} -eq 0 ] &&
    lk_console_detail "Active plugins:" "<none>" ||
    lk_echo_array ACTIVE_PLUGINS |
    lk_console_detail_list "Active $(
        lk_plural ${#ACTIVE_PLUGINS[@]} \
            "plugin" "plugins (${#ACTIVE_PLUGINS[@]})"
    ):"

lk_console_detail "Salts in wp-config.php will be refreshed"
lk_console_detail "Admin email address will be updated to:" "$ADMIN_EMAIL"
lk_console_detail "User addresses will be updated to:" "user_<ID>@$SITE_DOMAIN"
! lk_wp config has WP_CACHE --type=constant ||
    lk_console_detail "WP_CACHE in wp-config.php will be set to:" "false"
lk_console_detail "wp-mail-smtp will be configured to disable outgoing email"
if lk_wp plugin is-active woocommerce; then
    printf '%s\n' PayPal Stripe eWAY |
        lk_console_detail_list \
            "Test mode will be enabled for known WooCommerce gateways:"
    lk_console_detail "WooCommerce webhooks will be disabled"
fi
lk_console_detail "/etc/hosts will be updated with:" "${HOSTS[*]}"
lk_console_warning "Plugin code will be allowed to run where necessary"

lk_confirm "Proceed?" Y || lk_die ""

lk_console_message "Resetting WordPress for local development"

lk_console_detail "Refreshing salts defined in wp-config.php"
lk_wp config shuffle-salts

lk_console_detail "Updating email addresses"
lk_mysql "$DB_NAME" <<SQL
UPDATE ${TABLE_PREFIX}options
SET option_value = '$(lk_mysql_escape "$ADMIN_EMAIL")'
WHERE option_name IN ('admin_email', 'woocommerce_email_from_address', 'woocommerce_stock_email_recipient');

DELETE
FROM ${TABLE_PREFIX}options
WHERE option_name = 'new_admin_email';

UPDATE ${TABLE_PREFIX}users
SET user_email = CONCAT (
        'user_'
        ,ID
        ,'$(lk_mysql_escape "@$SITE_DOMAIN")'
        )
WHERE ID <> 1;
SQL
lk_wp user update 1 --user_email="$ADMIN_EMAIL" --skip-email
lk_wp user meta update 1 billing_email "$ADMIN_EMAIL"

if lk_wp config has WP_CACHE --type=constant; then
    lk_console_detail "Setting value of WP_CACHE in wp-config.php"
    lk_wp config set WP_CACHE false --type=constant --raw
fi

if ! lk_wp plugin is-installed wp-mail-smtp; then
    lk_console_detail "Installing and activating wp-mail-smtp"
    lk_wp plugin install wp-mail-smtp --activate
elif ! lk_wp plugin is-active wp-mail-smtp; then
    lk_console_detail "Activating wp-mail-smtp"
    lk_wp plugin activate wp-mail-smtp
fi

lk_console_detail "Disabling outgoing email"
lk_wp option patch insert wp_mail_smtp general '{
  "do_not_send": true,
  "am_notifications_hidden": false,
  "uninstall": false
}' --format=json

if lk_wp plugin is-active woocommerce; then
    lk_console_detail "WooCommerce: disabling live payments for known gateways"
    lk_wp option patch update \
        woocommerce_paypal_settings testmode yes
    if lk_wp plugin is-active woocommerce-gateway-stripe; then
        lk_wp option patch update \
            woocommerce_stripe_settings testmode yes
    fi
    if lk_wp plugin is-active woocommerce-gateway-eway; then
        lk_wp option patch update \
            woocommerce_eway_settings testmode yes
    fi

    if wp cli has-command "wc webhook list"; then
        TO_DEACTIVATE=($(
            wp --user=1 wc webhook list --field=id --status=active
            wp --user=1 wc webhook list --field=id --status=paused
        ))
        [ ${#TO_DEACTIVATE[@]} -eq 0 ] || {
            lk_console_detail "WooCommerce: disabling webhooks"
            for WEBHOOK_ID in "${TO_DEACTIVATE[@]}"; do
                wp --user=1 wc webhook update "$WEBHOOK_ID" --status=disabled
            done
        }
    fi
fi

lk_wp_reapply_config
lk_wp_flush

lk_hosts_file_add 127.0.0.1 "${HOSTS[@]}"

lk_console_success "WordPress successfully reset for local development"

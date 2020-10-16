#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2034,SC2207

lk_bin_depth=1 include=wordpress,provision . lk-bash-load.sh || exit

DEACTIVATE_PLUGINS=(
    #
    hide_my_wp
    wordfence
    wp-admin-no-show

    #
    all-in-one-redirection

    #
    w3-total-cache
    wp-rocket

    #
    zopim-live-chat
)

lk_console_message "Checking WordPress"

# Connect to MySQL
DB_NAME="$(lk_wp config get DB_NAME)"
DB_USER="$(lk_wp config get DB_USER)"
DB_PASSWORD="$(lk_wp config get DB_PASSWORD)"
DB_HOST="$(lk_wp config get DB_HOST)"
TABLE_PREFIX="$(lk_wp_get_table_prefix)"
lk_mysql_write_cnf
lk_mysql_connects "$DB_NAME"

# Retrieve particulars
function get_state() {
    local _HOST
    SITE_ADDR=$(lk_wp_get_site_address)
    _HOST=$(lk_uri_parts "$SITE_ADDR" "_HOST") &&
        eval "$_HOST" || lk_die "unable to parse site address: $SITE_ADDR"
    SITE_HOST=$_HOST
    SITE_DOMAIN=$(
        sed -E 's/^(www[^.]*|local|dev|staging)\.(.+)$/\2/' <<<"$_HOST"
    )
    [ -n "$SITE_DOMAIN" ] || SITE_DOMAIN=$_HOST
    SITE_ROOT=$(lk_wp_get_site_root)
    ACTIVE_PLUGINS=($(
        lk_wp plugin list --status=active --field=name | sort | uniq
    ))
    STALE=0
}
get_state

# Check plugins
TO_DEACTIVATE=($(
    [ ${#ACTIVE_PLUGINS[@]} -eq 0 ] ||
        [ ${#DEACTIVATE_PLUGINS[@]} -eq 0 ] ||
        comm -12 \
            <(printf '%s\n' "${ACTIVE_PLUGINS[@]}") \
            <(printf '%s\n' "${DEACTIVATE_PLUGINS[@]}" | sort | uniq)
))

if [ ${#TO_DEACTIVATE[@]} -gt 0 ]; then
    lk_echo_array TO_DEACTIVATE |
        lk_console_detail_list "Production-only $(
            lk_maybe_plural ${#TO_DEACTIVATE[@]} \
                "plugin" "plugins"
        ) must be deactivated to continue:"
    lk_confirm "Proceed?" Y || lk_die
    lk_wp plugin deactivate "${TO_DEACTIVATE[@]}"
    STALE=1
fi

IP="$(LK_DIG_SERVER=1.1.1.1 lk_hosts_get_records A,AAAA "$SITE_DOMAIN")"
if [ -n "$IP" ] && ! lk_node_is_host "$SITE_HOST"; then
    NEW_SITE_ADDR=$(lk_console_read "New site address:" "" \
        -i "http://${SITE_DOMAIN%%.*}.localhost")
    [ -z "$NEW_SITE_ADDR" ] || [ "$NEW_SITE_ADDR" = "$SITE_ADDR" ] || {
        LK_WP_QUIET=1 LK_WP_REPLACE=1 LK_WP_FLUSH=0 \
            lk_wp_rename_site "$NEW_SITE_ADDR" && STALE=1
    }
fi

lk_is_false "$STALE" ||
    get_state

ADMIN_EMAIL="admin@$SITE_DOMAIN"
lk_console_detail "Site address:" "$SITE_ADDR"
lk_console_detail "Domain:" "$SITE_DOMAIN"
lk_console_detail "Installed at:" "$SITE_ROOT"
[ ${#ACTIVE_PLUGINS[@]} -eq 0 ] &&
    lk_console_detail "Active plugins:" "<none>" ||
    lk_echo_array ACTIVE_PLUGINS |
    lk_console_detail_list "Active $(
        lk_maybe_plural ${#ACTIVE_PLUGINS[@]} \
            "plugin" "plugins (${#ACTIVE_PLUGINS[@]})"
    ):"

lk_console_message "Preparing to reset for local development"
lk_console_detail "Salts in wp-config.php will be refreshed"
lk_console_detail "Admin email address will be updated to:" "$ADMIN_EMAIL"
lk_console_detail "User addresses will be updated to:" "user_<ID>@$SITE_DOMAIN"
! lk_wp config has WP_CACHE --type=constant ||
    lk_console_detail "WP_CACHE in wp-config.php will be set to:" "false"
lk_console_detail "wp-mail-smtp will be configured to disable outgoing email"
if lk_wp plugin is-active woocommerce; then
    PLUGIN_CODE=1
    printf '%s\n' \
        "PayPal" \
        "Stripe" \
        "eWAY" |
        lk_console_detail_list \
            "Test mode will be enabled for known WooCommerce gateways:"
    lk_console_detail "Active WooCommerce webhooks will be deleted"
fi
[ "${PLUGIN_CODE:-0}" -eq 0 ] ||
    lk_console_warning0 "Plugin code will be allowed to run where necessary"

lk_confirm "Proceed?" Y || lk_die

lk_console_message "Resetting WordPress for local development"

lk_console_detail "Refreshing salts defined in wp-config.php"
lk_wp config shuffle-salts

lk_console_detail "Updating email addresses"
lk_mysql "$DB_NAME" <<SQL
UPDATE ${TABLE_PREFIX}options
SET option_value = '$ADMIN_EMAIL'
WHERE option_name IN ('admin_email', 'woocommerce_email_from_address', 'woocommerce_stock_email_recipient');

DELETE
FROM ${TABLE_PREFIX}options
WHERE option_name = 'new_admin_email';

UPDATE ${TABLE_PREFIX}users
SET user_email = CONCAT (
        'user_'
        ,ID
        ,'@$SITE_DOMAIN'
        )
WHERE ID <> 1;
SQL
lk_wp user update 1 --user_email="$ADMIN_EMAIL" --skip-email
lk_wp user meta update 1 billing_email "$ADMIN_EMAIL"

if lk_wp config has WP_CACHE --type=constant; then
    lk_console_detail "Setting value of WP_CACHE in wp-config.php"
    lk_wp config set WP_CACHE false --type=constant --raw
fi

lk_console_detail "Checking that wp-mail-smtp is installed and enabled"
if ! lk_wp plugin is-installed wp-mail-smtp; then
    lk_wp plugin install wp-mail-smtp --activate
else
    lk_wp plugin is-active wp-mail-smtp ||
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

    if wp cli has-command 'wc webhook list'; then
        TO_DEACTIVATE=($(
            wp wc webhook list --user=1 --field=id --status=active
        )) || {
            lk_console_error0 "Command failed with exit status $?:" \
                "wp wc webhook list --user=1 --field=id --status=active"
            TO_DEACTIVATE=()
        }
        [ ${#TO_DEACTIVATE[@]} -eq 0 ] || {
            lk_console_detail "WooCommerce: deleting active webhooks"
            for WEBHOOK_ID in "${TO_DEACTIVATE[@]}"; do
                # TODO: deactivate instead?
                wp wc webhook delete "$WEBHOOK_ID" --user=1 --force=true ||
                    lk_die
            done
        }
    fi
fi

lk_wp_flush

lk_console_success "WordPress successfully reset for local development"

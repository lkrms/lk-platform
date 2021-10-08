#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit
lk_include provision wordpress

DEFAULT_DEACTIVATE=(
    #
    hide_my_wp
    wordfence
    wp-admin-no-show

    #
    zopim-live-chat
)

{ lk_wp_get_site_root ||
    cd ~/public_html || true; } &>/dev/null

DEACTIVATE=()
NEW_SITE_ADDR=
INNODB=0
SHUFFLE_SALTS=1
UPDATE_EMAIL=1
DISABLE_EMAIL=1

LK_USAGE="\
Usage: ${0##*/} [OPTION...]

Prepare a local replica of a live WordPress site for staging or development.

Options:
  -d, --dir=PATH            target the WordPress installation at PATH
                            (default: use the current directory if WordPress is
                            installed, ~/public_html otherwise)
  -p, --deactivate=PLUGIN   deactivate the specified WordPress plugin (may be
                            given multiple times)
  -r, --rename=URL          change site address to URL
  -i, --innodb              convert any MyISAM tables to InnoDB
      --no-shuffle-salts    do not refresh salts defined in wp-config.php
      --no-deactivate       clear the default list of plugins to deactivate
                            (does not affect --deactivate)
      --no-anon-email       do not anonymise email addresses
      --no-disable-email    do not use WP Mail SMTP to disable outgoing email

Maintenance mode is enabled during processing."

lk_getopt "d:p:r:i" \
    "dir:,deactivate:,rename:,innodb,no-shuffle-salts,no-deactivate,no-anon-email,no-disable-email"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -d | --dir)
        cd "$1" || lk_warn "invalid directory: $1" || lk_usage
        shift
        ;;
    -p | --deactivate)
        DEACTIVATE+=("$1")
        shift
        ;;
    -r | --rename)
        NEW_SITE_ADDR=$1
        lk_is_uri "$1" || lk_warn "invalid URL: $1" || lk_usage
        shift
        ;;
    -i | --innodb)
        INNODB=1
        ;;
    --no-shuffle-salts)
        SHUFFLE_SALTS=0
        ;;
    --no-deactivate)
        DEFAULT_DEACTIVATE=()
        ;;
    --no-anon-email)
        UPDATE_EMAIL=0
        ;;
    --no-disable-email)
        DISABLE_EMAIL=0
        ;;
    --)
        break
        ;;
    esac
done

lk_tty_print "Checking WordPress"

# Connect to MySQL
lk_tty_detail "Testing MySQL connection"
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
        ACTIVE_PLUGINS=($(
            lk_wp plugin list --status=active --field=name | sort -u
        )) &&
        STALE=0
}
lk_tty_detail "Checking active plugins"
get_state

# Check plugins
TO_DEACTIVATE=($(
    comm -12 \
        <(lk_echo_array ACTIVE_PLUGINS) \
        <(lk_echo_array DEFAULT_DEACTIVATE DEACTIVATE | sort -u)
))

if [ ${#TO_DEACTIVATE[@]} -gt 0 ]; then
    lk_echo_array TO_DEACTIVATE | lk_console_detail_list \
        "$(lk_plural -v TO_DEACTIVATE plugin) to deactivate before continuing:"
    lk_confirm "Proceed?" Y || lk_die ""
    lk_wp plugin deactivate "${TO_DEACTIVATE[@]}"
    STALE=1
fi

if [ -n "$NEW_SITE_ADDR" ] || { IP=$(_LK_DNS_SERVER=1.1.1.1 \
    lk_dns_get_records A,AAAA "$SITE_DOMAIN") && [ -n "$IP" ] &&
    ! lk_node_is_host "$SITE_HOST"; }; then
    [ -n "$NEW_SITE_ADDR" ] ||
        lk_tty_read "New site address:" NEW_SITE_ADDR "" \
            -i "https://${SITE_DOMAIN%%.*}.test"
    if [ -n "$NEW_SITE_ADDR" ] && [ "$NEW_SITE_ADDR" != "$SITE_ADDR" ]; then
        lk_wp_maintenance_enable
        _LK_WP_QUIET=1 LK_WP_REPLACE=1 LK_WP_REAPPLY=0 LK_WP_FLUSH=0 \
            _LK_WP_REPLACE_COMMAND=wp \
            lk_wp_rename_site "$NEW_SITE_ADDR"
        STALE=1
    fi
fi

lk_tty_print "Preparing to reset WordPress for local development"

((!STALE)) || get_state

HOSTS=("$SITE_HOST")
EXTRA_HOST=www.${SITE_HOST#www.}
[ "$EXTRA_HOST" = "$SITE_HOST" ] ||
    HOSTS+=("$EXTRA_HOST")

ADMIN_EMAIL=admin@$SITE_DOMAIN
lk_tty_detail "Site address:" "$SITE_ADDR"
lk_tty_detail "Domain:" "$SITE_DOMAIN"
lk_tty_detail "Installed at:" "$SITE_ROOT"
[ ${#ACTIVE_PLUGINS[@]} -eq 0 ] &&
    lk_tty_detail "Active plugins:" "<none>" ||
    lk_echo_array ACTIVE_PLUGINS |
    lk_console_detail_list "Active $(
        lk_plural ACTIVE_PLUGINS plugin "plugins (${#ACTIVE_PLUGINS[@]})"
    ):"

lk_tty_detail "Maintenance mode will be enabled while processing"
((!SHUFFLE_SALTS)) ||
    lk_tty_detail "Salts in wp-config.php will be refreshed"
((!UPDATE_EMAIL)) || {
    lk_tty_detail "Admin email address will be updated to:" "$ADMIN_EMAIL"
    lk_tty_detail "User addresses will be updated to:" "*_<ID>@$SITE_DOMAIN"
}
((!INNODB)) || {
    ! lk_mysql_innodb_only "$DB_NAME" && lk_tty_detail \
        "MyISAM tables will be converted to InnoDB (TAKE A BACKUP FIRST)" ||
        INNODB=0
}
! lk_wp config has WP_CACHE --type=constant ||
    lk_tty_detail "WP_CACHE will be disabled"
((!DISABLE_EMAIL)) ||
    lk_tty_detail "WP Mail SMTP will be configured to disable outgoing email"
if lk_wp plugin is-active woocommerce; then
    printf '%s\n' PayPal Stripe eWAY |
        lk_console_detail_list \
            "Test mode will be enabled for known WooCommerce gateways:"
    lk_tty_detail "WooCommerce webhooks will be" disabled
fi
lk_require_output -q lk_dns_resolve_names "${HOSTS[@]}" && unset HOSTS ||
    lk_tty_detail "/etc/hosts will be updated with:" "${HOSTS[*]}"
lk_tty_detail "Plugin code will be allowed to run where necessary"

lk_confirm "Proceed?" Y || lk_pass lk_wp_maintenance_maybe_disable || lk_die ""

lk_tty_print "Resetting WordPress for local development"

lk_wp_maintenance_enable

((!SHUFFLE_SALTS)) || {
    lk_tty_detail "Refreshing salts defined in wp-config.php"
    lk_run_detail lk_wp config shuffle-salts
}

((!UPDATE_EMAIL)) || {
    lk_tty_detail "Updating email addresses"
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

DELETE
FROM ${TABLE_PREFIX}postmeta
WHERE meta_key IN ('customer_email', 'gift_receiver_email');

UPDATE ${TABLE_PREFIX}postmeta
SET meta_value = CONCAT (
        'post_'
        ,post_id
        ,'$(lk_mysql_escape "@$SITE_DOMAIN")'
        )
WHERE meta_key IN ('_billing_email');
SQL
    lk_wp user update 1 --user_email="$ADMIN_EMAIL" --skip-email
    lk_wp user meta update 1 billing_email "$ADMIN_EMAIL"
}

((!INNODB)) ||
    _LK_WP_QUIET=1 LK_VERBOSE=1 \
        lk_wp_db_myisam_to_innodb

if lk_wp config has WP_CACHE --type=constant; then
    lk_tty_detail "Disabling WP_CACHE in wp-config.php"
    lk_run_detail lk_wp config set WP_CACHE false --type=constant --raw
fi

((!DISABLE_EMAIL)) || {
    if ! lk_wp plugin is-installed wp-mail-smtp; then
        lk_tty_detail "Installing and activating WP Mail SMTP"
        lk_run_detail lk_wp plugin install wp-mail-smtp --activate
    elif ! lk_wp plugin is-active wp-mail-smtp; then
        lk_tty_detail "Activating WP Mail SMTP"
        lk_run_detail lk_wp plugin activate wp-mail-smtp
    fi

    lk_tty_detail "Disabling outgoing email"
    lk_wp option patch insert wp_mail_smtp general '{
  "do_not_send": true,
  "am_notifications_hidden": false,
  "uninstall": false
}' --format=json
}

if lk_wp plugin is-active woocommerce; then
    lk_tty_detail "WooCommerce: disabling live payments for known gateways"
    lk_run_detail lk_wp option patch update \
        woocommerce_paypal_settings testmode yes
    if lk_wp plugin is-active woocommerce-gateway-stripe; then
        lk_run_detail lk_wp option patch update \
            woocommerce_stripe_settings testmode yes
    fi
    if lk_wp plugin is-active woocommerce-gateway-eway; then
        lk_run_detail lk_wp option patch update \
            woocommerce_eway_settings testmode yes
    fi

    if wp cli has-command "wc webhook list"; then
        TO_DEACTIVATE=($(
            wp --user=1 wc webhook list --field=id --status=active
            wp --user=1 wc webhook list --field=id --status=paused
        ))
        [ ${#TO_DEACTIVATE[@]} -eq 0 ] || {
            lk_tty_detail "WooCommerce: disabling webhooks"
            for WEBHOOK_ID in "${TO_DEACTIVATE[@]}"; do
                lk_run_detail wp --user=1 \
                    wc webhook update "$WEBHOOK_ID" --status=disabled
            done
        }
    fi
fi

lk_wp_reapply_config
lk_wp_flush

[ -z "${HOSTS+1}" ] ||
    lk_hosts_file_add 127.0.0.1 "${HOSTS[@]}"

lk_wp_maintenance_maybe_disable

lk_console_success "WordPress successfully reset for local development"

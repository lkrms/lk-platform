#!/usr/bin/env bash

lk_bin_depth=2 . lk-bash-load.sh || exit
lk_require provision linode

function __usage() {
  cat <<EOF
Provision Amazon SES as an SMTP relay for one or more domains.

Usage:
  ${0##*/} [options] <DOMAIN>...

Options:
  -f, --force       Delete unrecognised SES records from DNS.
  -s, --skip-host   Only configure SES and DNS.
  -k, --insecure    Proceed even if <DOMAIN>'s TLS certificate is invalid.

If a domain is serviced by Linode, WHM or cPanel, records for Amazon SES will be
provisioned automatically.

If DOMAIN has already been verified by Amazon SES and valid lk-platform hosting
metadata can be retrieved from https://<DOMAIN>/php-sysinfo, SMTP credentials
and settings will be deployed to the server by configure-ses-site.sh.

Environment:
  AWS_PROFILE   Must contain the name of an AWS CLI profile with a default
                region and access to Amazon SES (see \`aws help configure\`).
  LINODE_USER   If set, Amazon SES DNS records will be added to any domains
                found in the user's Linode account.
EOF
}

lk_bash_is 4 || lk_die "Bash 4 or higher required"
lk_assert_command_exists aws

FORCE=0
SKIP_HOST=0
CURL_OPTIONS=(-fsSL)

lk_getopt "fsk" "force,skip-host,insecure"
eval "set -- $LK_GETOPT"

while :; do
  OPT=$1
  shift
  case "$OPT" in
  -f | --force)
    FORCE=1
    ;;
  -s | --skip-host)
    SKIP_HOST=1
    ;;
  -k | --insecure)
    CURL_OPTIONS+=("$OPT")
    ;;
  --)
    break
    ;;
  esac
done

lk_is_fqdn "$@" || lk_usage

export AWS_PROFILE=${AWS_PROFILE-${LK_AWS_PROFILE-}}
[ -n "${AWS_PROFILE:+1}" ] || lk_usage -e "AWS_PROFILE not set"

LINODE_USER=${LINODE_USER-${LK_LINODE_USER-}}
unset LINODE
[[ -z ${LINODE_USER:+1} ]] || {
  lk_assert_command_exists linode-cli
  LINODE=
}

AWS_REGION=$(aws configure get region) ||
  lk_usage -e "AWS region not set for profile '$AWS_PROFILE'"

function is_linode() {
  [ -n "${LINODE+1}" ]
}

function get_domain_tsv() {
  local TOKEN
  for TOKEN in "${TOKENS[@]}"; do
    printf '0\t%s\t0\t%s\t%s\t0\t0\t%s\n' \
      "$TOKEN._domainkey" CNAME 0 "$TOKEN.dkim.amazonses.com"
  done
  printf '0\t%s\t0\t%s\t%s\t0\t0\t%s\n' \
    amazonses MX 10 "feedback-smtp.$AWS_REGION.amazonses.com" \
    amazonses TXT 0 "v=spf1 include:amazonses.com ~all"
}

function get_domain_diff() {
  # - Records are matched by `name` and `record_type`
  # - `record_id`, `ttl`, `priority`, `weight` and `port` are left as-is
  # - `target` is updated if necessary
  #
  # 1. record_id
  # 2. name
  # 3. ttl
  # 4. record_type
  # 5. priority
  # 6. weight
  # 7. port
  # 8. target
  "$LK_BASE/lib/awk/tdiff" \
    1,3,5,6,7 2,4 \
    "$1" <(get_domain_tsv)
}

function filter_domain_tsv() {
  awk '
$4 == "CNAME" && $2 ~/\._domainkey$/ && $8 ~ /\.dkim\.amazonses\.com$/ { print }
$4 == "MX"    && $2 == "amazonses"   && $8 ~ /\.amazonses\.com$/       { print }
$4 == "TXT"   && $2 == "amazonses"   && $8 ~ /^v=spf1( |$)/            { print }'
}

function confirm_profile() {
  ((!PROFILE_CONFIRMED)) || return 0
  local PROFILE
  PROFILE=$(tr -Cd -- '-a-zA-Z0-9_' <<<"$AWS_PROFILE") &&
    lk_tty_ynav "${0##*/}/$FUNCNAME/$PROFILE" \
      "Before changes are made, is '$AWS_PROFILE' the correct AWS profile?" Y ||
    lk_die ""
  PROFILE_CONFIRMED=1
}

function maybe_get_ipv4() {
  lk_dns_resolve_name_from_ns "$1" |
    lk_filter_ipv4 |
    head -n1 |
    grep .
}

lk_log_open

{
  unset IDENTITY
  DKIM_KEY_LENGTH=RSA_1024_BIT
  PROFILE_CONFIRMED=0

  ! is_linode ||
    lk_linode_flush_cache

  while (($#)); do
    _DOMAIN=$1
    SES_DOMAIN=$1
    VERIFIED=0
    FROM_VERIFIED=0
    DNS_TYPE=
    DNS_SERVICE=
    shift

    lk_tty_log "Provisioning '$_DOMAIN' with Amazon SES"

    while :; do
      lk_tty_detail "Checking SES for identity:" "$SES_DOMAIN"
      lk_mktemp_with -r IDENTITY \
        aws sesv2 get-email-identity \
        --email-identity "$SES_DOMAIN" 2>/dev/null &&
        lk_tty_log "Amazon SES identity found:" "$SES_DOMAIN" || {
        SES_DOMAIN=${SES_DOMAIN#*.}
        ! lk_is_fqdn "$SES_DOMAIN" || lk_is_tld "$SES_DOMAIN" || continue
        SES_DOMAIN=
      }
      break
    done

    if [[ -z $SES_DOMAIN ]]; then
      confirm_profile
      SES_DOMAIN=$_DOMAIN
      lk_tty_print "Creating Amazon SES identity:" "$SES_DOMAIN"
      lk_mktemp_with -r IDENTITY \
        aws sesv2 create-email-identity \
        --email-identity "$SES_DOMAIN" \
        --dkim-signing-attributes NextSigningKeyLength="$DKIM_KEY_LENGTH"
    fi

    ! jq -e '.VerifiedForSendingStatus' <"$IDENTITY" >/dev/null || {
      lk_tty_success "Identity has been verified by Amazon SES"
      VERIFIED=1
    }

    TOKENS=($(jq -r '.DkimAttributes.Tokens[]' <"$IDENTITY"))
    [ ${#TOKENS[@]} -eq 3 ] ||
      lk_die "unexpected value in .DkimAttributes.Tokens[]"

    FROM_DOMAIN=amazonses.$SES_DOMAIN
    SH=$(jq .MailFromAttributes <"$IDENTITY" | lk_json_sh \
      MAIL_FROM_DOMAIN '.MailFromDomain? // ""' \
      MAIL_FROM_ON_FAILURE '.BehaviorOnMxFailure? // ""' \
      MAIL_FROM_STATUS '.MailFromDomainStatus? // ""') && eval "$SH"

    if [[ $MAIL_FROM_DOMAIN != "$FROM_DOMAIN" ]] ||
      [[ $MAIL_FROM_ON_FAILURE != USE_DEFAULT_VALUE ]]; then
      lk_tty_print "Setting custom MAIL FROM domain for SES identity:" "$SES_DOMAIN"
      aws sesv2 put-email-identity-mail-from-attributes \
        --email-identity "$SES_DOMAIN" \
        --mail-from-domain "$FROM_DOMAIN" \
        --behavior-on-mx-failure USE_DEFAULT_VALUE
    elif [[ $MAIL_FROM_STATUS == SUCCESS ]]; then
      lk_tty_success "Custom MAIL FROM domain has been confirmed by Amazon SES"
      FROM_VERIFIED=1
    fi

    if ((!VERIFIED || !FROM_VERIFIED)); then
      lk_tty_detail "Checking for DNS service:" "$SES_DOMAIN"
      lk_mktemp_with DOMAIN_TSV
      if is_linode &&
        lk_linode_domain_tsv "$SES_DOMAIN" | filter_domain_tsv >"$DOMAIN_TSV"; then
        DNS_TYPE=linode
        DNS_SERVICE=Linode
      elif { CP_NAME=cpanel.$_DOMAIN && CP_IPV4=$(maybe_get_ipv4 "$CP_NAME"); } ||
        { CP_NAME=$_DOMAIN && CP_IPV4=$(maybe_get_ipv4 "$CP_NAME"); }; then
        # Check for access to the domain via WHM first, then via cPanel
        for CP in {"whm,2087,WHM","cpanel,2083,cPanel"},{"$CP_NAME","$CP_IPV4"}; do
          IFS=, read -r CP_TYPE CP_PORT CP_SERVICE CP_HOST <<<"$CP"
          if lk_tcp_is_reachable "$CP_HOST" "$CP_PORT" &&
            "lk_${CP_TYPE}_server_set" -q "$CP_HOST" &&
            "lk_${CP_TYPE}_domain_tsv" "$SES_DOMAIN" | filter_domain_tsv >"$DOMAIN_TSV"; then
            DNS_TYPE=$CP_TYPE
            DNS_SERVICE=$CP_SERVICE
            break
          fi
        done
      fi
    fi

    if [[ -n $DNS_TYPE ]]; then
      for DNS_OP in create update delete; do
        eval "domain_record_${DNS_OP}() { lk_${DNS_TYPE}_domain_record_${DNS_OP} \"\$@\"; }"
      done
      lk_mktemp_with DOMAIN_DIFF get_domain_diff "$DOMAIN_TSV"
      if [[ -s $DOMAIN_DIFF ]]; then
        lk_tty_print "Updating DNS records via $DNS_SERVICE:" "$SES_DOMAIN"
        while IFS=$'\t' read -r ACTION RECORD_ID NAME TTL RECORD_TYPE PRIORITY WEIGHT PORT TARGET; do
          RECORD=$'\n'"$NAME $TTL $RECORD_TYPE $PRIORITY $WEIGHT $PORT $TARGET"
          case "$ACTION" in
          +)
            lk_tty_detail "Adding:" "$RECORD"
            domain_record_create "$SES_DOMAIN" "$NAME" "$TTL" "$RECORD_TYPE" "$PRIORITY" "$WEIGHT" "$PORT" "$TARGET"
            ;;
          =)
            lk_tty_detail "Updating:" "$RECORD"
            domain_record_update "$SES_DOMAIN" "$RECORD_ID" "$NAME" "$TTL" "$RECORD_TYPE" "$PRIORITY" "$WEIGHT" "$PORT" "$TARGET"
            ;;
          -)
            if ((FORCE)); then
              lk_tty_detail "Deleting:" "$RECORD"
              domain_record_delete "$SES_DOMAIN" "$RECORD_ID"
            else
              lk_tty_log "Run again with --force to delete:" "$RECORD"
            fi
            ;;
          esac
        done <"$DOMAIN_DIFF"
      else
        lk_tty_success "No updates to '$_DOMAIN' required"
      fi
    elif ((!VERIFIED || !FROM_VERIFIED)); then
      lk_tty_log "The following DNS records must be visible to SES:" "$(
        for TOKEN in "${TOKENS[@]}"; do
          NAME=$TOKEN._domainkey.$SES_DOMAIN.
          TARGET=$TOKEN.dkim.amazonses.com.
          printf '%s IN CNAME %s\n' "$NAME" "$TARGET"
        done
        NAME=$FROM_DOMAIN.
        printf '%s IN MX %s %s\n' \
          "$NAME" 10 "feedback-smtp.$AWS_REGION.amazonses.com."
        printf '%s IN TXT "%s"\n' \
          "$NAME" "v=spf1 include:amazonses.com ~all"
      )"
    fi

    ((!SKIP_HOST)) || continue

    lk_tty_detail "Checking for lk-platform hosting:" "$_DOMAIN"
    { lk_mktemp_with -r SYSINFO \
      curl "${CURL_OPTIONS[@]}" "https://$_DOMAIN/php-sysinfo" ||
      { (($? == 22)) && lk_die "--skip-host not set and lk-platform not found on host"; }; } &&
      SH=$(lk_json_sh \
        HOST_NAME .hostname \
        HOST_FQDN .fqdn \
        HOST_IP '[.ip_addr[]|select(test(regex.ipPrivateFilter)|not)]' \
        <"$SYSINFO" 2>/dev/null) && eval "$SH" ||
      lk_die "unable to retrieve system information"
    lk_is_fqdn "$HOST_FQDN" ||
      lk_die "host reported invalid FQDN: $HOST_FQDN"

    SMTP_USER=$_DOMAIN@$HOST_FQDN
    [[ $_DOMAIN != "$HOST_FQDN" ]] && [[ $_DOMAIN == "$SES_DOMAIN" ]] ||
      SMTP_USER=${_DOMAIN%".$SES_DOMAIN"}@$SES_DOMAIN

    COMMAND=("$LK_BASE/contrib/hosting/configure-ses-site.sh"
      "${LK_SSH_PREFIX-$LK_PATH_PREFIX}$HOST_NAME"
      "$SMTP_USER"
      "$_DOMAIN"
      "$SES_DOMAIN"
      "${HOST_IP[@]}")

    if ((VERIFIED)); then
      "${COMMAND[@]}"
    else
      lk_tty_print \
        "Run one of the following after Amazon SES verifies $SES_DOMAIN:"
      lk_tty_detail "${0##*/} $_DOMAIN"
      lk_tty_detail "$(COMMAND[0]=${COMMAND##*/} && lk_quote_arr COMMAND)"
    fi

  done

  exit
}

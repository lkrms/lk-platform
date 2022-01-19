#!/usr/bin/env bash

lk_bin_depth=2 . lk-bash-load.sh || exit
lk_require linode

function __usage() {
  cat <<EOF
Provision Amazon SES as an SMTP relay for one or more domains.

Usage:
  ${0##*/} [options] <DOMAIN>...

Options:
  -k, --insecure    Proceed even if <DOMAIN>'s TLS certificate is invalid.

Each DOMAIN must resolve to a hosting server, and https://<DOMAIN>/php-sysinfo
must be reachable.

Environment:
  AWS_PROFILE   Must contain the name of an AWS CLI profile with a default
                region and access to Amazon SES (see \`aws help configure\`).
  LINODE_USER   If set, Amazon SES DNS records will be added to any domains
                found in the user's Linode account.
EOF
}

lk_bash_at_least 4 || lk_die "Bash 4 or higher required"
lk_assert_command_exists aws linode-cli

CURL_OPTIONS=(-fsSL)

lk_getopt "k" "insecure"
eval "set -- $LK_GETOPT"

while :; do
  OPT=$1
  shift
  case "$OPT" in
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

AWS_REGION=$(aws configure get region) ||
  lk_usage -e "AWS region not set for profile '$AWS_PROFILE'"

{
  function is_linode() {
    [ -n "${LINODE+1}" ]
  }

  unset LINODE
  [ -z "${LINODE_USER:+1}" ] || {
    LINODE=
    LINODE_ARGS=(--as-user "$LINODE_USER")
  }

  unset IDENTITY
  DKIM_KEY_LENGTH=RSA_1024_BIT

  ! is_linode ||
    lk_linode_flush_cache

  while (($#)); do
    _DOMAIN=$1
    SES_DOMAIN=$1
    VERIFIED=
    shift

    lk_tty_print "Provisioning '$_DOMAIN' with Amazon SES"

    while :; do
      lk_tty_detail "Checking" "$SES_DOMAIN"
      lk_mktemp_with -r IDENTITY \
        aws sesv2 get-email-identity \
        --email-identity "$SES_DOMAIN" 2>/dev/null &&
        lk_tty_log "Email identity found:" "$SES_DOMAIN" || {
        SES_DOMAIN=${SES_DOMAIN#*.}
        ! lk_is_fqdn "$SES_DOMAIN" || lk_is_tld "$SES_DOMAIN" || continue
        SES_DOMAIN=
      }
      break
    done

    if [ -z "$SES_DOMAIN" ]; then
      SES_DOMAIN=$_DOMAIN
      lk_mktemp_with -r IDENTITY lk_tty_run_detail \
        aws sesv2 create-email-identity \
        --email-identity "$SES_DOMAIN" \
        --dkim-signing-attributes NextSigningKeyLength="$DKIM_KEY_LENGTH"
    fi

    if jq -e '.VerifiedForSendingStatus' <"$IDENTITY" >/dev/null; then

      lk_tty_success "Email identity has been verified by Amazon SES"
      VERIFIED=1

    else

      TOKENS=($(jq -r '.DkimAttributes.Tokens[]' <"$IDENTITY"))
      [ ${#TOKENS[@]} -eq 3 ] ||
        lk_die "unexpected value in .DkimAttributes.Tokens[]"

      # `lk_linode_domain -s` sets DOMAIN and DOMAIN_ID
      if is_linode &&
        lk_linode_domain -s "$SES_DOMAIN" "${LINODE_ARGS[@]}"; then

        lk_mktemp_with RECORDS \
          lk_linode_domain_records "$DOMAIN_ID" "${LINODE_ARGS[@]}"

        for TOKEN in "${TOKENS[@]}"; do

          NAME=$TOKEN._domainkey
          TARGET=$TOKEN.dkim.amazonses.com
          RECORD=$(jq -r --arg name "$NAME" '
[ .[] | select(.type == "CNAME" and .name == $name) ] |
    first // empty | [ .id, .target ] | join(",")' <"$RECORDS") || return

          case "$RECORD" in
          *,"$TARGET")
            lk_tty_detail "CNAME already added:" "$NAME.$DOMAIN"
            continue
            ;;

          *,*)
            lk_tty_run_detail linode-cli "${LINODE_ARGS[@]}" \
              domains records-update \
              --target "$TARGET" \
              "$DOMAIN_ID" "${RECORD%%,*}"
            ;;

          "")
            lk_tty_run_detail linode-cli "${LINODE_ARGS[@]}" \
              domains records-create \
              --type CNAME \
              --name "$NAME" \
              --target "$TARGET" \
              "$DOMAIN_ID"
            ;;

          esac >/dev/null

        done

      else

        lk_tty_detail "The following DNS records must be visible to SES:" \
          "$(for TOKEN in "${TOKENS[@]}"; do
            NAME=$TOKEN._domainkey.$SES_DOMAIN.
            TARGET=$TOKEN.dkim.amazonses.com.
            printf "%s IN CNAME %s\n" "$NAME" "$TARGET"
          done)"

      fi

    fi

    lk_mktemp_with -r SYSINFO lk_tty_run_detail \
      curl "${CURL_OPTIONS[@]}" "https://$_DOMAIN/php-sysinfo" ||
      lk_die "unable to retrieve system information from host: $_DOMAIN"

    SH=$(lk_json_sh \
      HOST_NAME .hostname \
      HOST_FQDN .fqdn \
      HOST_IP '[.ip_addr[]|select(test(regex.ipPrivateFilter)|not)]' \
      <"$SYSINFO") && eval "$SH"
    lk_is_fqdn "$HOST_FQDN" ||
      lk_die "host reported invalid FQDN: $HOST_FQDN"

    SMTP_USER=$_DOMAIN@$HOST_FQDN
    [[ $_DOMAIN != "$HOST_FQDN" ]] && [[ $_DOMAIN == "$SES_DOMAIN" ]] ||
      SMTP_USER=${_DOMAIN%".$SES_DOMAIN"}@$SES_DOMAIN

    lk_tty_run_detail "$LK_BASE/contrib/hosting/configure-ses-site.sh" \
      "${LK_SSH_PREFIX-$LK_PATH_PREFIX}$HOST_NAME" \
      "$SMTP_USER" \
      "$_DOMAIN" \
      "$SES_DOMAIN" \
      "${HOST_IP[@]}"

  done

  exit
}

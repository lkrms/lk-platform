#!/usr/bin/env bash

lk_bin_depth=2 . lk-bash-load.sh || exit

function __usage() {
  cat <<EOF
Configure a hosting server to send email from a verified domain via Amazon SES.

Usage:
  ${0##*/} [options] <SSH_HOST> <USER> <DOMAIN> <SES_DOMAIN> <SOURCE_IP>...

Options:
  -a, --api   Allow API-based sending (in addition to SMTP).

If SSH_HOST is -, the script will exit after printing credentials.

If SES_DOMAIN is -, DOMAIN will be used as the Amazon SES identity.

Example:
  ${0##*/} - domain.com@server.fqdn domain.com - 12.34.56.67

Environment:
  AWS_PROFILE   Must contain the name of an AWS CLI profile with a default
                region and access to Amazon SES (see \`aws help configure\`).
EOF
}

lk_bash_is 4 || lk_die "Bash 4 or higher required"
lk_assert_command_exists aws

ALLOW_API=0

lk_getopt "a" "api"
eval "set -- $LK_GETOPT"

while :; do
  OPT=$1
  shift
  case "$OPT" in
  -a | --api)
    ALLOW_API=1
    ;;
  --)
    break
    ;;
  esac
done

[ $# -ge 5 ] || lk_usage
lk_is_fqdn "$3" || lk_usage -e "invalid domain: $3"
[[ $4 == - ]] || lk_is_fqdn "$4" || lk_usage -e "invalid domain: $4"
lk_is_regex IP_REGEX "${@:5}" &&
  ! printf '%s\n' "${@:5}" |
  lk_grep_regex IP_PRIVATE_FILTER_REGEX >/dev/null ||
  lk_usage -e "invalid source IP"

export AWS_PROFILE=${AWS_PROFILE-${LK_AWS_PROFILE-}}
[ -n "${AWS_PROFILE:+1}" ] || lk_usage -e "AWS_PROFILE not set"

AWS_REGION=$(aws configure get region) ||
  lk_usage -e "AWS region not set for profile '$AWS_PROFILE'"

SSH_HOST=$1
IAM_USER=$2
DOMAIN=${3,,}
SES_DOMAIN=${4,,}
SOURCE_IP=("${@:5}")
[[ $SES_DOMAIN != - ]] ||
  SES_DOMAIN=$DOMAIN

lk_log_start

{
  lk_tty_log "Configuring IAM user '$IAM_USER' for SMTP$(
    ((!ALLOW_API)) || echo " and API"
  ) access to Amazon SES"
  lk_tty_list_detail SOURCE_IP "Source addresses:"

  lk_tty_detail "Getting AWS Account ID"
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')
  ARN_PREFIX=arn:aws:ses:$AWS_REGION:$AWS_ACCOUNT_ID:identity

  lk_tty_detail "Checking Amazon SES email identity:" "$SES_DOMAIN"
  aws sesv2 get-email-identity \
    --email-identity "$SES_DOMAIN" >/dev/null

  lk_tty_detail "Checking for IAM user:" "$IAM_USER"
  { lk_mktemp_with TEMP \
    aws iam get-user \
    --user-name "$IAM_USER" 2>/dev/null &&
    lk_tty_log "IAM user already exists:" "$IAM_USER"; } ||
    { lk_tty_print "Creating IAM user:" "$IAM_USER" &&
      lk_mktemp_with -r TEMP \
        aws iam create-user \
        --user-name "$IAM_USER"; }

  if ((ALLOW_API)); then
    JQ='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendRawEmail"
      ],
      "Resource": $resource,
      "Condition": {
        "ForAnyValue:IpAddress": {
          "aws:SourceIp": $ARGS.positional
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:ListEmailIdentities",
        "ses:GetIdentityVerificationAttributes",
        "ses:GetIdentityDkimAttributes"
      ],
      "Resource": "*",
      "Condition": {
        "ForAnyValue:IpAddress": {
          "aws:SourceIp": $ARGS.positional
        }
      }
    }
  ]
}'
  else
    JQ='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendRawEmail",
      "Resource": $resource,
      "Condition": {
        "ForAnyValue:IpAddress": {
          "aws:SourceIp": $ARGS.positional
        }
      }
    }
  ]
}'
  fi

  POLICY=$(jq -n \
    --arg resource "$ARN_PREFIX/$SES_DOMAIN" \
    "$JQ" \
    --args "${SOURCE_IP[@]}")

  lk_tty_print "Applying 'AmazonSesSendingAccess' policy to IAM user"
  aws iam put-user-policy \
    --user-name "$IAM_USER" \
    --policy-name "AmazonSesSendingAccess" \
    --policy-document "$POLICY"

  lk_tty_detail "Checking AWS access keys for" "$IAM_USER"
  lk_mktemp_with KEYS \
    aws iam list-access-keys \
    --user-name "$IAM_USER"

  KEY_COUNT=$(jq -r '.AccessKeyMetadata | length' <"$KEYS")
  if ((KEY_COUNT > 1)); then
    lk_tty_error "User already has $KEY_COUNT AWS access keys"
    if KEY_ID=$(jq -re \
      '[ .AccessKeyMetadata | sort_by(.CreateDate)[] |
  select(.Status != "Active") ] | last | .AccessKeyId' <"$KEYS"); then
      lk_tty_yn "OK to delete inactive key '$KEY_ID'?" Y || lk_die ""
    else
      KEY_ID=$(jq -re \
        '.AccessKeyMetadata | sort_by(.CreateDate) | last | .AccessKeyId' \
        <"$KEYS")
      lk_tty_yn "OK to delete newest key '$KEY_ID'?" Y || lk_die ""
    fi
    lk_tty_detail "Deleting AWS access key:" "$KEY_ID"
    aws iam delete-access-key \
      --user-name "$IAM_USER" \
      --access-key-id "$KEY_ID"
  fi

  lk_tty_print "Generating AWS access key for" "$IAM_USER"
  lk_mktemp_with NEW_KEY \
    aws iam create-access-key \
    --user-name "$IAM_USER"
  SH=$(lk_json_sh \
    ACCESS_KEY_ID .AccessKey.AccessKeyId \
    SECRET_ACCESS_KEY .AccessKey.SecretAccessKey \
    <"$NEW_KEY") && eval "$SH"
  lk_tty_detail "Converting access key to SMTP credentials"
  SMTP_PASSWORD=$("$LK_BASE/lib/vendor/aws/smtp_credentials_generate.py" \
    "$SECRET_ACCESS_KEY" "$AWS_REGION")
  SMTP_CREDENTIALS=${ACCESS_KEY_ID}:${SMTP_PASSWORD}

  lk_tty_success "AWS access key created"
  lk_tty_pairs_detail -- \
    "Access Key ID" "$ACCESS_KEY_ID" \
    "Secret Access Key" "$SECRET_ACCESS_KEY" \
    "SMTP region" "$AWS_REGION" \
    "SMTP credentials" "$SMTP_CREDENTIALS"

  [[ ${SSH_HOST:--} != - ]] ||
    exit 0

  # Deploy the latest version of lk_hosting_site_configure etc.
  lk_tty_print "Updating hosting server:" "$SSH_HOST"
  "$LK_BASE/contrib/hosting/update-server.sh" "$SSH_HOST"

  function set_site_smtp_settings() {
    export LC_ALL=C
    . /opt/lk-platform/lib/bash/rc.sh &&
      lk_require hosting || return
    local i=0 REGEX="(^|\\.)${DOMAIN//./\\.}\$" _DOMAIN SH
    while read -r _DOMAIN && [ -n "$_DOMAIN" ]; do
      ((++i))
      lk_hosting_site_configure -n \
        -s SITE_SMTP_RELAY="[email-smtp.$AWS_REGION.amazonaws.com]:587" \
        -s SITE_SMTP_CREDENTIALS="$SMTP_CREDENTIALS" \
        -s SITE_SMTP_SENDERS= \
        "$_DOMAIN" || return
    done < <(lk_hosting_list_sites |
      awk -v re="${REGEX//\\/\\\\}" '$1 ~ re { print $1 }')
    if [[ $LK_FQDN =~ $REGEX ]]; then
      ((++i))
      SH=$(lk_settings_getopt \
        --set LK_SMTP_RELAY "[email-smtp.$AWS_REGION.amazonaws.com]:587" \
        --set LK_SMTP_CREDENTIALS "$SMTP_CREDENTIALS" \
        --set LK_SMTP_SENDERS "$(
          [[ $SES_DOMAIN == "$DOMAIN" ]] || SES_DOMAIN+=,@$DOMAIN
          echo "@$SES_DOMAIN"
        )") && eval "$SH" &&
        lk_settings_persist "$SH" || return
    fi
    ((i)) || lk_warn "site not found: $DOMAIN" || return
    lk_hosting_apply_config
  }

  lk_mktemp_with SCRIPT
  {
    declare -f set_site_smtp_settings
    declare -p AWS_REGION DOMAIN SES_DOMAIN SMTP_CREDENTIALS
    lk_quote_args set_site_smtp_settings
  } >"$SCRIPT"
  COMMAND=$(lk_quote_args \
    bash -c 't=$(mktemp) && cat >"$t" && sudo -HE bash "$t"')

  ssh -o ControlPath=none -o LogLevel=QUIET "$SSH_HOST" \
    LK_VERBOSE=${LK_VERBOSE-1} "$COMMAND" <"$SCRIPT" || lk_die ""

  lk_tty_detail "Checking AWS access keys for" "$IAM_USER"
  if KEY_ID=$(aws iam list-access-keys \
    --user-name "$IAM_USER" |
    jq -re --arg keyId "$ACCESS_KEY_ID" \
      '.AccessKeyMetadata[] | select(.AccessKeyId != $keyId) | .AccessKeyId') &&
    lk_tty_yn "OK to delete previous key '$KEY_ID'?" Y; then
    lk_tty_detail "Deleting AWS access key:" "$KEY_ID"
    aws iam delete-access-key \
      --user-name "$IAM_USER" \
      --access-key-id "$KEY_ID"
  fi

  exit
}

#!/usr/bin/env bash

lk_bin_depth=2 . lk-bash-load.sh || exit

function __usage() {
  cat <<EOF
Configure a hosting server to send email from the given domain via Amazon SES.

Usage:
  ${0##*/} <SSH_HOST> <SMTP_USER> <DOMAIN> <SES_DOMAIN> <SOURCE_IP>...

If <SES_DOMAIN> is -, its value is taken from DOMAIN.

Environment:
  AWS_PROFILE   Must contain the name of an AWS CLI profile with a default
                region and access to Amazon SES (see \`aws help configure\`).
EOF
}

lk_bash_at_least 4 || lk_die "Bash 4 or higher required"
lk_assert_command_exists aws

lk_getopt
eval "set -- $LK_GETOPT"

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
SMTP_USER=$2
DOMAIN=${3,,}
SES_DOMAIN=${4,,}
SOURCE_IP=("${@:5}")
[[ $SES_DOMAIN != - ]] ||
  SES_DOMAIN=$DOMAIN

lk_log_start

{
  lk_tty_list SOURCE_IP \
    "Configuring IAM user '$SMTP_USER' for SMTP access to Amazon SES from:" \
    "IP address" "IP addresses"

  lk_tty_detail "Getting AWS Account ID"
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')
  ARN_PREFIX=arn:aws:ses:$AWS_REGION:$AWS_ACCOUNT_ID:identity

  lk_tty_detail "Checking Amazon SES email identity:" "$SES_DOMAIN"
  aws sesv2 get-email-identity \
    --email-identity "$SES_DOMAIN" >/dev/null

  { lk_mktemp_with IAM_USER \
    aws iam get-user \
    --user-name "$SMTP_USER" 2>/dev/null &&
    lk_tty_detail "IAM user already exists:" "$SMTP_USER"; } ||
    lk_mktemp_with -r IAM_USER lk_tty_run_detail \
      aws iam create-user \
      --user-name "$SMTP_USER"

  POLICY=$(jq \
    --arg resource "$ARN_PREFIX/$SES_DOMAIN" '
.Statement[0].Resource = $resource |
  .Statement[0]
    .Condition["ForAnyValue:IpAddress"]["aws:SourceIp"] = $ARGS.positional' \
    --args "${SOURCE_IP[@]}" \
    <<<'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendRawEmail",
      "Resource": null,
      "Condition": {
        "ForAnyValue:IpAddress": {
          "aws:SourceIp": null
        }
      }
    }
  ]
}')

  lk_tty_detail "Applying 'AmazonSesSendingAccess' policy to IAM user"
  aws iam put-user-policy \
    --user-name "$SMTP_USER" \
    --policy-name "AmazonSesSendingAccess" \
    --policy-document "$POLICY"

  lk_tty_print "Creating AWS access key for" "$SMTP_USER"
  lk_mktemp_with KEYS \
    aws iam list-access-keys \
    --user-name "$SMTP_USER"

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
    lk_tty_run_detail aws iam delete-access-key \
      --user-name "$SMTP_USER" \
      --access-key-id "$KEY_ID"
  fi

  lk_mktemp_with NEW_KEY lk_tty_run_detail \
    aws iam create-access-key \
    --user-name "$SMTP_USER"
  SH=$(lk_json_sh \
    ACCESS_KEY_ID .AccessKey.AccessKeyId \
    SECRET_ACCESS_KEY .AccessKey.SecretAccessKey \
    <"$NEW_KEY") && eval "$SH"
  lk_tty_success "Access key created:" "$ACCESS_KEY_ID"
  lk_tty_detail \
    "Converting access key to SMTP credentials for region:" "$AWS_REGION"
  SMTP_PASSWORD=$("$LK_BASE/lib/vendor/aws/smtp_credentials_generate.py" \
    "$SECRET_ACCESS_KEY" "$AWS_REGION")
  SMTP_CREDENTIALS=${ACCESS_KEY_ID}:${SMTP_PASSWORD}

  if [[ ${SSH_HOST:--} == - ]]; then
    lk_tty_print "Credentials for Postfix:" "$SMTP_CREDENTIALS"
    exit
  fi

  # Deploy the latest version of lk_hosting_site_configure etc.
  lk_tty_run_detail "$LK_BASE/contrib/hosting/update-server.sh" \
    --no-tls \
    --no-wordpress \
    --no-test \
    "$SSH_HOST"

  function set-site-smtp-settings() {
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
    if [[ $LK_NODE_FQDN =~ $REGEX ]]; then
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
    declare -f set-site-smtp-settings
    declare -p AWS_REGION DOMAIN SES_DOMAIN SMTP_CREDENTIALS
    lk_quote_args set-site-smtp-settings
  } >"$SCRIPT"
  COMMAND=$(lk_quote_args \
    bash -c 't=$(mktemp) && cat >"$t" && sudo -HE bash "$t"')

  ssh -o ControlPath=none -o LogLevel=QUIET "$SSH_HOST" \
    LK_VERBOSE=${LK_VERBOSE-1} "$COMMAND" <"$SCRIPT" || lk_die ""

  if KEY_ID=$(aws iam list-access-keys \
    --user-name "$SMTP_USER" |
    jq -re \
      --arg keyId "$ACCESS_KEY_ID" '
.AccessKeyMetadata[] |
  select(.AccessKeyId != $keyId) | .AccessKeyId') &&
    lk_tty_yn "OK to delete previous key '$KEY_ID'?" Y; then
    lk_tty_run_detail aws iam delete-access-key \
      --user-name "$SMTP_USER" \
      --access-key-id "$KEY_ID"
  fi

  exit
}

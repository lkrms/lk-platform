#!/bin/bash

. lk-bash-load.sh || exit

function __usage() {
  cat <<EOF
Configure a hosting server to send email from the given domain via Amazon SES.

Usage:
  ${0##*/} <SSH_HOST> <SMTP_USER> <DOMAIN> <SOURCE_IP>...

Environment:
  AWS_PROFILE must contain the name of an AWS CLI profile with a default region
  and access to Amazon SES (see \`aws help configure\`).
EOF
}

lk_assert_command_exists aws

lk_getopt
eval "set -- $LK_GETOPT"

[ $# -ge 4 ] || lk_usage
lk_is_fqdn "$3" || lk_usage -e "invalid domain: $3"
lk_is_regex IP_REGEX "${@:4}" &&
  ! printf '%s\n' "${@:4}" |
  lk_grep_regex IP_PRIVATE_FILTER_REGEX >/dev/null ||
  lk_usage -e "invalid source IP"

export AWS_PROFILE=${AWS_PROFILE-${LK_AWS_PROFILE-}}
[ -n "${AWS_PROFILE:+1}" ] || lk_usage -e "AWS_PROFILE not set"

AWS_REGION=$(aws configure get region) ||
  lk_usage -e "AWS region not set for profile '$AWS_PROFILE'"

SSH_HOST=$1
SMTP_USER=$2
DOMAIN=$3
SOURCE_IP=("${@:4}")

{
  lk_tty_list SOURCE_IP \
    "Configuring IAM user '$SMTP_USER' for SMTP access to Amazon SES from:" \
    "IP address" "IP addresses"

  lk_tty_detail "Getting AWS Account ID"
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')
  ARN_PREFIX=arn:aws:ses:$AWS_REGION:$AWS_ACCOUNT_ID:identity

  lk_tty_detail "Checking Amazon SES email identity:" "$DOMAIN"
  aws sesv2 get-email-identity \
    --email-identity "$DOMAIN" >/dev/null

  { lk_mktemp_with IAM_USER \
    aws iam get-user \
    --user-name "$SMTP_USER" 2>/dev/null &&
    lk_tty_detail "IAM user already exists:" "$SMTP_USER"; } ||
    lk_mktemp_with -r IAM_USER lk_tty_run_detail \
      aws iam create-user \
      --user-name "$SMTP_USER"

  POLICY=$(jq \
    --arg resource "$ARN_PREFIX/$DOMAIN" '
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
    lk_mktemp_with -r KEYS \
      aws iam list-access-keys \
      --user-name "$SMTP_USER"
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
    "Converting secret access key to SMTP credential for region:" "$AWS_REGION"
  SMTP_PASSWORD=$("$LK_BASE/lib/vendor/aws/smtp_credentials_generate.py" \
    "$SECRET_ACCESS_KEY" "$AWS_REGION")

  lk_tty_print "Credentials for Postfix:" \
    $'\n'"${ACCESS_KEY_ID}:${SMTP_PASSWORD}"

  exit
}

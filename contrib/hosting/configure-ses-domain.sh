#!/bin/bash

. lk-bash-load.sh || exit
lk_require linode

lk_assert_command_exists aws linode-cli

lk_is_fqdn "$@" || lk_die "invalid arguments"

export AWS_PROFILE=${AWS_PROFILE-${LK_AWS_PROFILE-}}
[ -n "${AWS_PROFILE:+1}" ] || lk_die "AWS_PROFILE not set"

AWS_REGION=$(aws configure get region) ||
    lk_die "AWS region not set for profile '$AWS_PROFILE'"

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
        DOMAIN=$1
        shift

        # `lk_linode_domain -s` sets DOMAIN and DOMAIN_ID
        if is_linode && lk_linode_domain -s "$DOMAIN" "${LINODE_ARGS[@]}"; then
            lk_tty_print "Adding Linode domain '$DOMAIN' to Amazon SES"
        else
            DOMAIN_ID=
            lk_tty_print "Adding unmanaged domain '$DOMAIN' to Amazon SES"
        fi

        { lk_mktemp_with -r IDENTITY \
            aws sesv2 get-email-identity \
            --email-identity "$DOMAIN" 2>/dev/null &&
            lk_tty_detail "Email identity already exists"; } ||
            lk_mktemp_with -r IDENTITY lk_tty_run_detail \
                aws sesv2 create-email-identity \
                --email-identity "$DOMAIN" \
                --dkim-signing-attributes NextSigningKeyLength="$DKIM_KEY_LENGTH"

        TOKENS=($(jq -r '.DkimAttributes.Tokens[]' <"$IDENTITY"))
        [ ${#TOKENS[@]} -eq 3 ] ||
            lk_die "unexpected value in .DkimAttributes.Tokens[]"

        if [ -n "$DOMAIN_ID" ]; then

            lk_mktemp_with RECORDS \
                lk_linode_domain_records "$DOMAIN_ID" ${LINODE+"${LINODE_ARGS[@]}"}

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
                    lk_tty_run_detail linode-cli ${LINODE+"${LINODE_ARGS[@]}"} \
                        domains records-update \
                        --target "$TARGET" \
                        "$DOMAIN_ID" "${RECORD%%,*}"
                    ;;

                "")
                    lk_tty_run_detail linode-cli ${LINODE+"${LINODE_ARGS[@]}"} \
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
                    NAME=$TOKEN._domainkey.$DOMAIN.
                    TARGET=$TOKEN.dkim.amazonses.com.
                    printf "%s IN CNAME %s\n" "$NAME" "$TARGET"
                done)"

            lk_tty_pause

        fi

    done

    exit
}

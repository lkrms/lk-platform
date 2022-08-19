#!/bin/bash

function lk_linode_provision_hosting() {
    local IFS=$'\n' REBUILD NODE_FQDN NODE_HOSTNAME HOST_DOMAIN HOST_ACCOUNT \
        ROOT_PASS AUTHORIZED_KEYS STACKSCRIPT STACKSCRIPT_DATA \
        ARGS VERBS KEY FILE LINODES EXIT_STATUS LINODE SH
    [ "${1-}" != -r ] || { REBUILD=$2 && shift 2; }
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME [-r LINODE_ID] FQDN DOMAIN [ACCOUNT [DATA_JSON [LINODE_ARG...]]]

Create a new Linode at FQDN and configure it to serve DOMAIN from user ACCOUNT.

\\SSH public keys are added from:
- array variable LK_LINODE_SSH_KEYS
- file LK_LINODE_SSH_KEYS_FILE
- ~/.ssh/authorized_keys (if both LK_LINODE_SSH_KEYS and LK_LINODE_SSH_KEYS_FILE
  are empty or unset)

Example:
  $FUNCNAME syd06.linode.myhosting.com linacreative.com lina" || return
    lk_is_fqdn "$1" || lk_warn "invalid domain: $1" || return
    lk_is_fqdn "$2" || lk_warn "invalid domain: $2" || return
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    NODE_FQDN=$1
    NODE_HOSTNAME=${1%%.*}
    HOST_DOMAIN=$2
    HOST_ACCOUNT=${3:-${2%%.*}}
    [[ $HOST_ACCOUNT =~ ^$LINUX_USERNAME_REGEX$ ]] ||
        lk_warn "invalid username: $HOST_ACCOUNT" || return
    AUTHORIZED_KEYS=(
        ${LK_LINODE_SSH_KEYS[@]+"${LK_LINODE_SSH_KEYS[@]}"}
        $([ ! -f "${LK_LINODE_SSH_KEYS_FILE-}" ] ||
            cat "$LK_LINODE_SSH_KEYS_FILE")
    )
    [ ${#AUTHORIZED_KEYS[@]} -gt 0 ] ||
        [ ! -f ~/.ssh/authorized_keys ] ||
        AUTHORIZED_KEYS=($(cat ~/.ssh/authorized_keys)) || return
    [ ${#AUTHORIZED_KEYS[@]} -gt 0 ] ||
        lk_warn "at least one authorized SSH key is required" || return
    unset IFS
    STACKSCRIPT=$(lk_linode_hosting_get_stackscript "${@:5}") ||
        lk_warn "hosting.sh StackScript not found" || return
    ARGS=(linodes create)
    VERBS=(Creating created)
    [ -z "${REBUILD-}" ] || {
        ARGS=(linodes rebuild)
        VERBS=(Rebuilding rebuilt)
        lk_linode_flush_cache
        LINODE=$(lk_linode_linodes "${@:5}" |
            jq -e --arg id "$REBUILD" \
                '[.[]|select((.id|tostring==$id) or .label==$id)]|if length==1 then .[0] else empty end') ||
            lk_warn "Linode not found: $REBUILD" || return
        SH=$(lk_linode_linode_sh <<<"$LINODE") &&
            eval "$SH" || return
        lk_tty_print "Rebuilding:" \
            "$LINODE_LABEL ($(lk_implode_arr ", " LINODE_TAGS))"
        lk_tty_detail "Linode ID:" "$LINODE_ID"
        lk_tty_detail "Linode type:" "$LINODE_TYPE"
        lk_tty_detail "CPU count:" "$LINODE_VPCUS"
        lk_tty_detail "Memory:" "$LINODE_MEMORY"
        lk_tty_detail "Storage:" "$((LINODE_DISK / 1024))G"
        lk_tty_detail "IP addresses:" $'\n'"$(lk_echo_args \
            $LINODE_IPV4_PUBLIC $LINODE_IPV6 $LINODE_IPV4_PRIVATE)"
        lk_confirm "Destroy the existing Linode and start over?" N || return
        ARGS+=(--image "$LINODE_IMAGE")
    }
    STACKSCRIPT_DATA=$(jq -n \
        --arg nodeFqdn "$NODE_FQDN" \
        --arg hostDomain "$HOST_DOMAIN" \
        --arg hostAccount "$HOST_ACCOUNT" \
        --arg adminEmail "${LK_ADMIN_EMAIL:-root@$NODE_FQDN}" \
        --arg autoReboot "${LK_AUTO_REBOOT:-Y}" \
        '{
    "LK_NODE_FQDN": $nodeFqdn,
    "LK_HOST_DOMAIN": $hostDomain,
    "LK_HOST_ACCOUNT": $hostAccount,
    "LK_ADMIN_EMAIL": $adminEmail,
    "LK_AUTO_REBOOT": $autoReboot
}'"${4:+ + $4}")
    ROOT_PASS=$(lk_random_password 64)
    ARGS+=(
        --json
        --root_pass "$ROOT_PASS"
        --stackscript_id "$STACKSCRIPT"
        --stackscript_data "$STACKSCRIPT_DATA"
    )
    [ -n "${REBUILD-}" ] || ARGS+=(
        --label "$NODE_HOSTNAME"
        --tags "${HOST_ACCOUNT:-$NODE_HOSTNAME}"
        --private_ip true
    )
    for KEY in "${AUTHORIZED_KEYS[@]}"; do
        ARGS+=(--authorized_keys "$KEY")
    done
    ARGS+=(
        "${@:5}"
        ${REBUILD:+"$LINODE_ID"}
    )
    lk_tty_print "Running:" \
        $'\n'"$(lk_fold_quote_options -120 linode-cli "${ARGS[@]##ssh-??? * }")"
    lk_confirm "Proceed?" Y || return
    lk_tty_print "${VERBS[0]} Linode"
    FILE=/tmp/$FUNCNAME-$1-$(lk_date %s).json
    LINODES=$(linode-cli "${ARGS[@]}" | tee "$FILE") ||
        lk_pass rm -f "$FILE" || return
    lk_linode_flush_cache
    LINODE=$(jq -c '.[0]' <<<"$LINODES")
    lk_tty_print "Linode ${VERBS[1]} successfully"
    lk_tty_detail "Root password:" "$ROOT_PASS"
    lk_tty_detail "Response written to:" "$FILE"
    SH=$(lk_linode_linode_sh <<<"$LINODE") &&
        eval "$SH" || return
    lk_tty_detail "Linode ID:" "$LINODE_ID"
    lk_tty_detail "Linode type:" "$LINODE_TYPE"
    lk_tty_detail "CPU count:" "$LINODE_VPCUS"
    lk_tty_detail "Memory:" "$LINODE_MEMORY"
    lk_tty_detail "Storage:" "$((LINODE_DISK / 1024))G"
    lk_tty_detail "Image:" "$LINODE_IMAGE"
    lk_tty_detail "IP addresses:" $'\n'"$(lk_echo_args \
        $LINODE_IPV4_PUBLIC $LINODE_IPV6 $LINODE_IPV4_PRIVATE)"
    lk_linode_ssh_add <<<"$LINODES"
    [ -z "$HOST_ACCOUNT" ] || {
        LK_SSH_PRIORITY='' \
            lk_linode_ssh_add "$HOST_ACCOUNT" "$HOST_ACCOUNT" <<<"$LINODES"
        LK_SSH_PRIORITY='' \
            lk_linode_ssh_add "$HOST_ACCOUNT-admin" "" <<<"$LINODES"
    }
    lk_linode_dns_check -t "$LINODES" "${NODE_FQDN#*.}" "${@:5}" &&
        LK_LINODE_JSON_FILE=$FILE
}

# lk_linode_hosting_get_meta DIR HOST...
function lk_linode_hosting_get_meta() {
    local DIR=${1-} _DIR HOST SSH_HOST FILE COMMIT EXT \
        FILES _FILES _FILE PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX} s=/
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME DIR HOST..." || return
    [ -d "$DIR" ] || lk_warn "not a directory: $DIR" || return
    DIR=${DIR%/}
    for HOST in "${@:2}"; do
        _DIR=$DIR/$HOST
        lk_install -d -m 00755 "$_DIR" || return
        SSH_HOST=$PREFIX${HOST#"$PREFIX"}
        FILE=$_DIR/StackScript-$HOST
        [ -e "$FILE" ] || {
            ssh "$SSH_HOST" \
                "sudo bash -c 'cp -pv /root/StackScript . && chown \$SUDO_USER: StackScript'" &&
                scp -p "$SSH_HOST":StackScript "$FILE" || return
            ! COMMIT=$(ssh "$SSH_HOST" "bash -c$(printf ' %q' \
                '{ cd "$1" 2>/dev/null || cd /opt/lk-platform; } && git rev-list -g HEAD | tail -n1' \
                bash \
                "/opt/${PREFIX}platform")") ||
                [ -z "$COMMIT" ] || {
                awk -f "$LK_BASE/lib/awk/patch-hosting-script.awk" \
                    -v commit="$COMMIT" <"$FILE" >"$FILE-patched" &&
                    touch -r "$FILE" "$FILE-patched" || return
            }
        }
        for EXT in log out; do
            FILE=$_DIR/install.$EXT-$HOST
            [ -e "$FILE" ] ||
                scp -p "$SSH_HOST:/var/log/lk-platform-install.$EXT" "$FILE" 2>/dev/null ||
                scp -p "$SSH_HOST:/var/log/${PREFIX}install.$EXT" "$FILE" 2>/dev/null || {
                _FILE=/opt/lk-platform/var/log/lk-provision-hosting.sh-0.$EXT
                ssh "$SSH_HOST" \
                    "sudo bash -c 'cp -pv $_FILE . && chown \$SUDO_USER: ${_FILE##*/}'" &&
                    scp -p "$SSH_HOST:${_FILE##*/}" "$FILE.tmp" &&
                    awk '!skip{print}/Shutdown scheduled for/{skip=1}' \
                        "$FILE.tmp" >"$FILE" &&
                    touch -r "$FILE.tmp" "$FILE" &&
                    rm -f "$FILE.tmp"
            } || return
        done
        FILES=$(ssh "$SSH_HOST" realpath -eq \
            /etc/default/lk-platform \
            /opt/{lk-,"$PREFIX"}platform/etc/{{lk-platform/,}"sites/*.conf",lk-platform/lk-platform.conf} \
            /etc/memcached.conf \
            "/etc/apache2/sites-available/*.conf" \
            "/etc/mysql/mariadb.conf.d/*$PREFIX*.cnf" \
            "/etc/php/*/fpm/pool.d/*.conf" \
            2>/dev/null | sort -u) || [ $? -ne 255 ]
        lk_mapfile _FILES <<<"$FILES"
        for _FILE in ${_FILES[@]+"${_FILES[@]}"}; do
            FILE=${_FILE#/}
            FILE=$_DIR/${FILE//"$s"/__}
            scp -p "$SSH_HOST:$_FILE" "$FILE" || return
        done
        awk -f "$LK_BASE/lib/awk/get-install-env.awk" \
            "$_DIR/install.log-$HOST" | { sed -E \
                -e '/^(DEBCONF_NONINTERACTIVE_SEEN|DEBIAN_FRONTEND|HOME|LINODE_.*|PATH|PWD|SHLVL|TERM|_)=/d' \
                -e 's/^((LK_)?NODE_(HOSTNAME|FQDN)=)/\1test-/' \
                -e '/^(LK_)?ADMIN_EMAIL=/d' \
                -e 's/^(CALL_HOME_MX=).*/\1/' &&
                if grep -Eq '<(lk:)?UDF\>.*\<ADMIN_EMAIL\>' \
                    "$_DIR/StackScript-$HOST"; then
                    printf ADMIN_EMAIL
                else
                    printf LK_ADMIN_EMAIL
                fi && echo "=nobody@localhost.localdomain"; } |
            while IFS='=' read -r VAR VALUE; do
                printf '%s=%q\n' "$VAR" "$VALUE"
            done >"$_DIR/StackScript-env-$HOST" &&
            touch -r "$_DIR/install.log-$HOST" \
                "$_DIR/StackScript-env-$HOST" "$_DIR" || return
    done
}

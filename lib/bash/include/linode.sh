#!/bin/bash

lk_include linux

function linode-cli() {
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function lk_linode_flush_cache() {
    local _DIR=${TMPDIR:-/tmp}
    _DIR=${_DIR%/}/_lk_linode_cache_$UID
    [ ! -e "$_DIR" ] ||
        rm -Rf "$_DIR"
    [ "$BASH_SUBSHELL" -eq 0 ] ||
        lk_warn "cannot flush cache in subshell" || exit
    unset "${!LK_LINODE_@}"
}

function _lk_linode_filter() {
    local REGEX=${LK_LINODE_SKIP_REGEX-^jump\\b}
    if [ -n "$REGEX" ]; then
        jq --arg skipRegex "$REGEX" \
            '[.[]|select(.label|test($skipRegex)==false)]'
    else
        cat
    fi
}

function _lk_linode_maybe_flush_cache() {
    [ "$BASH_SUBSHELL" -gt 0 ] ||
        [ -z "${_LK_LINODE_CACHE_DIRTY:-}" ] ||
        lk_linode_flush_cache
}

function _lk_linode_cache() {
    local _CACHE_VAR=$1 _DIR=${TMPDIR:-/tmp} _FILE
    _DIR=${_DIR%/}/_lk_linode_cache_$UID
    _FILE=$_DIR/$1
    if [ -e "$_FILE" ]; then
        cat "$_FILE"
    else
        [ -e "$_DIR" ] ||
            install -d -m 00700 "$_DIR" || return
        "${@:2}" | tee "$_DIR/$1"
    fi
}

function _lk_linode_define() {
    local _CACHE_VAR
    _CACHE_VAR=$(lk_upper "$1")
    eval "function $1() {
    [ \$# -eq 0 ] || {
        linode-cli --json ${*:2} \"\$@\"
        return
    }
    _lk_linode_maybe_flush_cache
    $_CACHE_VAR=\${$_CACHE_VAR:-\$(_lk_linode_cache $_CACHE_VAR linode-cli --json ${*:2})} &&
        echo \"\$$_CACHE_VAR\" ||
        echo \"\$$_CACHE_VAR\" >&2
}"
}

function _lk_linode_define_indexed() {
    local _CACHE_VAR
    _CACHE_VAR=$(lk_upper "$1")
    eval "function $1() {
    local _LK_VAR
    [ \$# -ge 1 ] && [[ \$1 =~ ^[0-9]+$ ]] || lk_warn \"invalid arguments\" || return
    [ \$# -eq 1 ] || {
        linode-cli --json ${*:2} \"\$@\"
        return
    }
    _lk_linode_maybe_flush_cache
    _LK_VAR=${_CACHE_VAR}_\$1
    eval \"\$_LK_VAR=\\\${\$_LK_VAR:-\\\$(_lk_linode_cache \$_LK_VAR linode-cli --json ${*:2} \\\"\\\$1\\\")}\" &&
        echo \"\${!_LK_VAR}\" ||
        echo \"\${!_LK_VAR}\" >&2
}"
}

_lk_linode_define lk_linode_linodes linodes list
_lk_linode_define lk_linode_ips networking ips-list
_lk_linode_define lk_linode_domains domains list
_lk_linode_define_indexed lk_linode_domain_records domains records-list
_lk_linode_define lk_linode_stackscripts stackscripts list --is_public false

function lk_linode_get_shell_var() {
    eval "$(lk_get_regex IPV4_PRIVATE_FILTER_REGEX)"
    # shellcheck disable=SC2016
    lk_jq_get_shell_var \
        --arg ipv4Private "$IPV4_PRIVATE_FILTER_REGEX" \
        LINODE_ID .id \
        LINODE_LABEL .label \
        LINODE_TYPE .type \
        LINODE_DISK .specs.disk \
        LINODE_VPCUS .specs.vcpus \
        LINODE_MEMORY .specs.memory \
        LINODE_IMAGE .image \
        LINODE_IPV4_PUBLIC 'first(.ipv4[]|select(test($ipv4Private)==false))' \
        LINODE_IPV4_PRIVATE 'first(.ipv4[]|select(test($ipv4Private)))' \
        LINODE_IPV6 '.ipv6|split("/")[0]'
}

# lk_linode_ssh_add [NAME [USER]]
#
# Add an SSH host for each Linode object in the JSON input array.
#
# shellcheck disable=SC2120
function lk_linode_ssh_add() {
    local LINODES LINODE SH LABEL USERNAME PUBLIC_SUFFIX \
        LK_SSH_PRIORITY=${LK_SSH_PRIORITY-45}
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH"
        eval "LABEL=${1:-}"
        LABEL=${LABEL:-${LINODE_LABEL%%.*}}
        eval "USERNAME=${2:-}"
        LK_CONSOLE_NO_FOLD=1 \
            lk_console_detail "Adding SSH host:" \
            $'\n'"${LK_SSH_PREFIX-$LK_PATH_PREFIX}$LABEL ($(lk_implode_args \
                " + " \
                ${LINODE_IPV4_PRIVATE:+"$LK_BOLD$LINODE_IPV4_PRIVATE$LK_RESET"} \
                ${LINODE_IPV4_PUBLIC:+"$LINODE_IPV4_PUBLIC"}))"
        PUBLIC_SUFFIX=
        [ "${LINODE_IPV4_PRIVATE:+1}${LK_SSH_JUMP_HOST:+1}" != 11 ] || {
            lk_ssh_add_host "$LABEL" \
                "$LINODE_IPV4_PRIVATE" "$USERNAME" "" "jump" || return
            PUBLIC_SUFFIX=-direct
        }
        [ -z "$LINODE_IPV4_PUBLIC" ] || lk_ssh_add_host "$LABEL$PUBLIC_SUFFIX" \
            "$LINODE_IPV4_PUBLIC" "$USERNAME" || return
    done
}

# lk_linode_ssh_add_all [LINODE_ARG...]
function lk_linode_ssh_add_all() {
    local JSON LABELS
    _lk_linode_maybe_flush_cache
    JSON=$(lk_linode_linodes "$@" | _lk_linode_filter) || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON" &&
        [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS | sort |
        lk_console_list "Adding to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    lk_linode_ssh_add <<<"$JSON"
    lk_console_success "SSH configuration complete"
}

# lk_linode_hosting_ssh_add_all [LINODE_ARG...]
#
# shellcheck disable=SC2029,SC2207
function lk_linode_hosting_ssh_add_all() {
    local GET_USERS_SH JSON LINODES LINODE SH IFS USERS USERNAME ALL_USERS=()
    _lk_linode_maybe_flush_cache
    GET_USERS_SH="$(declare -f lk_get_standard_users);lk_get_standard_users" &&
        GET_USERS_SH=$(printf '%q' "$GET_USERS_SH") || return
    JSON=$(lk_linode_linodes "$@" | _lk_linode_filter) &&
        lk_jq_get_array LINODES <<<"$JSON" &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    jq -r '.[].label' <<<"$JSON" | sort | lk_console_list \
        "Adding hosting accounts to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH" || return
        lk_console_item "Retrieving hosting accounts from" "$LINODE_LABEL"
        IFS=$'\n'
        USERS=($(ssh "${LK_SSH_PREFIX-$LK_PATH_PREFIX}${LINODE_LABEL%%.*}" \
            "bash -c $GET_USERS_SH")) || return
        unset IFS
        for USERNAME in ${USERS[@]+"${USERS[@]}"}; do
            ! lk_in_array "$USERNAME" ALL_USERS || {
                lk_console_warning "Skipping $USERNAME (already used)"
                continue
            }
            ALL_USERS+=("$USERNAME")
            LK_SSH_PRIORITY='' \
                lk_linode_ssh_add "$USERNAME" "$USERNAME" <<<"[$LINODE]"
        done
    done
    lk_console_success "SSH configuration complete"
}

# lk_linode_get_only_domain [LINODE_ARG...]
function lk_linode_get_only_domain() {
    local DOMAIN_ID
    _lk_linode_maybe_flush_cache
    DOMAIN_ID=$(lk_linode_domains "$@" | jq -r '.[].id') || return
    [ -n "$DOMAIN_ID" ] && [ "$(wc -l <<<"$DOMAIN_ID")" -eq 1 ] ||
        lk_warn "domain count must be 1" || return
    echo "$DOMAIN_ID"
}

# lk_linode_dns_check [DOMAIN_ID [LINODE_ARG...]]
#
# For each Linode object in the JSON input array, check DOMAIN_ID for each of
# the following records, add any that are missing, and if LK_VERBOSE >= 1,
# report any unmatched records.
# - {LABEL}             A       {IPV4_PUBLIC}
# - {LABEL}.PRIVATE     A       {IPV4_PRIVATE}
# - {LABEL}             AAAA    {IPV6}
#
# Characters after the first "." in each label are discarded. If DOMAIN_ID is
# not specified, `linode-cli domains list` will be called and if exactly one
# domain is returned, its ID will be used, otherwise false will be returned.
function lk_linode_dns_check() {
    local LINODES DOMAIN_ID DOMAIN RECORDS REVERSE_RECORDS \
        NEW_RECORDS NEW_REVERSE_RECORDS LINODE SH LABEL \
        OUTPUT RECORD_ID NEW_RECORD_COUNT=0 NEW_REVERSE_RECORD_COUNT=0
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    lk_console_message "Retrieving domain records and Linode IP addresses"
    DOMAIN_ID=${1:-$(lk_linode_get_only_domain "${@:2}")} &&
        lk_console_detail "Domain ID:" "$DOMAIN_ID" &&
        DOMAIN=$(lk_linode_domains "${@:2}" |
            jq -r --arg domainId "$DOMAIN_ID" \
                '.[]|select(.id==($domainId|tonumber)).domain') &&
        [ -n "$DOMAIN" ] || lk_warn "unable to retrieve domain" || return
    lk_console_detail "Domain name:" "$DOMAIN"
    RECORDS=$(lk_linode_domain_records "$DOMAIN_ID" "${@:2}" |
        jq -r '.[]|"\(.name)\t\(.type)\t\(.target)"') &&
        REVERSE_RECORDS=$(lk_linode_ips "${@:2}" |
            jq -r '.[]|select(.rdns!=null)|"\(.address)\t\(.rdns)"' |
            sed 's/\.$//') || return
    eval "$(lk_get_regex DOMAIN_PART_REGEX)"
    NEW_RECORDS=()
    NEW_REVERSE_RECORDS=()
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH" || return
        LABEL=${LINODE_LABEL%%.*}
        [[ $LABEL =~ ^$DOMAIN_PART_REGEX$ ]] ||
            lk_warn "invalid label: $LINODE_LABEL" || continue
        NEW_RECORDS+=("$(printf '%s\t%s\t%s\n' \
            "$LABEL" "A" "$LINODE_IPV4_PUBLIC" \
            "$LABEL" "AAAA" "$LINODE_IPV6" \
            "$LABEL.private" "A" "$LINODE_IPV4_PRIVATE")")
        NEW_REVERSE_RECORDS+=("$(printf '%s\t%s\n' \
            "$LINODE_IPV4_PUBLIC" "$LABEL.$DOMAIN" \
            "$LINODE_IPV6" "$LABEL.$DOMAIN")")
    done
    while read -r NAME TYPE TARGET; do
        lk_console_item "Adding DNS record:" "$NAME $TYPE $TARGET"
        OUTPUT=$(linode-cli --json domains records-create \
            --type "$TYPE" \
            --name "$NAME" \
            --target "$TARGET" \
            "$DOMAIN_ID" \
            "${@:2}") &&
            RECORD_ID=$(jq '.[0].id' <<<"$OUTPUT") ||
            lk_warn "linode-cli failed with: $OUTPUT" || return
        _LK_LINODE_CACHE_DIRTY=1
        ((++NEW_RECORD_COUNT))
        lk_console_detail "Record ID:" "$RECORD_ID"
    done < <(comm -23 \
        <(lk_echo_array NEW_RECORDS | sort) \
        <(sort <<<"$RECORDS"))
    while read -r ADDRESS RDNS; do
        [ "$NEW_RECORD_COUNT" -eq 0 ] ||
            [ "$NEW_REVERSE_RECORD_COUNT" -gt 0 ] || {
            lk_console_message "Waiting 60 seconds"
            sleep 60
        }
        lk_console_item "Adding RDNS record:" "$ADDRESS $RDNS"
        OUTPUT=$(linode-cli --json networking ip-update \
            --rdns "$RDNS" \
            "$ADDRESS" \
            "${@:2}") ||
            lk_warn "linode-cli failed with: $OUTPUT" || return
        _LK_LINODE_CACHE_DIRTY=1
        ((++NEW_REVERSE_RECORD_COUNT))
        lk_console_detail "Record added"
    done < <(comm -23 \
        <(lk_echo_array NEW_REVERSE_RECORDS | sort) \
        <(sort <<<"$REVERSE_RECORDS"))
    ! lk_verbose || {
        RECORDS=$(comm -13 \
            <(lk_echo_array NEW_RECORDS | sort) \
            <(sort <<<"$RECORDS"))
        [ -z "$RECORDS" ] ||
            lk_console_warning0 "No matching Linode:" "$RECORDS"
    }
}

# lk_linode_dns_check_all [DOMAIN_ID [LINODE_ARG...]]
function lk_linode_dns_check_all() {
    local JSON LABELS
    _lk_linode_maybe_flush_cache
    JSON=$(lk_linode_linodes "${@:2}") || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON"
    [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS | sort |
        lk_console_list "Checking DNS and RDNS records for:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    LK_VERBOSE=1 lk_linode_dns_check "$1" "${@:2}" <<<"$JSON" || return
    lk_console_success "DNS check complete"
}

# lk_linode_hosting_update_stackscript [REPO [REF [LINODE_ARG...]]]
#
# shellcheck disable=SC2207
function lk_linode_hosting_update_stackscript() {
    local REPO=${1:-$LK_BASE} REF=${2:-HEAD} HASH BASED_ON \
        SCRIPT STACKSCRIPT ARGS MESSAGE OUTPUT
    cd "$REPO" || return
    HASH=$(git rev-parse --verify "$REF") &&
        BASED_ON=($(LK_GIT_REF=$HASH \
            lk_git_ancestors master develop | head -n1)) ||
        lk_warn "invalid ref: $REF" || return
    SCRIPT=$(git show "$HASH:lib/linode/hosting.sh") || return
    if STACKSCRIPT=$(lk_linode_stackscripts --label hosting.sh "${@:3}" |
        jq -r '.[].id' | head -n1) && [ -n "$STACKSCRIPT" ]; then
        ARGS=(update "$STACKSCRIPT")
        MESSAGE="updated to"
        lk_console_item "Updating StackScript" "$STACKSCRIPT"
    else
        ARGS=(create)
        MESSAGE="created with"
        lk_console_message "Creating StackScript"
    fi
    OUTPUT=$(linode-cli --json stackscripts "${ARGS[@]}" \
        --label hosting.sh \
        --images linode/ubuntu20.04 \
        --images linode/ubuntu18.04 \
        --images linode/ubuntu16.04lts \
        --script "$SCRIPT" \
        --description "Provision a new Linode configured for hosting" \
        --is_public false \
        --rev_note "commit: ${HASH:0:7} (based on lk-platform/${BASED_ON[2]}@${BASED_ON[1]:0:7}" \
        "${@:3}") ||
        lk_warn "linode-cli failed with: $OUTPUT" || return
    _LK_LINODE_CACHE_DIRTY=1
    STACKSCRIPT=$(jq -r '.[0].id' <<<"$OUTPUT") &&
        lk_console_detail "StackScript $STACKSCRIPT $MESSAGE" "${HASH:0:7}:hosting.sh"
}

# lk_linode_hosting_get_meta DIR HOST...
function lk_linode_hosting_get_meta() {
    local DIR=${1:-} HOST SSH_HOST FILE COMMIT \
        PREFIX=${LK_SSH_PREFIX-$LK_PATH_PREFIX}
    [ $# -ge 2 ] || lk_usage "\
Usage: $(lk_myself -f) DIR HOST..." || return
    [ -d "$DIR" ] || lk_warn "not a directory: $DIR" || return
    DIR=${DIR%/}
    for HOST in "${@:2}"; do
        SSH_HOST=$PREFIX${HOST#$PREFIX}
        FILE=$DIR/StackScript-$HOST
        [ -e "$FILE" ] || {
            ssh "$SSH_HOST" \
                "sudo bash -c 'cp -pv /root/StackScript . && chown \$SUDO_USER: StackScript'" &&
                scp -p "$SSH_HOST":StackScript "$FILE" || return
            # shellcheck disable=SC2016,SC2029
            ! COMMIT=$(ssh "$SSH_HOST" "bash -c$(printf ' %q' \
                'cd "$1" && git rev-list -g HEAD | tail -n1' \
                bash \
                "/opt/${PREFIX}platform")") ||
                [ -z "$COMMIT" ] || {
                awk -f "$LK_BASE/lib/awk/patch-hosting-script.awk" \
                    -v commit="$COMMIT" <"$FILE" >"$FILE-patched" &&
                    touch -r "$FILE" "$FILE-patched" || return
            }
        }
        FILE=$DIR/install.log-$HOST
        [ -e "$FILE" ] ||
            scp -p "$SSH_HOST:/var/log/${PREFIX}install.log" "$FILE" || return
        FILE=$DIR/install.out-$HOST
        [ -e "$FILE" ] ||
            scp -p "$SSH_HOST:/var/log/${PREFIX}install.out" "$FILE" || return
        awk -f "$LK_BASE/lib/awk/get-install-env.awk" "$DIR/install.log-$HOST" |
            sed -E \
                -e '/^(DEBCONF_NONINTERACTIVE_SEEN|DEBIAN_FRONTEND|HOME|LINODE_.*|PATH|PWD|SHLVL|TERM|_)=/d' \
                -e "s/^((LK_)?NODE_(HOSTNAME|FQDN)=)/\\1test-/" \
                -e "s/^((LK_)?ADMIN_EMAIL=).*/\\1nobody@localhost/" \
                -e "s/^(CALL_HOME_MX=).*/\\1/" |
            while IFS='=' read -r VAR VALUE; do
                printf '%s=%q\n' "$VAR" "$VALUE"
            done >"$DIR/StackScript-env-$HOST" &&
            touch -r "$DIR/install.log-$HOST" "$DIR/StackScript-env-$HOST" || return
    done
}

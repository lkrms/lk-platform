#!/bin/bash

# lk_linode_ssh_add [NAME [USER]]
#
# Add an SSH host for each Linode object in the JSON input array.
function lk_linode_ssh_add() {
    local LINODES LINODE SH LABEL USERNAME PUBLIC_SUFFIX \
        LK_SSH_PRIORITY=${LK_SSH_PRIORITY-45}
    lk_jq_get_array LINODES &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes in input" || return
    for LINODE in "${LINODES[@]}"; do
        SH=$(lk_linode_get_shell_var <<<"$LINODE") &&
            eval "$SH"
        eval "LABEL=${1-}"
        LABEL=${LABEL:-${LINODE_LABEL%%.*}}
        eval "USERNAME=${2-}"
        lk_console_detail "Adding SSH host:" \
            $'\n'"${LK_SSH_PREFIX-$LK_PATH_PREFIX}$LABEL ($(lk_implode_args \
                " + " \
                ${LINODE_IPV4_PRIVATE:+"$LK_BOLD$LINODE_IPV4_PRIVATE$LK_RESET"} \
                ${LINODE_IPV4_PUBLIC:+"$LINODE_IPV4_PUBLIC"}))"
        PUBLIC_SUFFIX=
        if [ "$(lk_hostname)" = jump ]; then
            lk_ssh_add_host "$LABEL" \
                "$LINODE_IPV4_PRIVATE" "$USERNAME" || return
            PUBLIC_SUFFIX=-public
        elif [ "${LINODE_IPV4_PRIVATE:+1}${LK_SSH_JUMP_HOST:+1}" = 11 ]; then
            lk_ssh_add_host "$LABEL" \
                "$LINODE_IPV4_PRIVATE" "$USERNAME" "" "jump" || return
            PUBLIC_SUFFIX=-direct
        fi
        [ -z "$LINODE_IPV4_PUBLIC" ] || lk_ssh_add_host "$LABEL$PUBLIC_SUFFIX" \
            "$LINODE_IPV4_PUBLIC" "$USERNAME" || return
    done
}

# lk_linode_ssh_add_all [LINODE_ARG...]
function lk_linode_ssh_add_all() {
    local JSON LABELS
    JSON=$(lk_linode_linodes "$@" | _lk_linode_filter) || return
    lk_jq_get_array LABELS ".[].label" <<<"$JSON" &&
        [ ${#LABELS[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    lk_echo_array LABELS | sort |
        lk_tty_list - "Adding to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    lk_linode_ssh_add <<<"$JSON"
    lk_console_success "SSH configuration complete"
}

# lk_linode_hosting_ssh_add_all [LINODE_ARG...]
function lk_linode_hosting_ssh_add_all() {
    local GET_USERS_SH JSON LINODES LINODE SH IFS USERS USERNAME ALL_USERS=()
    GET_USERS_SH=$(printf '%q\n' \
        "$(declare -f lk_get_users_in_group lk_get_standard_users &&
            lk_quote_args lk_get_standard_users /srv/www)") || return
    JSON=$(lk_linode_linodes "$@" | _lk_linode_filter) &&
        lk_jq_get_array LINODES <<<"$JSON" &&
        [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    jq -r '.[].label' <<<"$JSON" | sort | lk_tty_list - \
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
            LK_SSH_PRIORITY='' \
                lk_linode_ssh_add "$USERNAME-admin" "" <<<"[$LINODE]"
        done
    done
    lk_console_success "SSH configuration complete"
}

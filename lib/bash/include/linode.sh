#!/bin/bash

function linode-cli() {
    # Suppress "Unable to determine if a new linode-cli package is available in
    # pypi"
    command linode-cli --suppress-warnings "$@"
}

function lk_linode_list() {
    lk_console_message "Retrieving list of Linodes"
    linode-cli --format="${1:-id}" --text --no-headers linodes list
}

# lk_linode_ssh_add LINODE_ID[,LABEL]...
function lk_linode_ssh_add() {
    local JQ_LABEL JQ_IPV4 LINODE_ID JSON LABEL
    JQ_LABEL=$(
        cat <<"EOF"
def to_bash:
  to_entries[] | "local \(.key | ascii_upcase)=\(.value | @sh)";
.[] | {
    "LABEL": .label
  } | to_bash
EOF
    )
    JQ_IPV4=$(
        cat <<"EOF"
def to_bash:
  to_entries[] | "local \(.key | ascii_upcase)=\(.value | @sh)";
.[] | {
    "IPV4_PUBLIC": .ipv4.public[].address,
    "IPV4_PRIVATE": .ipv4.private[].address
  } | to_bash
EOF
    )
    for LINODE_ID in "$@"; do
        if [[ $LINODE_ID =~ ^([0-9]+),(.+)$ ]]; then
            LINODE_ID=${BASH_REMATCH[1]}
            LABEL=${BASH_REMATCH[2]}
            lk_console_item "Adding SSH host:" "$LABEL (#$LINODE_ID)"
        else
            lk_console_item "Adding SSH host:" "#$LINODE_ID"
            JSON=$(linode-cli linodes view "$LINODE_ID" --json) &&
                SH=$(jq -r "$JQ_LABEL" <<<"$JSON") &&
                eval "$SH" || return
            lk_console_detail "Label:" "$LABEL"
        fi
        JSON=$(linode-cli linodes ips-list "$LINODE_ID" --json) &&
            SH=$(jq -r "$JQ_IPV4" <<<"$JSON") &&
            eval "$SH" || return
        lk_console_detail "IPv4 $(lk_maybe_plural \
            "${IPV4_PUBLIC+1}${IPV4_PRIVATE+1}" address addresses):" \
            $'\n'"$(lk_implode_args $'\n' ${IPV4_PUBLIC+"$IPV4_PUBLIC"} \
                ${IPV4_PRIVATE+"$IPV4_PRIVATE"})"
        lk_ssh_add_host "${LABEL%%.*}" "$IPV4_PRIVATE" "" "" "jump" &&
            lk_ssh_add_host "${LABEL%%.*}-direct" "$IPV4_PUBLIC" "" || return
    done
}

# shellcheck disable=SC2001,SC2207,SC2034
function lk_linode_ssh_add_all() {
    local IFS=$'\n' LINODES LABELS
    LINODES=($(lk_linode_list "id,label")) || return
    [ ${#LINODES[@]} -gt 0 ] || lk_warn "no Linodes found" || return
    LABELS=($(cut -f2 <<<"${LINODES[*]}"))
    LINODES=($(sed 's/\t/,/' <<<"${LINODES[*]}"))
    unset IFS
    lk_echo_array LABELS |
        lk_console_list "Adding to SSH configuration:" Linode Linodes
    lk_confirm "Proceed?" Y || return
    lk_linode_ssh_add "${LINODES[@]}"
}

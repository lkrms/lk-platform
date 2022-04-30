#!/bin/bash

function lk_linode_hosting_get_stackscript() {
    local STACKSCRIPT
    STACKSCRIPT=$(lk_linode_stackscripts --label hosting.sh "$@" |
        jq -r '.[].id' |
        sort -n) &&
        [ -n "$STACKSCRIPT" ] && {
        [ "$(wc -l <<<"$STACKSCRIPT")" -eq 1 ] ||
            lk_warn "multiple hosting.sh StackScripts found" || true
        echo "$STACKSCRIPT" | tail -n1
    }
}

# lk_linode_hosting_update_stackscript [REPO [REF [LINODE_ARG...]]]
function lk_linode_hosting_update_stackscript() {
    local REPO=${1:-$LK_BASE} REF=${2:-HEAD} HASH BASED_ON \
        SCRIPT STACKSCRIPT ARGS MESSAGE OUTPUT
    cd "$REPO" || return
    HASH=$(git rev-parse --verify "$REF") &&
        BASED_ON=($(LK_GIT_REF=$HASH \
            lk_git_ancestors main develop | head -n1)) ||
        lk_warn "invalid ref: $REF" || return
    SCRIPT=$(git show "$HASH:lib/linode/hosting.sh") || return
    if STACKSCRIPT=$(lk_linode_hosting_get_stackscript "${@:3}"); then
        ARGS=(update "$STACKSCRIPT")
        MESSAGE="updated to"
        lk_tty_print "Updating StackScript" "$STACKSCRIPT"
    else
        ARGS=(create)
        MESSAGE="created with"
        lk_tty_print "Creating StackScript"
    fi
    OUTPUT=$(linode-cli --json stackscripts "${ARGS[@]}" \
        --label hosting.sh \
        --images linode/ubuntu22.04 \
        --images linode/ubuntu20.04 \
        --images linode/ubuntu18.04 \
        --script "$SCRIPT" \
        --description "Provision a new Linode configured for hosting" \
        --is_public false \
        --rev_note "commit: ${HASH:0:7} (based on lk-platform/${BASED_ON[2]}@${BASED_ON[1]:0:7}" \
        "${@:3}") ||
        lk_warn "unable to ${ARGS[0]} StackScript" || return
    lk_linode_flush_cache
    STACKSCRIPT=$(jq -r '.[0].id' <<<"$OUTPUT") &&
        lk_tty_detail "StackScript $STACKSCRIPT $MESSAGE" "${HASH:0:7}:hosting.sh"
}

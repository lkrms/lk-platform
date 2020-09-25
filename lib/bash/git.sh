#!/bin/bash

# shellcheck disable=SC2015

# lk_git_ancestors <REF>...
#
# Output lines with tab-separated fields <behind>, <hash>, and REF, sorted
# numerically on <behind>, for each REF that is an ancestor of HEAD. If no REF
# is an ancestor, return false.
function lk_git_ancestors() {
    local REF HASH BEHIND ANCESTORS
    for REF in "$@"; do
        git merge-base --is-ancestor "$REF" HEAD &&
            HASH=$(git merge-base "$REF" HEAD) &&
            BEHIND=$(git rev-list --count "$HASH..HEAD") || continue
        ANCESTORS+=("$BEHIND" "$HASH" "$REF")
    done
    [ ${#ANCESTORS[@]} -gt 0 ] || return
    printf '%s\t%s\t%s\n' "${ANCESTORS[@]}" | sort -n
}

function lk_git_recheckout() {
    local REPO_ROOT COMMIT
    lk_console_message "Preparing to delete the index and check out HEAD again"
    REPO_ROOT="$(git rev-parse --show-toplevel)" &&
        COMMIT="$(git rev-list -1 --oneline HEAD)" || return
    lk_console_detail "Repository:" "$REPO_ROOT"
    lk_console_detail "HEAD refers to:" "$COMMIT"
    lk_confirm "Uncommitted changes will be permanently deleted. Proceed?" N || return
    rm -fv "$REPO_ROOT/.git/index" &&
        git checkout --force --no-overlay HEAD -- "$REPO_ROOT" &&
        lk_console_success "Checkout completed successfully"
}

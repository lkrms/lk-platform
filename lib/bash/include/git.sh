#!/bin/bash

# shellcheck disable=SC2015

function lk_git_quiet() {
    [ "${LK_GIT_QUIET:-0}" -ne 0 ]
}

function lk_git_is_in_work_tree() {
    local RESULT
    RESULT=$(cd "${1:-.}" &&
        git rev-parse --is-inside-work-tree 2>/dev/null) &&
        lk_is_true "$RESULT"
}

# lk_git_get_repos ARRAY [DIR...]
#
# Populate ARRAY with the path to the top-level working directory of each git
# repository found in DIR or the current directory.
function lk_git_get_repos() {
    local _LK_GIT_REPO _LK_GIT_ROOT
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    [ $# -lt 2 ] || for _LK_GIT_ROOT in "${@:2}"; do
        [ "${_LK_GIT_ROOT:0:1}" != - ] ||
            lk_warn "illegal directory: $_LK_GIT_ROOT" || return
    done
    eval "$1=()"
    while IFS= read -rd $'\0' _LK_GIT_REPO; do
        lk_git_is_in_work_tree "$_LK_GIT_REPO" || continue
        eval "$1+=(\"\$_LK_GIT_REPO\")"
    done < <(
        ROOTS=(.)
        [ $# -lt 2 ] || ROOTS=("${@:2}")
        find -L "${ROOTS[@]}" \
            -type d -exec test -d "{}/.git" \; -print0 -prune |
            sort -z
    )
}

function lk_git_with_repos() {
    local REPO ERROR_COUNT=0 \
        REPO_COMMAND=("$@") REPOS=(${LK_GIT_REPOS+"${LK_GIT_REPOS[@]}"})
    [ $# -gt 0 ] || lk_usage "\
Usage: $(lk_myself -f) COMMAND [ARG...]

Run COMMAND at the top of each repository in the current directory." || return
    lk_git_quiet || lk_console_message "Finding repositories"
    [ ${#REPOS[@]} -gt 0 ] || lk_git_get_repos REPOS
    [ ${#REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    lk_resolve_files REPOS || return
    lk_git_quiet ||
        LK_CONSOLE_NO_FOLD=1 lk_console_detail "Command:" "${REPO_COMMAND[*]}"
    lk_git_quiet ||
        lk_echo_array REPOS | lk_console_detail_list "Repositories:" repo repos
    lk_git_quiet || lk_confirm "Proceed?" Y || return
    for REPO in "${REPOS[@]}"; do
        lk_git_quiet || lk_console_item "Processing" "$REPO"
        (cd "$REPO" &&
            "${REPO_COMMAND[@]}") || ((++ERROR_COUNT))
    done
    lk_git_quiet || {
        [ "$ERROR_COUNT" -eq 0 ] &&
            lk_console_success "${REPO_COMMAND[*]}" \
                "executed without error in ${#REPOS[@]} $(lk_maybe_plural \
                    ${#REPOS[@]} repository repositories)" ||
            lk_console_error0 "${REPO_COMMAND[*]}" \
                "failed in $ERROR_COUNT of ${#REPOS[@]} $(lk_maybe_plural \
                    ${#REPOS[@]} repository repositories)"
    }
    [ "$ERROR_COUNT" -eq 0 ]
}

# lk_git_ancestors REF...
#
# Output lines with tab-separated fields BEHIND, HASH, and REF, sorted
# numerically on BEHIND, for each REF that is an ancestor of HEAD. If no REF is
# an ancestor, return false.
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

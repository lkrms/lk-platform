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
    local PARALLEL REPO_COMMAND REPO ERROR_COUNT=0 \
        REPOS=(${LK_GIT_REPOS[@]+"${LK_GIT_REPOS[@]}"})
    [ "${1:-}" != -p ] || {
        ! lk_bash_at_least 4 3 || PARALLEL=1
        shift
    }
    REPO_COMMAND=("$@")
    [ $# -gt 0 ] || lk_usage "\
Usage: $(lk_myself -f) [-p] COMMAND [ARG...]

For each Git repository in the directory hierarchy rooted at \".\", run COMMAND in
the working tree's top-level directory. If -p is set, process multiple
repositories simultaneously." || return
    lk_git_quiet || lk_console_message "Finding repositories"
    [ ${#REPOS[@]} -gt 0 ] || lk_git_get_repos REPOS
    [ ${#REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    lk_resolve_files REPOS || return
    lk_git_quiet ||
        LK_CONSOLE_NO_FOLD=1 lk_console_detail "Command:" "${REPO_COMMAND[*]}"
    lk_git_quiet ||
        lk_echo_array REPOS | lk_console_detail_list "Repositories:" repo repos
    lk_git_quiet || lk_confirm "Proceed?" Y || return
    if lk_is_true "${PARALLEL:-}"; then
        for REPO in "${REPOS[@]}"; do
            (
                exec 2>&4
                cd "$REPO" || exit
                EXIT_STATUS=0
                SH=$(lk_get_outputs_of "${REPO_COMMAND[@]}") ||
                    EXIT_STATUS=$?
                eval "$SH"
                lk_git_quiet || MESSAGE=$(
                    unset _LK_FD
                    {
                        lk_console_item "Processed:" "$REPO"
                        [ -z "$_STDOUT" ] ||
                            LK_CONSOLE_SECONDARY_COLOUR=$LK_GREEN \
                                lk_console_detail "Output:" \
                                $'\n'"$_STDOUT"
                        [ -z "$_STDERR" ] ||
                            LK_CONSOLE_SECONDARY_COLOUR=$LK_RED \
                                lk_console_detail "Error output:" \
                                $'\n'"$_STDERR"
                        [ "$EXIT_STATUS" -eq 0 ] ||
                            lk_console_detail \
                                "Exit status:" "$EXIT_STATUS" "$LK_BOLD$LK_RED"
                    } 2>&1
                )
                # TODO: get a lock first?
                echo "$MESSAGE" >&4
                exit "$EXIT_STATUS"
            ) &
        done 4>&2 2>/dev/null
        while [ "$(jobs -p | wc -l)" -gt 0 ]; do
            wait -n 2>/dev/null || ((++ERROR_COUNT))
        done
    else
        for REPO in "${REPOS[@]}"; do
            lk_git_quiet || lk_console_item "Processing" "$REPO"
            (cd "$REPO" &&
                "${REPO_COMMAND[@]}") || ((++ERROR_COUNT))
        done
    fi
    lk_git_quiet || {
        [ "$ERROR_COUNT" -eq 0 ] &&
            LK_CONSOLE_NO_FOLD=1 lk_console_success "${REPO_COMMAND[*]}" \
                "executed without error in ${#REPOS[@]} $(lk_maybe_plural \
                    ${#REPOS[@]} repository repositories)" ||
            LK_CONSOLE_NO_FOLD=1 lk_console_error0 "${REPO_COMMAND[*]}" \
                "failed in $ERROR_COUNT of ${#REPOS[@]} $(lk_maybe_plural \
                    ${#REPOS[@]} repository repositories)"
    }
    [ "$ERROR_COUNT" -eq 0 ]
}

# lk_git_ancestors REF...
#
# Output lines with tab-separated fields BEHIND, HASH, and REF, sorted
# numerically on BEHIND, for each REF that shares an ancestor with HEAD,
# measuring BEHIND from the point where HEAD and REF diverged. Output REFs with
# identical BEHIND values in argument order. If no REF is an ancestor, return
# false.
#
# To compare ancestors of a ref other than HEAD, set LK_GIT_REF.
function lk_git_ancestors() {
    local i REF HASH BEHIND ANCESTORS
    for REF in "$@"; do
        HASH=$(git merge-base --fork-point "$REF" "${LK_GIT_REF:-HEAD}") &&
            BEHIND=$(git rev-list --count "$HASH..${LK_GIT_REF:-HEAD}") ||
            continue
        ANCESTORS+=("$((i++))" "$BEHIND" "$HASH" "$REF")
    done
    [ ${#ANCESTORS[@]} -gt 0 ] || return
    printf '%s\t%s\t%s\t%s\n' "${ANCESTORS[@]}" | sort -n -k2 -k1 | cut -f2-
}

# lk_git_config_remote_push_all [REMOTE]
#
# Configure the repository to push to all remotes when pushing to REMOTE
# (default: the upstream remote of the current branch).
function lk_git_config_remote_push_all() {
    local UPSTREAM REMOTE_URL REMOTE
    UPSTREAM=${1:-$(git rev-parse --abbrev-ref "@{u}" | sed 's/\/.*//')} &&
        REMOTE_URL=$(git config "remote.$UPSTREAM.url") &&
        [ -n "$REMOTE_URL" ] || lk_warn "remote URL not found" || return
    lk_console_item "Configuring" "remote.$UPSTREAM.pushUrl"
    lk_console_detail "Adding:" "$REMOTE_URL"
    git config push.default current &&
        git config remote.pushDefault "$UPSTREAM" &&
        git config --replace-all "remote.$UPSTREAM.pushUrl" "$REMOTE_URL" &&
        for REMOTE in $(git remote | grep -Fxv "$UPSTREAM"); do
            REMOTE_URL=$(git config "remote.$REMOTE.url") &&
                [ -n "$REMOTE_URL" ] ||
                lk_warn "URL not found for remote $REMOTE" || continue
            lk_console_detail "Adding:" "$REMOTE_URL"
            git config --add "remote.$UPSTREAM.pushUrl" "$REMOTE_URL"
        done
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

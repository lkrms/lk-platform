#!/bin/bash

# shellcheck disable=SC2015,SC2034,SC2207

function _lk_git() {
    if [ -n "${LK_GIT_USER:-}" ]; then
        sudo -H -u "$LK_GIT_USER" git "$@"
    else
        lk_maybe_sudo git "$@"
    fi
}

function lk_git_is_quiet() {
    [ -n "${LK_GIT_QUIET:-}" ]
}

function lk_git_is_work_tree() {
    local RESULT
    RESULT=$({ [ -z "${1:-}" ] || cd "$1"; } &&
        git rev-parse --is-inside-work-tree 2>/dev/null) &&
        lk_is_true RESULT
}

function lk_git_is_submodule() {
    local RESULT
    RESULT=$({ [ -z "${1:-}" ] || cd "$1"; } &&
        git rev-parse --show-superproject-working-tree) &&
        [ -n "$RESULT" ]
}

function lk_git_is_top_level() {
    local RESULT
    RESULT=$({ [ -z "${1:-}" ] || cd "$1"; } &&
        git rev-parse --show-prefix) &&
        [ -z "$RESULT" ]
}

function lk_git_is_project_top_level() {
    lk_git_is_work_tree "${1:-}" &&
        ! lk_git_is_submodule "${1:-}" &&
        lk_git_is_top_level "${1:-}"
}

function lk_git_is_clean() {
    local NO_REFRESH=
    [ "${1:-}" != -n ] || { NO_REFRESH=1 && shift; }
    ({ [ -z "${1:-}" ] || cd "$1"; } &&
        { lk_is_true NO_REFRESH ||
            _lk_git update-index --refresh >/dev/null; } &&
        git diff-index --quiet HEAD --)
}

function lk_git_remote_singleton() {
    local REMOTES
    REMOTES=($(git remote)) &&
        [ ${#REMOTES[@]} -eq 1 ] || return
    echo "${REMOTES[0]}"
}

# lk_git_remote_head [REMOTE]
#
# Output the default branch configured on REMOTE (if known).
function lk_git_remote_head() {
    local REMOTE HEAD
    REMOTE=${1:-$(lk_git_remote_singleton)} || lk_warn "no remote" || return
    HEAD=$(git rev-parse --abbrev-ref "$REMOTE/HEAD" -- 2>/dev/null) &&
        [ "$HEAD" != "$REMOTE/HEAD" ] &&
        echo "${HEAD#$REMOTE/}"
}

function lk_git_branch_current() {
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD) &&
        [ "$BRANCH" != HEAD ] &&
        echo "$BRANCH"
}

function lk_git_branch_list_local() {
    lk_require_output \
        git for-each-ref --format="%(refname:short)" refs/heads
}

# lk_git_branch_upstream [BRANCH]
#
# Output upstream ("pull") <REMOTE>/<REMOTE_BRANCH> for BRANCH or the current
# branch.
function lk_git_branch_upstream() {
    lk_require_output -s \
        git rev-parse --abbrev-ref "${1:-}@{upstream}" 2>/dev/null
}

# lk_git_branch_upstream_remote [BRANCH]
#
# Output upstream ("pull") remote for BRANCH or the current branch.
function lk_git_branch_upstream_remote() {
    local UPSTREAM
    UPSTREAM=$(lk_git_branch_upstream "$@") &&
        [[ $UPSTREAM =~ ^([^/]+)/[^/]+$ ]] &&
        echo "${BASH_REMATCH[1]}"
}

# lk_git_branch_push [BRANCH]
#
# Output downstream ("push") <REMOTE>/<REMOTE_BRANCH> for BRANCH or the current
# branch.
function lk_git_branch_push() {
    lk_require_output -s \
        git rev-parse --abbrev-ref "${1:-}@{push}" 2>/dev/null
}

# lk_git_branch_push_remote [BRANCH]
#
# Output downstream ("push") remote for BRANCH or the current branch.
function lk_git_branch_push_remote() {
    local PUSH
    PUSH=$(lk_git_branch_push "$@") &&
        [[ $PUSH =~ ^([^/]+)/[^/]+$ ]] &&
        echo "${BASH_REMATCH[1]}"
}

# lk_git_update_repo_to REMOTE [BRANCH]
function lk_git_update_repo_to() {
    local REMOTE BRANCH UPSTREAM _BRANCH BEHIND _UPSTREAM
    [ $# -eq 2 ] || lk_usage "\
Usage: $(lk_myself -f) REMOTE [BRANCH]" || return
    REMOTE=$1
    _lk_git fetch --quiet --prune --prune-tags "$REMOTE" ||
        lk_warn "unable to fetch from remote: $REMOTE" ||
        return
    BRANCH=${2:-$(lk_git_remote_head "$REMOTE")} ||
        lk_warn "no default branch for remote: $REMOTE" || return
    UPSTREAM=$REMOTE/$BRANCH
    _BRANCH=$(lk_git_branch_current) || _BRANCH=
    unset LK_GIT_REPO_UPDATED
    if lk_git_branch_list_local |
        grep -Fx "$BRANCH" >/dev/null; then
        BEHIND=$(git rev-list --count "$BRANCH..$UPSTREAM")
        if [ "$BEHIND" -gt 0 ]; then
            git merge-base --is-ancestor "$BRANCH" "$UPSTREAM" ||
                lk_warn "local branch $BRANCH has diverged from $UPSTREAM" ||
                return
            lk_console_detail \
                "Updating $LK_BOLD$BRANCH$LK_RESET ($BEHIND $(lk_maybe_plural \
                    "$BEHIND" commit commits) behind)"
            LK_GIT_REPO_UPDATED=1
            if [ "$_BRANCH" = "$BRANCH" ]; then
                _lk_git merge --ff-only "$UPSTREAM"
            else
                # Fast-forward local BRANCH (e.g. 'develop') to UPSTREAM
                # ('origin/develop') without checking it out
                _lk_git fetch . "$UPSTREAM:$BRANCH"
            fi || return
        fi
        [ "$_BRANCH" = "$BRANCH" ] || {
            lk_console_detail \
                "Switching ${_BRANCH:+from $LK_BOLD$_BRANCH$LK_RESET }to $LK_BOLD$BRANCH$LK_RESET"
            LK_GIT_REPO_UPDATED=1
            _lk_git checkout "$BRANCH" || return
        }
        _UPSTREAM=$(lk_git_branch_upstream) || _UPSTREAM=
        [ "$_UPSTREAM" = "$UPSTREAM" ] || {
            lk_console_detail \
                "Updating remote-tracking branch for $LK_BOLD$BRANCH$LK_RESET"
            _lk_git branch --set-upstream-to "$UPSTREAM"
        }
    else
        lk_console_detail \
            "Switching ${_BRANCH:+from $LK_BOLD$_BRANCH$LK_RESET }to $REMOTE/$LK_BOLD$BRANCH$LK_RESET"
        LK_GIT_REPO_UPDATED=1
        _lk_git checkout -b "$BRANCH" --track "$UPSTREAM"
    fi
}

# lk_git_get_repos ARRAY [DIR...]
#
# Populate ARRAY with the path to the top-level working directory of each git
# repository found in DIR or the current directory.
function lk_git_get_repos() {
    local _LK_GIT_REPO _LK_GIT_ROOTS=(.) _lk_i=0
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    [ $# -lt 2 ] || {
        lk_paths_exist "${@:2}" || lk_warn "directory not found" || return
        _LK_GIT_ROOTS=("${@:2}")
        lk_resolve_files _LK_GIT_ROOTS
    }
    eval "$1=()"
    while IFS= read -rd '' _LK_GIT_REPO; do
        lk_git_is_work_tree "$_LK_GIT_REPO" || continue
        eval "$1[$((_lk_i++))]=\$_LK_GIT_REPO"
    done < <(
        find -L "${_LK_GIT_ROOTS[@]}" \
            -type d -exec test -d "{}/.git" \; -print0 -prune |
            sort -z
    )
}

function lk_git_with_repos() {
    local PARALLEL GIT_SSH_COMMAND REPO_COMMAND FD REPO ERROR_COUNT=0 \
        REPOS=(${LK_GIT_REPOS[@]+"${LK_GIT_REPOS[@]}"})
    [ "${1:-}" != -p ] || {
        ! lk_bash_at_least 4 3 || {
            PARALLEL=1
            export GIT_SSH_COMMAND="ssh -o ControlPath=none"
        }
        shift
    }
    REPO_COMMAND=("$@")
    [ $# -gt 0 ] || lk_usage "\
Usage: $(lk_myself -f) [-p] COMMAND [ARG...]

For each Git repository in the directory hierarchy rooted at \".\", run COMMAND in
the working tree's top-level directory. If -p is set, process multiple
repositories simultaneously." || return
    if [ ${#REPOS[@]} -gt 0 ]; then
        lk_test_many lk_git_is_top_level "${REPOS[@]}" ||
            lk_warn "each element of LK_GIT_REPOS must be the top-level directory \
of a working tree" || return
        lk_resolve_files REPOS
    else
        lk_git_is_quiet || lk_console_message "Finding repositories"
        lk_git_get_repos REPOS
        [ ${#REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    fi
    lk_git_is_quiet || {
        lk_console_detail "Command:" $'\n'"${REPO_COMMAND[*]}"
        lk_echo_array REPOS | lk_pretty_path |
            lk_console_detail_list "Repositories:" repo repos
        lk_confirm "Proceed?" Y || return
    }
    if lk_is_true PARALLEL; then
        FD=$(lk_next_fd) &&
            eval "exec $FD>&2 2>/dev/null" || return
        for REPO in "${REPOS[@]}"; do
            (
                exec 2>&"$FD" &&
                    cd "$REPO" || exit
                EXIT_STATUS=0
                SH=$(lk_get_outputs_of "${REPO_COMMAND[@]}") ||
                    EXIT_STATUS=$?
                eval "$SH" || exit
                lk_git_is_quiet && [ "$EXIT_STATUS" -eq 0 ] || echo "$(
                    unset _LK_FD
                    LK_TTY_NO_FOLD=1
                    {
                        lk_console_item "Processed:" "$REPO"
                        [ "$EXIT_STATUS" -eq 0 ] ||
                            lk_console_error \
                                "Exit status:" "$EXIT_STATUS"
                        [ -z "$_STDOUT" ] ||
                            LK_TTY_COLOUR2=$LK_GREEN \
                                lk_console_detail "Output:" \
                                $'\n'"$_STDOUT"
                        [ -z "$_STDERR" ] ||
                            LK_TTY_COLOUR2=$LK_RED \
                                lk_console_detail "Error output:" \
                                $'\n'"$_STDERR"
                    } 2>&1
                )" >&"$FD"
                exit "$EXIT_STATUS"
            ) &
        done
        eval "exec 2>&$FD $FD>&-"
        while [ -n "$(jobs -p)" ]; do
            wait -n 2>/dev/null || ((++ERROR_COUNT))
        done
    else
        for REPO in "${REPOS[@]}"; do
            lk_git_is_quiet || lk_console_item "Processing" "$REPO"
            (cd "$REPO" &&
                "${REPO_COMMAND[@]}") || ((++ERROR_COUNT))
        done
    fi
    lk_git_is_quiet || {
        [ "$ERROR_COUNT" -eq 0 ] &&
            LK_TTY_NO_FOLD=1 lk_console_success "${REPO_COMMAND[*]}" \
                "executed without error in ${#REPOS[@]} $(lk_maybe_plural \
                    ${#REPOS[@]} repository repositories)" ||
            LK_TTY_NO_FOLD=1 lk_console_error "${REPO_COMMAND[*]}" \
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
    local i REF HASH BEHIND ANCESTORS=()
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

lk_provide git

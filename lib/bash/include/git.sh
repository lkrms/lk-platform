#!/bin/bash

# shellcheck disable=SC2015,SC2034,SC2086,SC2120,SC2164,SC2207

function _lk_git() {
    if [ -n "${LK_GIT_USER:-}" ]; then
        sudo -H -u "$LK_GIT_USER" git "$@"
    else
        lk_maybe_sudo git "$@"
    fi
}

function lk_git_cd() {
    [ $# -eq 0 ] || cd "$1"
}

function lk_git_is_quiet() {
    [ -n "${LK_GIT_QUIET:-}" ]
}

function lk_git_is_work_tree() {
    local RESULT
    RESULT=$(lk_git_cd "$@" &&
        git rev-parse --is-inside-work-tree 2>/dev/null) &&
        lk_is_true RESULT
}

function lk_git_is_submodule() {
    local RESULT
    RESULT=$(lk_git_cd "$@" &&
        git rev-parse --show-superproject-working-tree) &&
        [ -n "$RESULT" ]
}

function lk_git_is_top_level() {
    local RESULT
    RESULT=$(lk_git_cd "$@" && git rev-parse --show-prefix) &&
        [ -z "$RESULT" ]
}

function lk_git_is_project_top_level() {
    (lk_git_cd "$@" &&
        lk_git_is_work_tree && ! lk_git_is_submodule && lk_git_is_top_level)
}

function lk_git_is_clean() {
    local NO_REFRESH
    [ "${1:-}" != -n ] || { NO_REFRESH=1 && shift; }
    (lk_git_cd "$@" &&
        { lk_is_true NO_REFRESH || _lk_git update-index --refresh; } &&
        git diff-index --quiet HEAD --) >/dev/null
}

function lk_git_remote_singleton() {
    local REMOTES
    REMOTES=($(git remote)) && [ ${#REMOTES[@]} -eq 1 ] || return
    echo "${REMOTES[0]}"
}

# lk_git_remote_head [REMOTE]
#
# Output the default branch configured on REMOTE (if known).
function lk_git_remote_head() {
    local REMOTE HEAD
    REMOTE=${1:-$(lk_git_remote_singleton)} || lk_warn "no remote" || return
    HEAD=$(git rev-parse --abbrev-ref "$REMOTE/HEAD" 2>/dev/null) &&
        [ "$HEAD" != "$REMOTE/HEAD" ] &&
        echo "${HEAD#$REMOTE/}"
}

function lk_git_branch_current() {
    local BRANCH
    BRANCH=$(git rev-parse --abbrev-ref HEAD) && [ "$BRANCH" != HEAD ] &&
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
    PUSH=$(lk_git_branch_push "$@") && [[ $PUSH =~ ^([^/]+)/[^/]+$ ]] &&
        echo "${BASH_REMATCH[1]}"
}

function lk_git_ref() {
    git rev-parse --short HEAD
}

# lk_git_provision_repo [OPTIONS] REMOTE_URL DIR
function lk_git_provision_repo() {
    local OPTIND OPTARG OPT SHARE OWNER GROUP BRANCH NAME LK_USAGE \
        LK_SUDO=1 LK_GIT_USER
    unset SHARE
    LK_USAGE="\
Usage: $(lk_myself -f) [OPTIONS] REMOTE_URL DIR

Options:
  -s                            make repository group-shareable
  -o OWNER|OWNER:GROUP|:GROUP   set ownership
  -b BRANCH                     check out BRANCH
  -n NAME                       use NAME instead of REMOTE_URL in messages"
    while getopts ":so:b:n:" OPT; do
        case "$OPT" in
        s)
            SHARE=
            ;;
        o)
            [ -n "$OPTARG" ] &&
                [[ $OPTARG =~ ^([-a-z0-9_]+\$?)?(:([-a-z0-9_]+\$?))?$ ]] ||
                lk_warn "invalid owner: $OPTARG" || lk_usage || return
            OWNER=${BASH_REMATCH[1]}
            GROUP=${BASH_REMATCH[3]}
            LK_GIT_USER=$OWNER
            ;;
        b)
            BRANCH=$OPTARG
            ;;
        n)
            NAME=$OPTARG
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -eq 2 ] || lk_usage || return
    lk_install -d -m ${SHARE+02775} ${SHARE-00755} \
        ${OWNER:+-o "$OWNER"} ${GROUP:+-g "$GROUP"} "$2" || return
    if [ -z "$(ls -A "$2")" ]; then
        lk_console_item "Installing $NAME to" "$2"
        (
            umask ${SHARE+002} ${SHARE-022} &&
                _lk_git clone \
                    ${BRANCH:+-b "$BRANCH"} "$1" "$2"
        )
    else
        lk_console_item "Updating $NAME in" "$2"
        (
            OWNER=${OWNER:-}${GROUP:+:${GROUP:-}}
            if [ -n "$OWNER" ]; then
                lk_maybe_sudo chown -R "$OWNER" "$2" || exit
            fi
            umask ${SHARE+002} ${SHARE-022} &&
                cd "$2" || exit
            REMOTE=$(git remote) &&
                [ "$REMOTE" = origin ] &&
                REMOTE_URL=$(git remote get-url origin 2>/dev/null) &&
                [ "$REMOTE_URL" = "$1" ] || {
                lk_console_detail "Resetting remotes"
                for REMOTE_NAME in $REMOTE; do
                    _lk_git remote remove "$REMOTE_NAME" || exit
                done
                _lk_git remote add origin "$1" || exit
            }
            lk_git_update_repo_to origin "${BRANCH:-}"
        )
    fi
}

# lk_git_fast_forward_branch [-f] BRANCH UPSTREAM
function lk_git_fast_forward_branch() {
    local FORCE BEHIND TAG _BRANCH
    unset FORCE
    [ "${1:-}" != -f ] || { FORCE= && shift; }
    BEHIND=$(git rev-list --count "$1..$2") || return
    if [ "$BEHIND" -gt 0 ]; then
        git merge-base --is-ancestor "$1" "$2" && unset FORCE ||
            { [ -n "${FORCE+1}" ] && lk_git_is_clean &&
                TAG=diverged-$1-$(lk_git_ref) && _lk_git tag -f "$TAG" &&
                lk_console_warning "Tag added:" "$TAG"; } ||
            lk_console_warning -r "Local branch $1 has diverged from $2" ||
            return
        _BRANCH=$(lk_git_branch_current) || return
        lk_console_detail \
            "${FORCE-Updating}${FORCE+Resetting} $1 ($BEHIND $(lk_maybe_plural \
                "$BEHIND" commit commits) behind${FORCE+, diverged})"
        LK_GIT_REPO_UPDATED=1
        if [ "$_BRANCH" = "$1" ]; then
            _lk_git ${FORCE-merge --ff-only}${FORCE+reset --hard} "$2"
        else
            # Fast-forward local BRANCH (e.g. 'develop') to UPSTREAM
            # ('origin/develop') without checking it out
            _lk_git ${FORCE-fetch . "$2:$1"}${FORCE+branch -f "$1" "$2"}
        fi
    fi
}

# lk_git_update_repo
#
# Fetch from all remotes and fast-forward each branch with a remote-tracking
# branch it has not diverged from.
function lk_git_update_repo() {
    local ERRORS=0 REMOTE BRANCH UPSTREAM
    REMOTE=$1
    for REMOTE in $(git remote); do
        _lk_git fetch --quiet --prune "$REMOTE" ||
            lk_console_warning -r "Unable to fetch from remote:" "$REMOTE" ||
            ((++ERRORS))
    done
    for BRANCH in $(lk_git_branch_list_local); do
        UPSTREAM=$(lk_git_branch_upstream "$BRANCH") ||
            lk_console_warning -r "No upstream for branch:" "$BRANCH" || {
            ((++ERRORS))
            continue
        }
        lk_git_fast_forward_branch "$BRANCH" "$UPSTREAM" ||
            ((++ERRORS))
    done
    [ "$ERRORS" -eq 0 ]
}

# lk_git_update_repo_to [-f] REMOTE [BRANCH]
function lk_git_update_repo_to() {
    local FORCE REMOTE BRANCH UPSTREAM _BRANCH BEHIND _UPSTREAM
    unset FORCE
    [ "${1:-}" != -f ] || { FORCE= && shift; }
    [ $# -ge 1 ] || lk_usage "\
Usage: $(lk_myself -f) [-f] REMOTE [BRANCH]" || return
    REMOTE=$1
    _lk_git fetch --quiet --prune "$REMOTE" ||
        lk_warn "unable to fetch from remote: $REMOTE" ||
        return
    BRANCH=${2:-$(lk_git_remote_head "$REMOTE")} ||
        lk_warn "no default branch for remote: $REMOTE" || return
    UPSTREAM=$REMOTE/$BRANCH
    _BRANCH=$(lk_git_branch_current) || _BRANCH=
    unset LK_GIT_REPO_UPDATED
    if lk_git_branch_list_local |
        grep -Fx "$BRANCH" >/dev/null; then
        lk_git_fast_forward_branch ${FORCE+-f} "$BRANCH" "$UPSTREAM" || return
        [ "$_BRANCH" = "$BRANCH" ] || {
            lk_console_detail "Switching ${_BRANCH:+from $_BRANCH }to $BRANCH"
            LK_GIT_REPO_UPDATED=1
            _lk_git checkout "$BRANCH" || return
        }
        _UPSTREAM=$(lk_git_branch_upstream) || _UPSTREAM=
        [ "$_UPSTREAM" = "$UPSTREAM" ] || {
            lk_console_detail "Updating remote-tracking branch for $BRANCH"
            _lk_git branch --set-upstream-to "$UPSTREAM"
        }
    else
        lk_console_detail \
            "Switching ${_BRANCH:+from $_BRANCH }to $REMOTE/$BRANCH"
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

function _lk_git_do_with_repo() {
    local SH EXIT_STATUS=0
    SH=$(lk_get_outputs_of "${REPO_COMMAND[@]}") ||
        EXIT_STATUS=$?
    eval "$SH" || return
    lk_git_is_quiet && [ "$EXIT_STATUS" -eq 0 ] || echo "$(
        unset _LK_FD
        LK_TTY_NO_FOLD=1
        {
            lk_git_is_quiet &&
                lk_console_item "Command failed in" "$REPO" ||
                lk_console_item "Processed:" "$REPO"
            [ "$EXIT_STATUS" -eq 0 ] ||
                lk_console_error "Exit status:" "$EXIT_STATUS"
            [ -z "$_STDOUT" ] ||
                LK_TTY_COLOUR2=$LK_GREEN \
                    lk_console_detail "Output:" $'\n'"$_STDOUT"
            [ -z "$_STDERR" ] ||
                LK_TTY_COLOUR2=$([ "$EXIT_STATUS" -eq 0 ] &&
                    echo "$LK_YELLOW" ||
                    echo "$LK_RED") \
                    lk_console_detail "Error output:" $'\n'"$_STDERR"
        } 2>&1
    )"
    return "$EXIT_STATUS"
}

function lk_git_with_repos() {
    local PARALLEL GIT_SSH_COMMAND REPO_COMMAND FD REPO ERROR_COUNT=0 NOUN \
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

For each Git repository found in the current directory, run COMMAND in the
working tree's top-level directory. If -p is set, process multiple repositories
simultaneously (Bash 4.3+ only)." || return
    if [ ${#REPOS[@]} -gt 0 ]; then
        lk_test_many lk_git_is_top_level "${REPOS[@]}" ||
            lk_warn "each element of LK_GIT_REPOS must be the top-level \
directory of a working tree" || return
        lk_resolve_files REPOS
    else
        lk_git_get_repos REPOS
        [ ${#REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    fi
    lk_git_is_quiet || {
        lk_echo_array REPOS | lk_pretty_path |
            lk_console_list "Repositories:" repo repos
        lk_console_item "Command to run:" \
            $'\n'"$(lk_quote_args "${REPO_COMMAND[@]}")"
        lk_confirm "Proceed?" Y || return
    }
    [ ${#REPOS[@]} -gt 1 ] || unset PARALLEL
    NOUN="${#REPOS[@]} $(lk_maybe_plural ${#REPOS[@]} repo repos)"
    if lk_is_true PARALLEL; then
        lk_git_is_quiet ||
            lk_console_message "Processing $NOUN in parallel"
        FD=$(lk_next_fd) &&
            eval "exec $FD>&2 2>/dev/null" || return
        for REPO in "${REPOS[@]}"; do
            (
                exec 2>&"$FD" &&
                    cd "$REPO" &&
                    _lk_git_do_with_repo >&"$FD"
            ) &
        done
        eval "exec 2>&$FD $FD>&-"
        while [ -n "$(jobs -p)" ]; do
            wait -n 2>/dev/null || ((++ERROR_COUNT))
        done
    else
        lk_git_is_quiet ||
            lk_console_message "Processing $NOUN"
        for REPO in "${REPOS[@]}"; do
            (cd "$REPO" &&
                _lk_git_do_with_repo) || ((++ERROR_COUNT))
        done
    fi
    lk_git_is_quiet || {
        [ "$ERROR_COUNT" -eq 0 ] &&
            LK_TTY_NO_FOLD=1 \
                lk_console_success "Command succeeded in $NOUN" ||
            LK_TTY_NO_FOLD=1 \
                lk_console_error "Command failed in $ERROR_COUNT of $NOUN"
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
    REPO_ROOT=$(git rev-parse --show-toplevel) &&
        COMMIT=$(git rev-list -1 --oneline HEAD) || return
    lk_console_detail "Repository:" "$REPO_ROOT"
    lk_console_detail "HEAD refers to:" "$COMMIT"
    lk_confirm \
        "Uncommitted changes will be permanently deleted. Proceed?" N || return
    rm -fv "$REPO_ROOT/.git/index" &&
        git checkout --force --no-overlay HEAD -- "$REPO_ROOT" &&
        lk_console_success "Checkout completed successfully"
}

lk_provide git

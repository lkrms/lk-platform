#!/bin/bash

function _lk_git() {
    local VAR ENV=() SOCK_OWNER SSH_OPTIONS=(ClearAllForwardings=yes
        ${_LK_GIT_SSH_OPTIONS+"${_LK_GIT_SSH_OPTIONS[@]}"})
    if [ "${1-}" = -1 ]; then
        set -- "${@:2}"
    else
        set -- git "$@"
    fi
    for VAR in "${!GIT_@}"; do
        ! lk_is_exported "$VAR" || ENV[${#ENV[@]}]="$VAR=${!VAR}"
    done
    [ "${SSH_AUTH_SOCK:+1}${_LK_GIT_USER:+1}" != 11 ] ||
        ! SOCK_OWNER=$(lk_file_owner "$SSH_AUTH_SOCK" 2>/dev/null) ||
        [ "$SOCK_OWNER" != "$_LK_GIT_USER" ] ||
        ENV[${#ENV[@]}]="SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
    set -- env \
        ${ENV+"${ENV[@]}"} \
        GIT_SSH_COMMAND="ssh$(printf ' -o %s' "${SSH_OPTIONS[@]}")" \
        "$@"
    if [ -n "${_LK_GIT_USER-}" ]; then
        lk_run_as "$_LK_GIT_USER" "$@"
    else
        lk_maybe_sudo "$@"
    fi
} #### Reviewed: 2021-05-25

function _lk_git_cd() {
    [ $# -eq 0 ] || cd "$1"
}

function _lk_git_is_quiet() {
    [ -n "${_LK_GIT_QUIET-}" ]
}

# lk_git_is_work_tree [DIR]
function lk_git_is_work_tree() {
    local RESULT
    RESULT=$(_lk_git_cd "$@" &&
        git rev-parse --is-inside-work-tree 2>/dev/null) &&
        lk_is_true RESULT
}

# lk_git_is_submodule [DIR]
function lk_git_is_submodule() {
    local RESULT
    RESULT=$(_lk_git_cd "$@" &&
        git rev-parse --show-superproject-working-tree) &&
        [ -n "$RESULT" ]
}

# lk_git_is_top_level [DIR]
function lk_git_is_top_level() {
    local RESULT
    RESULT=$(_lk_git_cd "$@" && git rev-parse --show-prefix) &&
        [ -z "$RESULT" ]
}

# lk_git_is_project_top_level [DIR]
function lk_git_is_project_top_level() {
    (_lk_git_cd "$@" &&
        lk_git_is_work_tree && ! lk_git_is_submodule && lk_git_is_top_level)
}

# lk_git_is_clean [-n] [DIR]
#
# Return true if there are no uncommitted changes in the repository. If -n is
# set, skip the index update.
function lk_git_is_clean() {
    local NO_REFRESH
    [ "${1-}" != -n ] || { NO_REFRESH=1 && shift; }
    (_lk_git_cd "$@" &&
        { [ -n "${NO_REFRESH-}" ] ||
            _lk_git update-index --refresh; } &&
        git diff-index --quiet HEAD --) >/dev/null
}

# lk_git_list_changes [-n] [DIR]
#
# List uncommitted changes in the repository. If -n is set, skip the index
# update.
function lk_git_list_changes() {
    local NO_REFRESH
    [ "${1-}" != -n ] || { NO_REFRESH=1 && shift; }
    (_lk_git_cd "$@" &&
        { [ -n "${NO_REFRESH-}" ] ||
            _lk_git update-index --refresh >/dev/null || true; } &&
        git diff-index --name-status HEAD --)
}

# lk_git_list_untracked [DIR]
function lk_git_list_untracked() {
    (_lk_git_cd "$@" &&
        git ls-files --others --exclude-standard --directory)
}

# lk_git_has_untracked [DIR]
function lk_git_has_untracked() {
    lk_require_output -q lk_git_list_untracked "$@"
}

# lk_git_stash_list [DIR]
function lk_git_stash_list() {
    (_lk_git_cd "$@" &&
        git stash list --format="%gd")
}

# lk_git_has_stash [DIR]
function lk_git_has_stash() {
    lk_require_output -q lk_git_stash_list "$@"
}

# lk_git_remote_is_skipped [REMOTE]
function lk_git_remote_is_skipped() {
    {
        git config "remote.$1.skipDefaultUpdate" || true
        git config "remote.$1.skipFetchAll" || true
    } | grep -Fx true >/dev/null
}

function lk_git_remote_skip() {
    [ -n "${1-}" ] || lk_usage "Usage: $FUNCNAME REMOTE" || return
    lk_confirm "Exclude remote '$1' from fetch and push?" Y || return
    _lk_git config --type=bool "remote.$1.skipDefaultUpdate" 1
    _lk_git config --type=bool "remote.$1.skipFetchAll" 1
}

function lk_git_remote_singleton() {
    local REMOTES
    REMOTES=($(git remote)) && [ ${#REMOTES[@]} -eq 1 ] || return
    echo "${REMOTES[0]}"
}

# lk_git_remote_from_url [-E] URL
#
# Print the name of each remote with the given URL. If -E is set, treat URL as a
# regular expression.
function lk_git_remote_from_url() {
    local VALUE REGEX='^remote\.(.+)\.url$'
    unset VALUE
    [ "${1-}" != -E ] || { shift && VALUE=${1-}; }
    [ $# -gt 0 ] || lk_usage "Usage: $FUNCNAME [-E] URL" || return
    VALUE=${VALUE-$(lk_escape_ere "${1-}")} &&
        git config --local --name-only --get-regexp "$REGEX" "$VALUE" |
        lk_require_output sed -E "s/$REGEX/\1/"
}

# lk_git_list_push_urls REMOTE
function lk_git_list_push_urls() {
    git remote get-url --push --all "$1"
}

# lk_git_list_push_remotes REMOTE
function lk_git_list_push_remotes() {
    { { git config --get-all "remote.$1.pushurl" ||
        git config --get "remote.$1.url"; } |
        lk_xargs lk_git_remote_from_url || true; } |
        lk_require_output cat
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

# lk_git_branch_list_remote [REMOTE]
function lk_git_branch_list_remote() {
    local REMOTE _REMOTE
    REMOTE=${1:-$(lk_git_remote_singleton)} || lk_warn "no remote" || return
    _REMOTE=$(lk_escape_ere "$REMOTE")
    git for-each-ref --format="%(refname:short)" "refs/remotes/$REMOTE" |
        lk_require_output \
            sed -E -e "/^$_REMOTE\/HEAD\$/d" -e "s/^$_REMOTE\///"
}

# lk_git_branch_upstream [BRANCH]
#
# Output upstream ("pull") <REMOTE>/<REMOTE_BRANCH> for BRANCH or the current
# branch.
function lk_git_branch_upstream() {
    lk_require_output -s \
        git rev-parse --abbrev-ref "${1-}@{upstream}" 2>/dev/null
}

# lk_git_branch_upstream_remote [BRANCH]
#
# Output upstream ("pull") remote for BRANCH or the current branch.
function lk_git_branch_upstream_remote() {
    local UPSTREAM
    UPSTREAM=$(lk_git_branch_upstream "$@") &&
        [[ $UPSTREAM =~ ^([^/]+)/([^/]+(/[^/]+)*)$ ]] &&
        echo "${BASH_REMATCH[1]}"
}

# lk_git_branch_push [BRANCH]
#
# Output downstream ("push") <REMOTE>/<REMOTE_BRANCH> for BRANCH or the current
# branch.
function lk_git_branch_push() {
    lk_require_output -s \
        git rev-parse --abbrev-ref "${1-}@{push}" 2>/dev/null ||
        lk_git_branch_upstream "$@"
}

# lk_git_branch_push_remote [BRANCH]
#
# Output downstream ("push") remote for BRANCH or the current branch.
function lk_git_branch_push_remote() {
    local PUSH
    PUSH=$(lk_git_branch_push "$@") &&
        [[ $PUSH =~ ^([^/]+)/([^/]+(/[^/]+)*)$ ]] &&
        echo "${BASH_REMATCH[1]}"
}

function lk_git_ref() {
    git rev-parse --short HEAD
}

# lk_git_provision_repo [OPTIONS] REMOTE_URL DIR
function lk_git_provision_repo() {
    local OPTIND OPTARG OPT FORCE REMOTE SHARE OWNER GROUP BRANCH NAME \
        LK_USAGE LK_SUDO=1 _LK_GIT_USER \
        GIT_DIR GIT_WORK_TREE
    unset FORCE SHARE
    LK_USAGE="\
Usage: $FUNCNAME [OPTIONS] REMOTE_URL DIR

Options:
  -f                        use \`git reset --hard\` if branches have diverged
  -r NAME                   use NAME instead of origin as the remote name
  -s                        make repository group-shareable
  -o OWNER|[OWNER]:GROUP    set ownership
  -b BRANCH                 check out BRANCH
  -n NAME                   use NAME instead of REMOTE_URL in messages"
    while getopts ":fr:so:b:n:" OPT; do
        case "$OPT" in
        f)
            FORCE=
            ;;
        r)
            REMOTE=$OPTARG
            ;;
        s)
            SHARE=
            ;;
        o)
            [ -n "$OPTARG" ] &&
                [[ $OPTARG =~ ^([-a-z0-9_]+\$?)?(:([-a-z0-9_]+\$?))?$ ]] ||
                lk_warn "invalid owner: $OPTARG" || lk_usage || return
            OWNER=${BASH_REMATCH[1]}
            GROUP=${BASH_REMATCH[3]}
            _LK_GIT_USER=$OWNER
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
    NAME=${NAME:-$1}
    lk_install -d -m ${SHARE+02775} ${SHARE-00755} \
        ${OWNER:+-o "$OWNER"} ${GROUP:+-g "$GROUP"} "$2" || return
    if [ -z "$(ls -A "$2")" ]; then
        lk_console_item "Installing $NAME to" "$2"
        (umask ${SHARE+002} ${SHARE-022} &&
            _lk_git clone \
                ${BRANCH:+-b "$BRANCH"} ${REMOTE:+-o "$REMOTE"} \
                "$1" "$2")
    else
        lk_console_item "Updating $NAME in" "$2"
        (
            OWNER=${OWNER-}${GROUP:+:${GROUP-}}
            if [ -n "$OWNER" ]; then
                lk_elevate chown -R "$OWNER" "$2" || exit
            fi
            umask ${SHARE+002} ${SHARE-022} &&
                cd "$2" || exit
            _REMOTE=$(lk_git_remote_from_url "$1" | head -n1) ||
                { _REMOTE=${REMOTE:-origin} &&
                    if git remote | grep -Fx "$_REMOTE" >/dev/null; then
                        _lk_git remote set-url "$_REMOTE" "$1"
                    else
                        _lk_git remote add "$_REMOTE" "$1"
                    fi; } ||
                lk_warn "unable to add or update remote: $_REMOTE" || exit
            lk_git_update_repo_to ${FORCE+-f} "$_REMOTE" "${BRANCH-}"
        )
    fi || return
    export GIT_DIR=$2/.git GIT_WORK_TREE=$2
    if [ -z "${SHARE+1}" ]; then
        lk_git_config --unset core.sharedRepository
    else
        lk_git_config core.sharedRepository 0664
    fi
} #### Reviewed: 2021-05-25

function _lk_git_branch_check_diverged() {
    git merge-base --is-ancestor "$1" "$2" || {
        local STATUS=$?
        [ -z "${_LK_GIT_ALREADY_WARNED+1}" ] || {
            [[ ,${_LK_GIT_ALREADY_WARNED-}, != *,$1-$2-diverged,* ]] ||
                return "$STATUS"
            _LK_GIT_ALREADY_WARNED+=${_LK_GIT_ALREADY_WARNED:+,}$1-$2-diverged
        }
        lk_console_error "$1 has diverged from $2"
        return "$STATUS"
    }
} #### Reviewed: 2021-05-30

# lk_git_fast_forward_branch [-f] BRANCH UPSTREAM
function lk_git_fast_forward_branch() {
    local FORCE QUIET BEHIND TAG _BRANCH
    unset FORCE QUIET
    [ "${1-}" != -f ] || { FORCE= && shift; }
    ! _lk_git_is_quiet || QUIET=
    BEHIND=$(git rev-list --count "$1..$2") || return
    [ "$BEHIND" -gt 0 ] || return 0
    _lk_git_branch_check_diverged "$1" "$2" && unset FORCE || {
        [ -n "${FORCE+1}" ] || return
        if lk_git_is_clean; then
            TAG=diverged-$1-$(lk_git_ref) &&
                lk_console_detail "Tagging local HEAD:" "$TAG" &&
                _lk_git tag -f "$TAG" || return
        else
            lk_console_detail "Stashing local changes" &&
                _lk_git stash ${QUIET+--quiet} || return
        fi
    }
    _BRANCH=$(lk_git_branch_current) || return
    lk_console_detail \
        "${FORCE-Updating}${FORCE+Resetting}" "$1 ($BEHIND $(lk_maybe_plural \
            "$BEHIND" commit commits) behind${FORCE+, diverged})"
    LK_GIT_REPO_UPDATED=1
    if [ "$_BRANCH" = "$1" ]; then
        _lk_git ${FORCE-merge --ff-only}${FORCE+reset --hard} \
            ${QUIET+--quiet} "$2"
    else
        # Fast-forward local BRANCH (e.g. 'develop') to UPSTREAM
        # ('origin/develop') without checking it out
        _lk_git ${FORCE-fetch . "$2:$1"}${FORCE+branch -f "$1" "$2"} \
            ${QUIET+--quiet}
    fi
} #### Reviewed: 2021-05-25

# lk_git_push_branch BRANCH DOWNSTREAM
function lk_git_push_branch() {
    local REMOTE REMOTE_BRANCH AHEAD _PATH LOG STALE
    [[ $2 =~ ^([^/]+)/([^/]+(/[^/]+)*)$ ]] ||
        lk_warn "invalid downstream: $2" || return
    REMOTE=${BASH_REMATCH[1]}
    REMOTE_BRANCH=${BASH_REMATCH[2]}
    AHEAD=$(git rev-list --count "$2..$1") &&
        _PATH=$(pwd | lk_pretty_path) || return
    [ "$AHEAD" -gt 0 ] || return 0
    ! lk_no_input ||
        lk_warn "in $_PATH, cannot push to $2: user input disabled" || return 0
    _lk_git_branch_check_diverged "$2" "$1" || return
    LOG=$(git log --reverse \
        --oneline --decorate --color=always "$2..$1") || return
    lk_tty_dump \
        "$LOG" \
        "Not pushed:" \
        "($AHEAD $(lk_maybe_plural "$AHEAD" commit commits))"
    lk_mapfile PUSH_URLS <(lk_git_list_push_urls "$REMOTE" 2>/dev/null)
    [ ${#PUSH_URLS[@]} -eq 0 ] ||
        lk_console_detail "Push $(lk_maybe_plural \
            ${#PUSH_URLS[@]} URL URLs):" \
            $'\n'"$(lk_echo_array PUSH_URLS)"
    lk_confirm "In $LK_BOLD$_PATH$LK_RESET, \
push $LK_BOLD$1$LK_RESET to $LK_BOLD$2$LK_RESET?" Y ||
        return 0
    lk_console_detail \
        "Pushing to $2 ($AHEAD $(lk_maybe_plural \
            "$AHEAD" commit commits) ahead)"
    _lk_git push --tags "$REMOTE" "$1:$REMOTE_BRANCH" &&
        LK_GIT_REPO_UPDATED=1 || return
    # Fetch from other remotes configured to receive this push
    ! STALE=($(lk_git_list_push_remotes "$REMOTE" |
        grep -Fxv "$REMOTE")) ||
        lk_git_fetch -q "${STALE[@]}"
}

# lk_git_fetch [-q] [REMOTE...]
function lk_git_fetch() {
    local IFS QUIET ERRORS=0 REMOTES REMOTE
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    REMOTES=$*
    [ $# -gt 0 ] || REMOTES=$(git remote) || return
    for REMOTE in $REMOTES; do
        [ $# -gt 0 ] || ! lk_git_remote_is_skipped "$REMOTE" || continue
        _lk_git fetch --quiet --prune "$REMOTE" || {
            [ -n "${QUIET-}" ] || lk_console_error \
                "Unable to fetch from remote:" "$REMOTE"
            ((++ERRORS))
        }
    done
    [ "$ERRORS" -eq 0 ]
}

# lk_git_update_repo [-s]
#
# Fetch from all remotes and fast-forward each branch with a remote-tracking
# branch it has not diverged from. If -s is set, skip fetching from remotes.
function lk_git_update_repo() {
    local FETCH=1 ERRORS=0 REMOTE BRANCH UPSTREAM
    [ "${1-}" != -s ] || { FETCH= && shift; }
    [ -z "$FETCH" ] || {
        lk_console_message "Fetching from all remotes"
        lk_git_fetch || ((++ERRORS))
    }
    for BRANCH in $(lk_git_branch_list_local); do
        UPSTREAM=$(lk_git_branch_upstream "$BRANCH") ||
            lk_console_warning -r -n "No upstream:" "$BRANCH" ||
            continue
        lk_git_fast_forward_branch "$BRANCH" "$UPSTREAM" ||
            ((++ERRORS))
    done
    [ "$ERRORS" -eq 0 ]
}

function lk_git_update_remote() {
    local QUIET ERRORS=0 BRANCHES REMOTES BRANCH _PUSH PUSH=() REMOTE RBRANCHES
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    BRANCHES=$(lk_git_branch_list_local) &&
        REMOTES=$(git remote) || return
    for BRANCH in $BRANCHES; do
        _PUSH=$(lk_git_branch_push "$BRANCH") || {
            [ -n "${QUIET-}" ] ||
                lk_console_warning -n "No push destination:" "$BRANCH"
            continue
        }
        PUSH[${#PUSH[@]}]=$(lk_quote_args "$BRANCH" "$_PUSH")
        lk_git_push_branch "$BRANCH" "$_PUSH" ||
            ((++ERRORS))
    done
    for REMOTE in $REMOTES; do
        ! lk_git_remote_is_skipped "$REMOTE" || continue
        RBRANCHES=$(lk_git_branch_list_remote "$REMOTE") &&
            RBRANCHES=$(comm -12 \
                <(echo "$BRANCHES" | sort) \
                <(echo "$RBRANCHES" | sort)) &&
            [ -n "$RBRANCHES" ] || continue
        for BRANCH in $RBRANCHES; do
            _PUSH=$(lk_quote_args "$BRANCH" "$REMOTE/$BRANCH")
            ! lk_in_array "$_PUSH" PUSH || continue
            PUSH[${#PUSH[@]}]=$_PUSH
            lk_git_push_branch "$BRANCH" "$REMOTE/$BRANCH" ||
                ((++ERRORS))
        done
    done
    [ "$ERRORS" -eq 0 ]
}

# lk_git_update_repo_to [-f] REMOTE [BRANCH]
function lk_git_update_repo_to() {
    local FORCE REMOTE BRANCH UPSTREAM _BRANCH BEHIND _UPSTREAM
    unset FORCE
    [ "${1-}" != -f ] || { FORCE= && shift; }
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME [-f] REMOTE [BRANCH]" || return
    REMOTE=$1
    _lk_git fetch --quiet --prune "$REMOTE" ||
        lk_warn "unable to fetch from remote: $REMOTE" ||
        return
    _BRANCH=$(lk_git_branch_current) || _BRANCH=
    { BRANCH=${2:-$_BRANCH} && [ -n "$BRANCH" ]; } ||
        BRANCH=$(lk_git_remote_head "$REMOTE") ||
        lk_warn "no default branch for remote: $REMOTE" || return
    UPSTREAM=$REMOTE/$BRANCH
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
    local SH STATUS=0
    if [ -z "${STDOUT-}" ]; then
        SH=$(lk_get_outputs_of "${REPO_COMMAND[@]}") ||
            STATUS=$?
        eval "$SH" || return
        _lk_git_is_quiet && [ "$STATUS" -eq 0 ] || echo "$(
            unset _LK_FD
            _LK_TTY_NO_FOLD=1
            {
                if [ "$STATUS" -eq 0 ]; then
                    _LK_TTY_PREFIX_COLOUR=$LK_BOLD$LK_GREEN \
                        lk_console_item "Processed:" "$_REPO"
                else
                    lk_console_item \
                        "Exit status $STATUS:" "$_REPO" "$LK_BOLD$LK_RED"
                fi
                [ -z "$_STDOUT" ] ||
                    _LK_TTY_COLOUR2=$LK_GREEN \
                        lk_console_detail "Output:" $'\n'"$_STDOUT"
                [ -z "$_STDERR" ] ||
                    _LK_TTY_COLOUR2=$([ "$STATUS" -eq 0 ] &&
                        echo "$LK_YELLOW" ||
                        echo "$LK_RED") \
                        lk_console_detail "Error output:" $'\n'"$_STDERR"
            } 2>&1
        )"
    else
        _LK_TTY_PREFIX_COLOUR=$LK_BOLD$LK_GREEN \
            lk_console_item "Processing" "$_REPO"
        "${REPO_COMMAND[@]}" || {
            STATUS=$?
            [ ${FUNCNAME[2]-} = lk_git_audit_repos ] ||
                lk_console_error "Exit status $STATUS"
        }
    fi
    return "$STATUS"
}

function lk_git_with_repos() {
    local OPTIND OPTARG OPT LK_USAGE PARALLEL STDOUT PROMPT=1 \
        REPO_COMMAND NOUN FD ERR_FILE REPO _REPO ERR_COUNT=0 ERR_REPOS \
        _LK_GIT_SSH_OPTIONS REPOS=(${LK_GIT_REPOS[@]+"${LK_GIT_REPOS[@]}"})
    _LK_GIT_REPO_ERRORS=(${REPOS[@]+"${REPOS[@]}"})
    LK_USAGE="\
Usage: $FUNCNAME [-p|-t] [-y] COMMAND [ARG...]

For each Git repository found in the current directory, run COMMAND in the
working tree's top-level directory. If -p is set, process multiple repositories
simultaneously (Bash 4.3+ only). If -t is set, print the output of each COMMAND
on the standard output. If -y is set, proceed without prompting."
    while getopts ":pty" OPT; do
        case "$OPT" in
        p)
            ! lk_bash_at_least 4 3 || {
                PARALLEL=1
                _LK_GIT_SSH_OPTIONS=(ControlPath=none)
            }
            unset STDOUT
            ;;
        t)
            STDOUT=1
            unset PARALLEL _LK_GIT_SSH_OPTIONS
            ;;
        y)
            unset PROMPT
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -gt 0 ] || lk_usage || return
    REPO_COMMAND=("$@")
    if [ ${#REPOS[@]} -gt 0 ]; then
        lk_test_many lk_git_is_top_level "${REPOS[@]}" ||
            lk_warn "each element of LK_GIT_REPOS must be the top-level \
directory of a working tree" || return
        lk_resolve_files REPOS
    else
        lk_git_get_repos REPOS
        [ ${#REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    fi
    [ -z "${PROMPT-}" ] || lk_no_input || {
        lk_echo_array REPOS | lk_pretty_path |
            lk_console_list "Repositories:" repo repos
        lk_console_item "Command to run:" \
            $'\n'"$(lk_quote_args "${REPO_COMMAND[@]}")"
        lk_confirm "Proceed?" Y || return
    }
    [ ${#REPOS[@]} -gt 1 ] || unset PARALLEL
    NOUN="${#REPOS[@]} $(lk_maybe_plural ${#REPOS[@]} repo repos)"
    if lk_is_true PARALLEL; then
        _lk_git_is_quiet ||
            lk_console_log "Processing $NOUN in parallel"
        FD=$(lk_fd_next) &&
            eval "exec $FD>&2 2>/dev/null" &&
            ERR_FILE=$(lk_mktemp_file) &&
            lk_delete_on_exit "$ERR_FILE" || return
        for REPO in "${REPOS[@]}"; do
            _REPO=$(lk_pretty_path "$REPO")
            (
                exec 2>&"$FD" &&
                    cd "$REPO" &&
                    _lk_git_do_with_repo >&"$FD" ||
                    lk_pass eval 'echo "$_REPO" >>"$ERR_FILE"'
            ) &
            lk_console_blank
        done
        eval "exec 2>&$FD $FD>&-"
        while [ -n "$(jobs -p)" ]; do
            wait -n 2>/dev/null || ((++ERR_COUNT))
        done
        lk_mapfile ERR_REPOS "$ERR_FILE"
    else
        _lk_git_is_quiet ||
            lk_console_log "Processing $NOUN"
        for REPO in "${REPOS[@]}"; do
            _REPO=$(lk_pretty_path "$REPO")
            (cd "$REPO" && _lk_git_do_with_repo) ||
                ERR_REPOS[ERR_COUNT++]=$_REPO
            lk_console_blank
        done
    fi
    _lk_git_is_quiet || {
        [ "$ERR_COUNT" -eq 0 ] &&
            _LK_TTY_NO_FOLD=1 \
                lk_console_success "Command succeeded in $NOUN" ||
            _LK_TTY_NO_FOLD=1 \
                lk_console_error "Command failed in $ERR_COUNT of $NOUN:" \
                "$(lk_echo_array ERR_REPOS)"
    }
    _LK_GIT_REPO_ERRORS=(${ERR_REPOS[@]+"${ERR_REPOS[@]}"})
    [ "$ERR_COUNT" -eq 0 ]
}

function lk_git_audit_repo() {
    local SKIP_FETCH ERRORS=0 STASHES _LK_GIT_ALREADY_WARNED=
    [ "${1-}" != -s ] || { SKIP_FETCH=1 && shift; }
    lk_git_update_repo ${SKIP_FETCH:+-s} || ((++ERRORS))
    lk_git_update_remote -q || ((++ERRORS))
    lk_git_is_clean ||
        lk_console_error -r -n "Changed:" \
            $'\n'"$(lk_pass lk_git_list_changes -n)" || ((++ERRORS))
    ! lk_git_has_untracked ||
        lk_console_error -r -n "Untracked:" \
            $'\n'"$(lk_pass lk_git_list_untracked)" || ((++ERRORS))
    STASHES=$(lk_git_stash_list | wc -l) || { STASHES=0 && ((++ERRORS)); }
    [ "$STASHES" -eq 0 ] ||
        lk_console_error -r "Changes in $STASHES $(lk_pass \
            lk_maybe_plural "$STASHES" stash stashes)" || ((++ERRORS))
    [ "$ERRORS" -eq 0 ]
}

# lk_git_audit_repos [-s] [REPO...]
function lk_git_audit_repos() {
    local SKIP_FETCH NOUN _LK_GIT_QUIET=${_LK_GIT_QUIET-1} \
        FETCH_ERRORS=() AUDIT_ERRORS=() \
        LK_GIT_REPOS=(${LK_GIT_REPOS[@]+"${LK_GIT_REPOS[@]}"})
    [ "${1-}" != -s ] || { SKIP_FETCH=1 && shift; }
    [ $# -eq 0 ] || LK_GIT_REPOS=("$@")
    [ ${#LK_GIT_REPOS[@]} -gt 0 ] || lk_git_get_repos LK_GIT_REPOS
    [ ${#LK_GIT_REPOS[@]} -gt 0 ] || lk_warn "no repos found" || return
    NOUN="${#LK_GIT_REPOS[@]} $(lk_maybe_plural ${#LK_GIT_REPOS[@]} repo repos)"
    if ! lk_is_true SKIP_FETCH; then
        lk_echo_array LK_GIT_REPOS |
            lk_console_list "Fetching all remotes:" repo repos
        lk_git_with_repos -py lk_git_fetch ||
            FETCH_ERRORS=(${_LK_GIT_REPO_ERRORS[@]+"${_LK_GIT_REPO_ERRORS[@]}"})
        lk_console_blank
    else
        lk_echo_array LK_GIT_REPOS |
            lk_console_list "Auditing:" repo repos
        lk_console_blank
    fi
    lk_git_with_repos -ty lk_git_audit_repo -s ||
        AUDIT_ERRORS=(${_LK_GIT_REPO_ERRORS[@]+"${_LK_GIT_REPO_ERRORS[@]}"})
    lk_console_message "Audit complete"
    lk_is_true SKIP_FETCH || {
        [ ${#FETCH_ERRORS[@]} -eq 0 ] &&
            _LK_TTY_NO_FOLD=1 \
                lk_console_success "Fetch succeeded in $NOUN" ||
            _LK_TTY_NO_FOLD=1 \
                lk_console_error "Fetch failed in ${#FETCH_ERRORS[@]} of $NOUN:" \
                "$(lk_echo_array FETCH_ERRORS)"
    }
    [ ${#AUDIT_ERRORS[@]} -eq 0 ] &&
        _LK_TTY_NO_FOLD=1 \
            lk_console_success "Checks passed in $NOUN" ||
        _LK_TTY_NO_FOLD=1 \
            lk_console_error "Checks failed in ${#AUDIT_ERRORS[@]} of $NOUN:" \
            "$(lk_echo_array AUDIT_ERRORS)"
    [[ $((${#FETCH_ERRORS[@]} + ${#AUDIT_ERRORS[@]})) -eq 0 ]]
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

# - lk_git_config [-o] [--type=TYPE] NAME VALUE
# - lk_git_config [-o] [--type=TYPE] --unset[-all] NAME
function lk_git_config() {
    local OUTPUT COMMAND=() REGEX
    [ "${1-}" != -o ] || { OUTPUT=1 && shift; }
    [ $# -ge 2 ] ||
        lk_usage "\
Usage: $FUNCNAME [-o] [--type=TYPE] NAME VALUE
   or: $FUNCNAME [-o] [--type=TYPE] --unset[-all] NAME" || return
    case "${*:$#-1:1}" in
    --unset | --unset-all)
        ! git config --local "${@:1:$#-2}" --get "${*:$#}" >/dev/null ||
            COMMAND=(_lk_git config --local "$@")
        ;;

    *)
        REGEX=$(lk_escape_ere "${*:$#}") || return
        git config --local \
            "${@:1:$#-2}" --get "${*:$#-1:1}" "$REGEX" >/dev/null ||
            COMMAND=(_lk_git config --local "$@")
        ;;
    esac
    [ -z "${COMMAND+1}" ] ||
        if [ -n "${OUTPUT-}" ]; then
            lk_quote_args "${COMMAND[@]}"
        else
            "${COMMAND[@]}"
        fi
} #### Reviewed: 2021-05-29

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
    _lk_git config push.default current &&
        _lk_git config remote.pushDefault "$UPSTREAM" &&
        _lk_git config --replace-all "remote.$UPSTREAM.pushUrl" "$REMOTE_URL" &&
        for REMOTE in $(git remote | grep -Fxv "$UPSTREAM"); do
            REMOTE_URL=$(git config "remote.$REMOTE.url") &&
                [ -n "$REMOTE_URL" ] ||
                lk_warn "URL not found for remote $REMOTE" || continue
            lk_console_detail "Adding:" "$REMOTE_URL"
            _lk_git config --add "remote.$UPSTREAM.pushUrl" "$REMOTE_URL"
        done
}

function lk_git_recheckout() {
    local REPO_ROOT COMMIT
    lk_console_message "Preparing to delete the index and check out HEAD again"
    REPO_ROOT=$(git rev-parse --show-toplevel) &&
        COMMIT=$(git rev-list -1 --oneline HEAD) || return
    lk_console_detail "Repository:" "$REPO_ROOT"
    lk_console_detail "HEAD refers to:" "$COMMIT"
    lk_no_input || lk_confirm \
        "Uncommitted changes will be permanently deleted. Proceed?" N || return
    _lk_git -1 rm -fv "$REPO_ROOT/.git/index" &&
        _lk_git checkout --force --no-overlay HEAD -- "$REPO_ROOT" &&
        lk_console_success "Checkout completed successfully"
}

lk_provide git

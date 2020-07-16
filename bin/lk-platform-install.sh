#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2001,SC2015,SC2034

# root privileges are required for access to settings files and startup scripts
# in ~root, /home/*, etc., so elevate immediately rather than waiting for
# lk_elevate to be available
[ "$EUID" -eq "0" ] || {
    sudo -H -E "$0" "$@"
    exit
}

{
    set -euo pipefail
    _FILE="${BASH_SOURCE[0]}" && [ ! -L "$_FILE" ] &&
        LK_INST="$(cd "${_FILE%/*}/.." && pwd -P)" &&
        [ -d "$LK_INST/lib/bash" ] && export LK_INST ||
        { echo "${_FILE:+$_FILE: }unable to find LK_BASE" >&2 && exit 1; }

    shopt -s nullglob

    INSTALL_SETTINGS=(
        # lib/linode/hosting.sh
        NODE_HOSTNAME
        NODE_FQDN
        NODE_TIMEZONE
        NODE_SERVICES
        NODE_PACKAGES
        ADMIN_EMAIL
        TRUSTED_IP_ADDRESSES
        SSH_TRUSTED_ONLY
        REJECT_OUTPUT
        ACCEPT_OUTPUT_HOSTS
        INNODB_BUFFER_SIZE
        OPCACHE_MEMORY_CONSUMPTION
        MEMCACHED_MEMORY_LIMIT
        SMTP_RELAY
        EMAIL_BLACKHOLE
        AUTO_REBOOT
        AUTO_REBOOT_TIME
        PLATFORM_BRANCH
    )

    DEFAULT_SETTINGS=(
        LK_BASE
        LK_PATH_PREFIX
        LK_PATH_PREFIX_ALPHA
        LK_NODE_HOSTNAME
        LK_NODE_FQDN
        LK_NODE_TIMEZONE
        LK_NODE_SERVICES
        LK_NODE_PACKAGES
        LK_ADMIN_EMAIL
        LK_TRUSTED_IP_ADDRESSES
        LK_SSH_TRUSTED_ONLY
        LK_REJECT_OUTPUT
        LK_ACCEPT_OUTPUT_HOSTS
        LK_INNODB_BUFFER_SIZE
        LK_DEFAULT_OPCACHE_MEMORY_CONSUMPTION
        LK_MEMCACHED_MEMORY_LIMIT
        LK_SMTP_RELAY
        LK_EMAIL_BLACKHOLE
        LK_AUTO_REBOOT
        LK_AUTO_REBOOT_TIME
        LK_PLATFORM_BRANCH
    )

    DEFAULT_FILE="/etc/default/lk-platform"
    GLOBIGNORE="$LK_INST/etc/*example.*:$LK_INST/etc/*default.*"
    LK_SETTINGS_FILES=(
        "$LK_INST/etc"/*.conf
        "$DEFAULT_FILE"
        "~root/.\${LK_PATH_PREFIX:-lk-}settings"
        "$DEFAULT_FILE"
    )
    unset GLOBIGNORE

    # otherwise the LK_BASE environment variable (if set) will mask the value
    # set in config files
    unset LK_BASE
    export -n LK_PATH_PREFIX

    include= skip=env . "$LK_INST/lib/bash/common.sh"

    LK_BACKUP_SUFFIX="-$(lk_timestamp).bak"
    LK_VERBOSE=1
    lk_log_output

    lk_console_message "Installing gnu_* symlinks"
    # to list gnu_* commands required by lk-platform:
    #   find "$LK_BASE" ! \( -type d -name .git -prune \) -type f -print0 |
    #       xargs -0 grep -Eho '\bgnu_[a-zA-Z0-9.]+' | sort -u
    lk_install_gnu_commands awk date find mktemp sort stat xargs
    lk_install_gnu_commands || true

    lk_console_message "Checking configuration files"
    LK_PATH_PREFIX="${LK_PATH_PREFIX:-${PATH_PREFIX:-${1:-}}}"
    [ -n "$LK_PATH_PREFIX" ] ||
        lk_die "LK_PATH_PREFIX not set and no value provided on command line"
    [ -z "$LK_BASE" ] ||
        [ "$LK_BASE" = "$LK_INST" ] ||
        [ ! -d "$LK_BASE" ] ||
        {
            lk_console_detail "Existing installation found at" "$LK_BASE"
            lk_no_input || lk_confirm "Reconfigure system?" Y || lk_die
        }
    export LK_BASE="$LK_INST"
    LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(
        sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
    )}"

    # check repo state
    cd "$LK_BASE"
    REPO_OWNER="$(gnu_stat --printf '%U' "$LK_BASE")"
    CONFIG_COMMANDS=()
    function check_git_config() {
        local VALUE
        VALUE="$(git config --local "$1")" &&
            [ "$VALUE" = "$2" ] ||
            CONFIG_COMMANDS+=("$(printf 'git config %q %q' "$1" "$2")")
    }
    check_git_config "core.sharedRepository" "0664"
    check_git_config "merge.ff" "only"
    check_git_config "pull.ff" "only"
    if [ "${#CONFIG_COMMANDS[@]}" -gt "0" ]; then
        IFS=$'\n'
        lk_console_item "Running in $LK_BASE:" "${CONFIG_COMMANDS[*]}"
        unset IFS
        sudo -Hu "$REPO_OWNER" \
            bash -c "$(lk_implode ' && ' "${CONFIG_COMMANDS[@]}")"
    fi
    BRANCH="$(git rev-parse --abbrev-ref HEAD)" && [ "$BRANCH" != "HEAD" ] ||
        lk_die "no branch checked out: $LK_BASE"
    LK_PLATFORM_BRANCH="${LK_PLATFORM_BRANCH:-$BRANCH}"
    if [ "$LK_PLATFORM_BRANCH" != "$BRANCH" ]; then
        lk_console_warning "$(printf "%s is set to %s, but %s is checked out" \
            "LK_PLATFORM_BRANCH" \
            "$LK_BOLD$LK_PLATFORM_BRANCH$LK_RESET" \
            "$LK_BOLD$BRANCH$LK_RESET")"
        if ! lk_no_input && lk_confirm "Switch to $LK_PLATFORM_BRANCH?" N; then
            lk_console_item "Switching to" "$LK_PLATFORM_BRANCH"
            sudo -Hu "$REPO_OWNER" git checkout "$LK_PLATFORM_BRANCH"
            BRANCH="$LK_PLATFORM_BRANCH"
        else
            LK_PLATFORM_BRANCH="$BRANCH"
        fi
    fi
    REMOTE_NAME="$(git for-each-ref --format="%(upstream:remotename)" \
        "refs/heads/$BRANCH")" && [ -n "$REMOTE_NAME" ] ||
        lk_die "no upstream remote for current branch: $LK_BASE"
    # TODO: skip fetch if .git/FETCH_HEAD <5min old
    if sudo -Hu "$REPO_OWNER" \
        git fetch --quiet --prune --prune-tags "$REMOTE_NAME" "$BRANCH"; then
        BEHIND="$(git rev-list --count "HEAD..@{upstream}")"
        if [ "$BEHIND" -gt "0" ]; then
            git merge-base --is-ancestor HEAD "@{upstream}" ||
                lk_die "local branch has diverged from upstream: $LK_BASE"
            lk_console_item \
                "Updating lk-platform ($BEHIND $(
                    lk_maybe_plural "$BEHIND" "commit" "commits"
                ) behind) in" "$LK_BASE"
            sudo -Hu "$REPO_OWNER" \
                git merge --ff-only "@{upstream}"
            lk_console_message "Restarting $(basename "$0")"
            "$0" "$@"
            exit
        fi
    else
        lk_console_warning "Unable to check for lk-platform updates"
    fi

    # use the opening "Environment:" log entry created by hosting.sh as a last
    # resort when looking for settings
    function install_env() {
        INSTALL_ENV="${INSTALL_ENV-$(
            [ ! -f "/var/log/${LK_PATH_PREFIX}install.log" ] || {
                PROG="\
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}( [-+][0-9]{4})? Environment:\$/         { env_started = 1; next }
/^  [a-zA-Z_][a-zA-Z0-9_]*=/                                                            { if (env_started) { print substr(\$0, 3, length - 2); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} [-+][0-9]{4}   [a-zA-Z_][a-zA-Z0-9_]*=/ { if (env_started) { print substr(\$0, 29, length - 28); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}( [-+][0-9]{4})? /                       { if (env_started) exit }"
                awk "$PROG" <"/var/log/${LK_PATH_PREFIX}install.log"
            }
        )}" && awk -F= "/^$1=/ { print \$2 }" <<<"$INSTALL_ENV"
    }

    for i in "${INSTALL_SETTINGS[@]}"; do
        case "$i" in
        OPCACHE_MEMORY_CONSUMPTION)
            eval "LK_DEFAULT_$i=\"\${LK_DEFAULT_$i-\
\${LK_$i-\${$i-\$(install_env \"(LK_(DEFAULT_)?)?$i\")}}}\"" || exit
            ;;
        *)
            eval "LK_$i=\"\${LK_$i-\${$i-\$(install_env \"(LK_)?$i\")}}\"" || exit
            ;;
        esac
    done

    lk_console_item "Configuring system for lk-platform installed at" "$LK_BASE"

    # generate /etc/default/lk-platform
    [ -e "$DEFAULT_FILE" ] || {
        install -d -m 0755 "${DEFAULT_FILE%/*}" &&
            install -m 0644 /dev/null "$DEFAULT_FILE"
    }
    DEFAULT_LINES=()
    for i in "${DEFAULT_SETTINGS[@]}"; do
        # don't include null variables unless they already appear in
        # /etc/default/lk-platform
        [ -n "${!i}" ] ||
            grep -Eq "^$i=" "$DEFAULT_FILE" ||
            continue
        lk_console_detail "$i:" "${!i:-<none>}"
        DEFAULT_LINES+=("$(printf '%s=%q' "$i" "${!i}")")
    done
    lk_maybe_replace "$DEFAULT_FILE" "$(lk_echo_array "${DEFAULT_LINES[@]}")"

    # check .bashrc files
    RC_FILES=(
        /etc/skel/.bashrc
        /etc/skel."${LK_PATH_PREFIX_ALPHA}"/.bashrc
        /{home,Users}/*/.bashrc
        /srv/www/*/.bashrc
        ~root/.bashrc
    )
    lk_resolve_files RC_FILES
    if [ "${#RC_FILES[@]}" -eq "0" ]; then
        lk_console_warning "No ~/.bashrc files found"
    else
        lk_echo_array "${RC_FILES[@]}" |
            lk_console_list "Checking startup scripts:" "file" "files"
        RC_ESCAPED="$(printf '%q' "$LK_BASE/lib/bash/rc.sh")"
        BASH_SKEL="
# Added by $(basename "$0") at $(lk_now)
if [ -f $RC_ESCAPED ]; then
    . $RC_ESCAPED
fi"
        for RC_FILE in "${RC_FILES[@]}"; do
            # fix legacy references to $LK_BASE/**/.bashrc
            lk_maybe_sed -E "s/'($(
                lk_escape_ere "$LK_BASE"
            ))(\/.*)?\/.bashrc'/$(
                lk_escape_ere_replace "$RC_ESCAPED"
            )/g" "$RC_FILE"

            # source $LK_BASE/lib/bash/rc.sh unless a reference is already
            # present
            grep -Fq "$RC_ESCAPED" "$RC_FILE" || {
                lk_keep_original "$RC_FILE" &&
                    echo "$BASH_SKEL" >>"$RC_FILE" || exit
                lk_console_file "$RC_FILE"
            }
        done
    fi

    if lk_is_desktop; then
        . "$LK_BASE/lib/desktop/install.sh"
    fi

    lk_console_message "lk-platform successfully installed" "$LK_GREEN"

    exit
}

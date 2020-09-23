#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2001,SC2015,SC2034

# root privileges are required for access to settings files and startup scripts
# in ~root, /home/*, etc., so elevate immediately rather than waiting for
# lk_elevate to be available
[ "$EUID" -eq 0 ] || {
    sudo -H -E "$0" "$@"
    exit
}

{
    set -euo pipefail
    _DEPTH=1
    _FILE=${BASH_SOURCE[0]}
    lk_die() { s=$? && echo "$_FILE: $1" >&2 && (return $s) && false || exit; }
    [ "${_FILE%/*}" != "$_FILE" ] || _FILE=./$_FILE
    LK_INST=$(i=0 && F=$_FILE && while [ $((i++)) -le "$_DEPTH" ]; do
        [ "$F" != / ] && [ ! -L "$F" ] &&
            cd "${F%/*}" && F=$PWD || exit
    done && pwd -P) || lk_die "symlinks in path are not supported"
    [ -d "$LK_INST/lib/bash" ] || lk_die "unable to locate LK_BASE"
    export LK_INST

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
        SSH_JUMP_HOST
        SSH_JUMP_USER
        SSH_JUMP_KEY
        REJECT_OUTPUT
        ACCEPT_OUTPUT_HOSTS
        INNODB_BUFFER_SIZE
        OPCACHE_MEMORY_CONSUMPTION
        PHP_SETTINGS
        PHP_ADMIN_SETTINGS
        MEMCACHED_MEMORY_LIMIT
        SMTP_RELAY
        EMAIL_BLACKHOLE
        AUTO_REBOOT
        AUTO_REBOOT_TIME
        SCRIPT_DEBUG
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
        LK_SSH_JUMP_HOST
        LK_SSH_JUMP_USER
        LK_SSH_JUMP_KEY
        LK_REJECT_OUTPUT
        LK_ACCEPT_OUTPUT_HOSTS
        LK_INNODB_BUFFER_SIZE
        LK_OPCACHE_MEMORY_CONSUMPTION
        LK_PHP_SETTINGS
        LK_PHP_ADMIN_SETTINGS
        LK_MEMCACHED_MEMORY_LIMIT
        LK_SMTP_RELAY
        LK_EMAIL_BLACKHOLE
        LK_AUTO_REBOOT
        LK_AUTO_REBOOT_TIME
        LK_SCRIPT_DEBUG
        LK_PLATFORM_BRANCH
        LK_PACKAGES_FILE
    )

    DEFAULT_FILE="/etc/default/lk-platform"
    GLOBIGNORE="$LK_INST/etc/*example.*:$LK_INST/etc/*default.*"
    LK_SETTINGS_FILES=(
        "$DEFAULT_FILE"
        "$LK_INST/etc"/*.conf
        "~root/.\${LK_PATH_PREFIX:-lk-}settings"
        "$DEFAULT_FILE"
    )
    unset GLOBIGNORE

    # Otherwise the LK_BASE environment variable (if set) will mask the value
    # set in config files
    unset LK_BASE
    export -n LK_PATH_PREFIX

    LK_SKIP=env include=provision . "$LK_INST/lib/bash/common.sh"

    LK_BIN_PATH=${LK_BIN_PATH:-/usr/local/bin}
    LK_BACKUP_SUFFIX="-$(lk_timestamp).bak"
    LK_VERBOSE=1
    lk_log_output

    # To list gnu_* commands required by lk-platform:
    #
    #   find "$LK_BASE" ! \( -type d -name .git -prune \) -type f -print0 |
    #       xargs -0 grep -Eho '\bgnu_[a-zA-Z0-9.]+' | sort -u
    lk_console_message "Checking gnu_* symlinks"
    function install_gnu_commands() {
        local COMMAND GCOMMAND COMMAND_PATH COMMANDS=("$@") EXIT_STATUS=0
        [ $# -gt 0 ] ||
            COMMANDS=(${_LK_GNU_COMMANDS[@]+"${_LK_GNU_COMMANDS[@]}"})
        for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
            GCOMMAND=$(_lk_gnu_command "$COMMAND")
            COMMAND_PATH=$(type -P "$GCOMMAND") || {
                EXIT_STATUS=$?
                lk_console_warning "GNU $COMMAND not found:" "$GCOMMAND"
                continue
            }
            lk_safe_symlink "$COMMAND_PATH" "$LK_BIN_PATH/gnu_$COMMAND" ||
                EXIT_STATUS=$?
        done
        return "$EXIT_STATUS"
    }
    # Exit if required commands fail to install
    install_gnu_commands chmod date find getopt realpath sed stat xargs
    # For other commands, warn and continue
    install_gnu_commands || true

    lk_console_message "Checking configuration files"
    LK_PATH_PREFIX="${LK_PATH_PREFIX:-${PATH_PREFIX:-${1:-}}}"
    [ -n "$LK_PATH_PREFIX" ] ||
        lk_die "LK_PATH_PREFIX not set and no value provided on command line"
    [ -z "$LK_BASE" ] ||
        [ "$LK_BASE" = "$LK_INST" ] ||
        [ ! -d "$LK_BASE" ] ||
        {
            lk_console_detail "Existing installation found at" "$LK_BASE"
            lk_confirm "Reconfigure system?" Y || lk_die
        }
    export LK_BASE="$LK_INST"
    LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(
        sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
    )}"

    # Check repo state
    cd "$LK_BASE"
    REPO_OWNER="$(lk_file_owner "$LK_BASE")"
    CONFIG_COMMANDS=()
    function check_repo_config() {
        local VALUE
        VALUE="$(git config --local "$1")" &&
            [ "$VALUE" = "$2" ] ||
            CONFIG_COMMANDS+=("$(printf 'git config %q %q' "$1" "$2")")
    }
    check_repo_config "core.sharedRepository" "0664"
    check_repo_config "merge.ff" "only"
    check_repo_config "pull.ff" "only"
    if [ "${#CONFIG_COMMANDS[@]}" -gt 0 ]; then
        lk_console_item "Running in $LK_BASE:" \
            "$(lk_echo_array CONFIG_COMMANDS)"
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
        if lk_confirm "Switch to $LK_PLATFORM_BRANCH?" N; then
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
        if [ "$BEHIND" -gt 0 ]; then
            git merge-base --is-ancestor HEAD "@{upstream}" ||
                lk_die "local branch has diverged from upstream: $LK_BASE"
            lk_console_item \
                "Updating lk-platform ($BEHIND $(
                    lk_maybe_plural "$BEHIND" "commit" "commits"
                ) behind) in" "$LK_BASE"
            sudo -Hu "$REPO_OWNER" \
                git merge --ff-only "@{upstream}"
            lk_console_message "Restarting ${0##*/}"
            NO_LOG=1
            ! lk_has_arg --no-log || unset NO_LOG
            "$0" "$@" ${NO_LOG+--no-log}
            exit
        fi
    else
        lk_console_warning0 "Unable to check for lk-platform updates"
    fi

    # Use the opening "Environment:" log entry created by hosting.sh as a last
    # resort when looking for settings
    function install_env() {
        INSTALL_ENV="${INSTALL_ENV-$(
            [ ! -f "/var/log/${LK_PATH_PREFIX}install.log" ] || {
                PROG="\
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}( [-+][0-9]{4})? (==> |   -> )?Environment:\$/   { env_started = 1; next }
/^  [a-zA-Z_][a-zA-Z0-9_]*=/                                                                    { if (env_started) { print substr(\$0, 3, length - 2); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} [-+][0-9]{4}   [a-zA-Z_][a-zA-Z0-9_]*=/         { if (env_started) { print substr(\$0, 29, length - 28); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} [-+][0-9]{4}     [a-zA-Z_][a-zA-Z0-9_]*=/       { if (env_started) { print substr(\$0, 31, length - 30); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} [-+][0-9]{4}       [a-zA-Z_][a-zA-Z0-9_]*=/     { if (env_started) { print substr(\$0, 33, length - 32); next } }
/^[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}( [-+][0-9]{4})? /                               { if (env_started) exit }"
                awk "$PROG" <"/var/log/${LK_PATH_PREFIX}install.log"
            }
        )}" && awk -F= "/^$1=/ { print \$2 }" <<<"$INSTALL_ENV"
    }

    for i in "${INSTALL_SETTINGS[@]}"; do
        eval "\
LK_$i=\"\${LK_$i-\${LK_DEFAULT_$i-\${$i-\$(\
install_env \"(LK_(DEFAULT_)?)?$i\")}}}\"" || exit
    done

    lk_console_item "Configuring system for lk-platform installed at" "$LK_BASE"

    # Generate /etc/default/lk-platform
    [ -e "$DEFAULT_FILE" ] || {
        install -d -m 0755 "${DEFAULT_FILE%/*}" &&
            install -m 0644 /dev/null "$DEFAULT_FILE"
    }
    # TODO: add or replace lines rather than overwriting entire file
    DEFAULT_LINES=()
    OUTPUT=()
    for i in "${DEFAULT_SETTINGS[@]}"; do
        if [ -z "${!i:=}" ]; then
            # Don't include null variables unless they already appear in
            # /etc/default/lk-platform
            grep -Eq "^$i=" "$DEFAULT_FILE" ||
                continue
            DEFAULT_LINES+=("$(printf '%s=' "$i")")
        else
            DEFAULT_LINES+=("$(printf '%s=%q' "$i" "${!i}")")
        fi
        OUTPUT+=("$i" "${!i:-<none>}")
    done
    lk_console_item "Settings:" "$(printf '%s: %s\n' "${OUTPUT[@]}")"
    lk_maybe_replace "$DEFAULT_FILE" "$(lk_echo_array DEFAULT_LINES)"

    lk_console_message "Checking lk-* symlinks"
    lk_safe_symlink "$LK_BASE/bin/lk-bash-load.sh" \
        "$LK_BIN_PATH/lk-bash-load.sh"

    # Check .bashrc files
    RC_FILES=(
        /etc/skel{,".$LK_PATH_PREFIX_ALPHA"}/.bashrc
        /{home,Users}/*/.bashrc
        /srv/www/*/.bashrc
        ~root/.bashrc
    )
    lk_resolve_files RC_FILES
    if [ "${#RC_FILES[@]}" -eq 0 ]; then
        lk_console_warning "No ~/.bashrc files found"
    else
        lk_echo_array RC_FILES |
            lk_console_list "Checking startup scripts:" "file" "files"
        LK_BASE_QUOTED=$(printf '%q' "$LK_BASE")
        RC_PATH=$LK_BASE_QUOTED/lib/bash/rc.sh
        RC_PATTERN=$(lk_escape_ere "$LK_BASE")
        [ "$LK_BASE_QUOTED" = "$LK_BASE" ] ||
            RC_PATTERN="($RC_PATTERN|$(lk_escape_ere "$LK_BASE_QUOTED"))"
        RC_PATTERN="$RC_PATTERN(\\/.*)?\\/(\\.bashrc|rc\\.sh)"
        RC_PATTERN=${RC_PATTERN//\\/\\\\}
        RC_SH="\
if [ -f $RC_PATH ]; then
    . $RC_PATH
fi"
        # shellcheck disable=SC2016
        PROG='
function print_previous() {
    if (previous) {
        print previous
        previous = ""
    }
}
function print_RC_SH(add_newline) {
    if (RC_SH) {
        print (add_newline ? "\n" : "") RC_SH
        RC_SH = ""
    }
}
$0 ~ RC_PATTERN {
    remove = 1
    previous = ""
    next
}
remove {
    remove = 0
    print_RC_SH()
    next
}
/^# Added by / {
    print_previous()
    previous = $0
    next
}
{
    print_previous()
    print
}
END {
    print_previous()
    print_RC_SH(1)
}'
        AWK=(awk -v "RC_PATTERN=$RC_PATTERN" -v "RC_SH=$RC_SH" "$PROG")
        for RC_FILE in "${RC_FILES[@]}"; do
            lk_maybe_replace "$RC_FILE" "$("${AWK[@]}" "$RC_FILE")"
        done
    fi

    SSH_DIRS=(
        /etc/skel{,".$LK_PATH_PREFIX_ALPHA"}/.ssh
        /{home,Users}/*/.ssh
        /srv/www/*/.ssh
        ~root/.ssh
    )
    LK_SSH_HOMES=("${SSH_DIRS[@]%/*}")
    lk_resolve_files LK_SSH_HOMES
    if [ "${#LK_SSH_HOMES[@]}" -eq 0 ]; then
        lk_console_warning "No ~/.ssh directories found"
    else
        lk_echo_args "${LK_SSH_HOMES[@]/%//.ssh}" |
            lk_console_list "Checking SSH configuration:" directory directories
        if [ -n "${LK_SSH_JUMP_HOST:-}" ]; then
            lk_ssh_configure "$LK_SSH_JUMP_HOST" \
                "${LK_SSH_JUMP_USER:-}" \
                "${LK_SSH_JUMP_KEY:-}"
        else
            lk_ssh_configure
        fi
    fi

    if lk_is_desktop; then
        . "$LK_BASE/lib/desktop/install.sh"
    fi

    lk_console_success "lk-platform successfully installed"

    exit
}

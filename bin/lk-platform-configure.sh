#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2016,SC2034,SC2207

[ "$EUID" -eq 0 ] || {
    sudo -H -E "$0" --elevated "$@"
    exit
}

{
    set -euo pipefail
    _FILE=${BASH_SOURCE[0]}
    lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
    _DIR=${_FILE%/*}
    [ "$_DIR" != "$_FILE" ] || _DIR=.
    _DIR=$(cd "$_DIR" && pwd)
    LK_INST=${_DIR%/*}
    [ -d "$LK_INST/lib/bash" ] &&
        LK_INST=$(cd "$LK_INST" && pwd -P) || lk_die "unable to locate LK_BASE"

    shopt -s nullglob

    CONF_FILE=/etc/default/lk-platform

    SETTINGS=(
        LK_BASE
        LK_PATH_PREFIX
        LK_NODE_HOSTNAME
        LK_NODE_FQDN
        LK_NODE_TIMEZONE
        LK_NODE_SERVICES
        LK_NODE_PACKAGES
        LK_NODE_LOCALES
        LK_NODE_LANGUAGE
        LK_NTP_SERVER
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
        LK_ARCH_CUSTOM_REPOS
        LK_ARCH_MIRROR
        LK_SCRIPT_DEBUG
        LK_PLATFORM_BRANCH
        LK_PACKAGES_FILE
    )

    LK_SETTINGS_FILES=(
        "$LK_INST/etc"/*.conf
        "$CONF_FILE"
    )

    # Don't allow environment variables to override values set in config files
    export -n "${!LK_@}"

    # Don't allow common.sh to override ORIGINAL_PATH_PREFIX (see below)
    LK_PATH_PREFIX=${LK_PATH_PREFIX-}

    include=provision,git . "$LK_INST/lib/bash/common.sh"

    LK_BIN_PATH=${LK_BIN_PATH:-/usr/local/bin}
    LK_FILE_TAKE_BACKUP=${LK_FILE_TAKE_BACKUP-1}
    LK_FILE_MOVE_BACKUP=1
    LK_VERBOSE=${LK_VERBOSE-1}

    NEW_SETTINGS=()
    unset ELEVATED

    lk_getopt "s:" "elevated,set:"
    eval "set -- $LK_GETOPT"

    while :; do
        OPT=$1
        shift
        case "$OPT" in
        -s | --set)
            [[ $1 =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*) ]] ||
                lk_die "invalid argument: $1"
            NEW_SETTINGS+=("${BASH_REMATCH[1]}")
            eval "${BASH_REMATCH[1]}=\${BASH_REMATCH[2]}"
            shift
            ;;
        --elevated)
            ELEVATED=1
            ;;
        --)
            break
            ;;
        esac
    done

    lk_lock LOCK_FILE LOCK_FD

    lk_log_output

    if [ "${LK_INST##*/}" != lk-platform ] &&
        [[ "${LK_INST##*/}" =~ ^([a-zA-Z0-9]{2,3}-)platform$ ]]; then
        ORIGINAL_PATH_PREFIX=${BASH_REMATCH[1]}
        OLD_LK_INST=$LK_INST
        LK_INST=${LK_INST%/*}/lk-platform
        lk_console_message "Renaming installation directory"
        if [ -e "$LK_INST" ] && [ ! -L "$LK_INST" ]; then
            BACKUP_DIR=$LK_INST$(lk_file_get_backup_suffix)
            [ ! -e "$BACKUP_DIR" ] || lk_die "$BACKUP_DIR already exists"
            mv -fv "$LK_INST" "$BACKUP_DIR"
        fi
        rm -fv "$LK_INST"
        mv -v "$OLD_LK_INST" "$LK_INST"
        lk_symlink lk-platform "$OLD_LK_INST"
    fi

    lk_console_message "Checking environment"
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${PATH_PREFIX:-${ORIGINAL_PATH_PREFIX:-}}}
    [ -n "$LK_PATH_PREFIX" ] || lk_no_input || {
        lk_console_detail "LK_PATH_PREFIX is not set"
        lk_console_detail \
            "Value must be 2-3 alphanumeric characters followed by a hyphen"
        lk_console_detail "Default value:" "lk-"
        while [[ ! $LK_PATH_PREFIX =~ ^[a-zA-Z0-9]{2,3}-$ ]]; do
            [ -z "$LK_PATH_PREFIX" ] ||
                lk_console_error "Invalid LK_PATH_PREFIX:" "$LK_PATH_PREFIX"
            LK_PATH_PREFIX=$(lk_console_read "Path prefix (required):")
        done
    }
    [ -n "$LK_PATH_PREFIX" ] || lk_die "LK_PATH_PREFIX not set"
    [ -z "${LK_BASE:-}" ] ||
        [ "$LK_BASE" = "$LK_INST" ] ||
        [ "$LK_BASE" = "$OLD_LK_INST" ] ||
        [ ! -d "$LK_BASE" ] ||
        {
            lk_console_item "Existing installation found at" "$LK_BASE"
            lk_confirm "Reconfigure system?" Y || lk_die
        }
    export LK_BASE=$LK_INST

    lk_is_arch && _IS_ARCH=1 || _IS_ARCH=
    _BASHRC='[ -z "${BASH_VERSION:-}" ] || [ ! -f ~/.bashrc ] || . ~/.bashrc'
    BYOBU_PATH=$(type -P byobu-launch) &&
        _BYOBU=$(printf '%s_byobu_sourced=1 . %q 2>/dev/null || true' \
            "$(! lk_is_macos || echo '[ ! "$SSH_CONNECTION" ] || ')" \
            "$BYOBU_PATH") ||
        _BYOBU=

    lk_console_message "Checking sudo configuration"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default
    [ ! -e "${FILE}s" ] || [ -e "$FILE" ] ||
        mv -fv "${FILE}s" "$FILE"
    [ -e "$FILE" ] ||
        install -m 00440 /dev/null "$FILE"
    lk_file_replace "$FILE" "$(cat "$LK_BASE/share/sudoers.d/default")"

    # To list gnu_* commands required by lk-platform:
    #
    #   find "$LK_BASE" ! \( -type d -name .git -prune \) -type f -print0 |
    #       xargs -0 grep -Eho '\bgnu_[a-zA-Z0-9.]+' | sort -u
    lk_console_message "Checking GNU utilities"
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
            lk_symlink "$COMMAND_PATH" "$LK_BIN_PATH/gnu_$COMMAND" ||
                EXIT_STATUS=$?
        done
        return "$EXIT_STATUS"
    }
    # Exit if required commands fail to install
    install_gnu_commands \
        awk chmod chown cp date df diff find getopt nc realpath sed stat xargs
    # For other commands, warn and continue
    install_gnu_commands || true

    lk_console_item "Checking lk-platform configuration:" "$CONF_FILE"
    [ -e "$CONF_FILE" ] || {
        install -d -m 00755 "${CONF_FILE%/*}" &&
            install -m 00644 /dev/null "$CONF_FILE"
    }

    # Use the opening "Environment:" log entry created by hosting.sh as a last
    # resort when looking for old settings
    function install_env() {
        if [ "${INSTALL_ENV+1}" != 1 ]; then
            INSTALL_ENV=$(
                FILE=/var/log/${LK_PATH_PREFIX}install.log
                [ ! -f "$FILE" ] ||
                    awk -f "$LK_BASE/lib/awk/get-install-env.awk" <"$FILE"
            ) || return
        fi
        awk -F= \
            -v "SETTING=$1" \
            '$1 ~ "^" SETTING "$" { print $2 }' <<<"$INSTALL_ENV"
    }

    for i in "${SETTINGS[@]}"; do
        SH=$(printf \
            '%s=${%s-${%s-${%s-$(install_env "(LK_(DEFAULT_)?)?%s")}}}' \
            "$i" "$i" "LK_DEFAULT_${i#LK_}" "${i#LK_}" "${i#LK_}") &&
            eval "$SH"
    done

    KNOWN_SETTINGS=()
    for i in "${SETTINGS[@]}"; do
        # Don't include null variables unless they already appear in
        # /etc/default/lk-platform
        [ -n "${!i:-}" ] ||
            grep -Eq "^$i=" "$CONF_FILE" ||
            continue
        KNOWN_SETTINGS+=("$i")
    done
    OTHER_SETTINGS=($(comm -23 \
        <({ lk_echo_array NEW_SETTINGS &&
            sed -En \
                -e '/^LK_PATH_PREFIX_ALPHA=/d' \
                -e 's/^([a-zA-Z_][a-zA-Z0-9_]*)=.*/\1/p' "$CONF_FILE"; } |
            sort -u) \
        <(lk_echo_array KNOWN_SETTINGS | sort)))
    lk_file_replace "$CONF_FILE" "$(lk_get_shell_var \
        "${KNOWN_SETTINGS[@]}" \
        ${OTHER_SETTINGS[@]+"${OTHER_SETTINGS[@]}"})"

    function restart_script() {
        lk_lock_drop LOCK_FILE LOCK_FD
        lk_console_message "Restarting ${0##*/}"
        "$0" --no-log "$@"
        exit
    }

    if [ -d "$LK_BASE/.git" ]; then
        # shellcheck disable=SC2086
        function _git() {
            sudo -Hu "$REPO_OWNER" git "$@"
        }
        function check_repo_config() {
            local VALUE
            VALUE=$(git config --local "$1") &&
                [ "$VALUE" = "$2" ] ||
                CONFIG_COMMANDS+=("$(printf 'config %q %q' "$1" "$2")")
        }
        function update_repo() {
            local _BRANCH=${1:-$BRANCH} UPSTREAM BEHIND
            UPSTREAM=$REMOTE/$_BRANCH
            _git fetch --quiet --prune --prune-tags "$REMOTE" ||
                lk_warn "unable to check remote '$REMOTE' for updates" ||
                return
            if lk_git_branch_list_local |
                grep -Fx "$_BRANCH" >/dev/null; then
                BEHIND=$(git rev-list --count "$_BRANCH..$UPSTREAM")
                if [ "$BEHIND" -gt 0 ]; then
                    git merge-base --is-ancestor "$_BRANCH" "$UPSTREAM" ||
                        lk_warn "local branch $_BRANCH has diverged" ||
                        return
                    lk_console_detail \
                        "Updating lk-platform ($_BRANCH branch is $BEHIND $(
                            lk_maybe_plural "$BEHIND" "commit" "commits"
                        ) behind)"
                    REPO_MERGED=1
                    if [ "$_BRANCH" = "$BRANCH" ]; then
                        _git merge --ff-only
                    else
                        # Fast-forward local _BRANCH (e.g. 'develop') to
                        # UPSTREAM (e.g. 'origin/develop') without checking
                        # it out
                        _git fetch . "$UPSTREAM:$_BRANCH"
                    fi
                fi
            fi
        }
        UMASK=$(umask)
        umask 002
        lk_console_item "Checking repository:" "$LK_BASE"
        cd "$LK_BASE"
        REPO_OWNER=$(lk_file_owner "$LK_BASE")
        CONFIG_COMMANDS=()
        [ ! -g "$LK_BASE" ] ||
            check_repo_config "core.sharedRepository" "0664"
        check_repo_config "merge.ff" "only"
        check_repo_config "pull.ff" "only"
        if [ ${#CONFIG_COMMANDS[@]} -gt 0 ]; then
            lk_console_detail "Running:" \
                "$(lk_echo_args "${CONFIG_COMMANDS[@]/#/git }")"
            for COMMAND in "${CONFIG_COMMANDS[@]}"; do
                _git $COMMAND
            done
        fi
        REMOTE=$(lk_git_branch_upstream_remote) ||
            lk_die "no upstream remote for current branch"
        BRANCH=$(lk_git_branch_current) ||
            lk_die "no branch checked out"
        LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-$BRANCH}
        if [ "$LK_PLATFORM_BRANCH" != "$BRANCH" ]; then
            lk_console_warning "$(printf \
                "%s is set to %s, but %s is checked out" \
                "LK_PLATFORM_BRANCH" \
                "$LK_BOLD$LK_PLATFORM_BRANCH$LK_RESET" \
                "$LK_BOLD$BRANCH$LK_RESET")"
            if lk_confirm "Switch to $LK_PLATFORM_BRANCH?" Y; then
                lk_console_detail "Switching to" "$LK_PLATFORM_BRANCH"
                update_repo "$LK_PLATFORM_BRANCH"
                _git checkout "$LK_PLATFORM_BRANCH"
                lk_git_branch_upstream >/dev/null ||
                    _git branch -u "$REMOTE/$LK_PLATFORM_BRANCH"
                restart_script "$@"
            else
                LK_PLATFORM_BRANCH=$BRANCH
            fi
        fi
        FETCH_TIME=$(lk_file_modified ".git/FETCH_HEAD" 2>/dev/null) ||
            FETCH_TIME=0
        if [ $(($(lk_timestamp) - FETCH_TIME)) -gt 300 ]; then
            lk_console_detail "Checking for changes"
            unset REPO_MERGED
            update_repo
            ! lk_is_true REPO_MERGED ||
                restart_script "$@"
        fi
        lk_console_detail "Resetting file permissions"
        DIR_MODE=0755
        FILE_MODE=0644
        PRIVILEGED_DIR_MODE=0700
        [ ! -g "$LK_BASE" ] || {
            DIR_MODE=2775
            FILE_MODE=0664
            PRIVILEGED_DIR_MODE=0750
        }
        LK_VERBOSE='' \
            lk_dir_set_modes "$LK_BASE" \
            "" \
            "+$DIR_MODE" "+$FILE_MODE" \
            "\\./etc/" \
            "$DIR_MODE" "" \
            "\\./var/(log|backup)/" \
            "" "" \
            "\\./\\.git/objects/([0-9a-f]{2}|pack)/.*" \
            0555 0444
        install -d -m 00777 "$LK_BASE/var/log"
        install -d -m "0$PRIVILEGED_DIR_MODE" "$LK_BASE/var/backup"
        umask "$UMASK"
    fi

    lk_console_message "Checking symbolic links"
    lk_symlink \
        "$LK_BASE/bin/lk-bash-load.sh" "$LK_BIN_PATH/lk-bash-load.sh"

    LK_HOMES=(
        /etc/skel{,".${LK_PATH_PREFIX%-}"}
        ${SUDO_USER:+"$(lk_expand_path "~$SUDO_USER")"}
        "$@"
    )
    # If invoked by root, include all standard home directories
    lk_is_true ELEVATED || LK_HOMES+=(
        /{home,Users}/*
        /srv/www/*
        ~root
    )
    lk_remove_missing LK_HOMES
    lk_resolve_files LK_HOMES
    [ ${#LK_HOMES[@]} -gt 0 ] || lk_die "No home directories found"
    lk_echo_array LK_HOMES |
        lk_console_list "Checking startup scripts and SSH config files in:" \
            directory directories

    # Prepare awk to update ~/.bashrc
    LK_BASE_QUOTED=$(printf '%q' "$LK_BASE")
    RC_PATH=$LK_BASE_QUOTED/lib/bash/rc.sh
    LK_BASE_ALT=${LK_BASE%/*}/${LK_PATH_PREFIX}platform
    [ "$LK_BASE_ALT" != "$LK_BASE" ] &&
        LK_BASE_ALT_QUOTED=$(printf '%q' "$LK_BASE_ALT") ||
        LK_BASE_ALT=
    RC_PATTERNS=("$(lk_escape_ere "$LK_BASE")")
    [ "$LK_BASE_QUOTED" = "$LK_BASE" ] ||
        RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_QUOTED")")
    [ -z "$LK_BASE_ALT" ] || {
        RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_ALT")")
        [ "$LK_BASE_ALT_QUOTED" = "$LK_BASE_ALT" ] ||
            RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_ALT_QUOTED")")
    }
    RC_PATTERN="$(lk_regex_implode \
        "${RC_PATTERNS[@]}")(\\/.*)?\\/(\\.bashrc|rc\\.sh)"
    RC_PATTERN=${RC_PATTERN//\\/\\\\}
    RC_SH=$(printf '%s\n' \
        "if [ -f $RC_PATH ]; then" \
        "    . $RC_PATH" \
        "fi")
    RC_AWK=(awk
        -f "$LK_BASE/lib/awk/update-bashrc.awk"
        -v "RC_PATTERN=$RC_PATTERN"
        -v "RC_SH=$RC_SH")

    function replace_byobu() {
        local FILE=$1
        shift
        [ -e "$FILE" ] ||
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        lk_file_replace "$FILE" "$([ $# -eq 0 ] || printf "%s\n" "$@")" \
            '^[[:blank:]]*($|#)'
    }

    LK_FILE_NO_DIFF=1
    for h in "${LK_HOMES[@]}"; do
        [ ! -e "$h/.${LK_PATH_PREFIX}ignore" ] || continue
        OWNER=$(lk_file_owner "$h")
        GROUP=$(id -gn "$OWNER")

        # Create ~/.bashrc if it doesn't exist, then add or update commands to
        # source LK_BASE/lib/bash/rc.sh at startup when Bash is running as a
        # non-login shell (e.g. in most desktop terminals on Linux)
        FILE=$h/.bashrc
        [ -f "$FILE" ] || {
            lk_console_detail "Creating" "$FILE"
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        }
        lk_file_replace "$FILE" "$("${RC_AWK[@]}" "$FILE")"

        # Create ~/.profile if no profile file exists, then check that ~/.bashrc
        # is sourced at startup when Bash is running as a login shell (e.g. in a
        # default SSH session or a macOS terminal)
        PROFILES=("$h/.bash_profile" "$h/.bash_login" "$h/.profile")
        lk_remove_missing PROFILES
        [ ${#PROFILES[@]} -gt "0" ] || {
            FILE=$h/.profile
            PROFILES+=("$FILE")
            lk_console_detail "Creating" "$FILE"
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        }
        grep -q "\\.bashrc" "${PROFILES[@]}" || {
            FILE=${PROFILES[0]}
            lk_console_detail "Sourcing ~/.bashrc in" "$FILE"
            lk_file_get_text "$FILE" CONTENT &&
                lk_file_replace "$FILE" "$CONTENT$_BASHRC"
        }

        install -d -m 00755 -o "$OWNER" -g "$GROUP" "$h/.lk-platform"

        DIR=$h/.byobu
        if [ ! -e "$DIR/.${LK_PATH_PREFIX}ignore" ] &&
            [ -n "$_BYOBU" ]; then
            for FILE in "${PROFILES[@]}"; do
                grep -q "byobu-launch" "$FILE" || {
                    lk_console_detail "Adding byobu-launch to" "$FILE"
                    lk_file_get_text "$FILE" CONTENT &&
                        lk_file_replace "$FILE" "$CONTENT$_BYOBU"
                }
            done

            [ -d "$DIR" ] ||
                install -d -m 00755 -o "$OWNER" -g "$GROUP" "$DIR"
            # Prevent byobu from enabling its prompt on first start
            replace_byobu "$DIR/prompt"
            # Configure status notifications
            replace_byobu "$DIR/status" \
                'screen_upper_left="color"' \
                'screen_upper_right="color whoami hostname #ip_address menu"' \
                'screen_lower_left="color #logo #distro release #arch #session"' \
                'screen_lower_right="color #network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk #time_utc date time"' \
                'tmux_left="#logo #distro release #arch #session"' \
                'tmux_right="#network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk whoami hostname #ip_address #time_utc date time"'
            # Display date as 20Aug, remove space between date and time, include
            # UTC offset
            replace_byobu "$DIR/datetime.tmux" \
                'BYOBU_DATE="%-d%b"' \
                'BYOBU_TIME="%H:%M:%S%z"'
            # Turn off UTF-8 support
            replace_byobu "$DIR/statusrc" \
                ${_IS_ARCH:+'[ ! -f "/etc/arch-release" ] || RELEASE_ABBREVIATED=1'} \
                "BYOBU_CHARMAP=x"
            # Fix output issue when connecting from OpenSSH on Windows
            replace_byobu "$DIR/.tmux.conf" \
                "set -s escape-time 50"
        fi
    done

    unset LK_FILE_TAKE_BACKUP

    # Leave ~root/.ssh alone
    lk_remove_false "$(printf '[ "{}" != %q ]' "$(realpath ~root)")" LK_HOMES
    if [ -n "${LK_SSH_JUMP_HOST:-}" ]; then
        lk_ssh_configure "$LK_SSH_JUMP_HOST" \
            "${LK_SSH_JUMP_USER:-}" \
            "${LK_SSH_JUMP_KEY:-}"
    else
        lk_ssh_configure
    fi

    if lk_is_desktop; then
        . "$LK_BASE/lib/desktop/configure.sh"
    fi

    lk_lock_drop LOCK_FILE LOCK_FD

    lk_console_success "lk-platform successfully configured"

    exit
}

#!/bin/bash

# shellcheck disable=SC1090,SC2001,SC2015,SC2016,SC2034,SC2207

# Elevate for access to ~root, /home/*, etc.
[ "$EUID" -eq 0 ] || {
    sudo -H -E "$0" "$@"
    exit
}

{
    set -euo pipefail
    readonly _FILE=${BASH_SOURCE[0]}
    lk_die() { s=$? && echo "$_FILE: $1" >&2 && (return $s) && false || exit; }
    _DIR=${_FILE%/*}
    [ "$_DIR" != "$_FILE" ] || _DIR=.
    readonly _DIR=$(cd "$_DIR" && pwd)
    LK_INST=${_DIR%/*}
    [ -d "$LK_INST/lib/bash" ] || lk_die "unable to locate LK_BASE"
    export LK_INST

    shopt -s nullglob

    CONF_FILE=/etc/default/lk-platform

    OLD_SETTINGS=(
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

    SETTINGS=(
        LK_BASE
        LK_PATH_PREFIX
        LK_PATH_PREFIX_ALPHA
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

    # To gather missing settings for CONF_FILE, source it twice:
    # - first to seed variables like LK_PATH_PREFIX;
    # - then to ensure existing values are not overwritten
    LK_SETTINGS_FILES=(
        "$CONF_FILE"
        "$LK_INST/etc"/*.conf
        ~root/".\${LK_PATH_PREFIX:-lk-}settings"
        "$CONF_FILE"
    )

    # Otherwise the LK_BASE environment variable (if set) will mask the value
    # set in config files
    unset LK_BASE
    export -n LK_PATH_PREFIX

    LK_SKIP=env include=provision . "$LK_INST/lib/bash/common.sh"

    lk_getopt
    eval "set -- $LK_GETOPT"

    [ "${LK_INST##*/}" = lk-platform ] || {
        OLD_LK_INST=$LK_INST
        LK_INST=${LK_INST%/*}/lk-platform
        lk_safe_symlink "$OLD_LK_INST" "$LK_INST"
    }

    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${PATH_PREFIX:-}}
    [ -n "$LK_PATH_PREFIX" ] || lk_no_input || {
        lk_console_message "LK_PATH_PREFIX not set"
        lk_console_detail \
            "Value must be 2-4 alphanumeric characters followed by a hyphen"
        lk_console_detail "Suggestions:" "$(printf '%s\n' lk- \
            "${USER:0:4}$(lk_repeat 1 $((2 - ${#USER})))-")"
        while [[ ! $LK_PATH_PREFIX =~ ^[a-zA-Z0-9]{2,4}-$ ]]; do
            [ -z "$LK_PATH_PREFIX" ] ||
                lk_console_error0 "Invalid LK_PATH_PREFIX:" "$LK_PATH_PREFIX"
            LK_PATH_PREFIX=$(lk_console_read "LK_PATH_PREFIX:")
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
    LK_PATH_PREFIX_ALPHA=${LK_PATH_PREFIX_ALPHA:-$(sed \
        's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX")}

    LK_BIN_PATH=${LK_BIN_PATH:-/usr/local/bin}
    LK_BACKUP_SUFFIX=-$(lk_timestamp).bak
    LK_VERBOSE=1
    lk_log_output

    lk_console_message "Checking sudo configuration"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default
    [ ! -e "${FILE}s" ] || [ -e "$FILE" ] ||
        mv -v "${FILE}s" "$FILE"
    [ -e "$FILE" ] ||
        install -m 00440 /dev/null "$FILE"
    LK_BACKUP_SUFFIX='' \
        lk_maybe_replace "$FILE" "$(cat "$LK_BASE/share/sudoers.d/default")"

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
            lk_safe_symlink "$COMMAND_PATH" "$LK_BIN_PATH/gnu_$COMMAND" ||
                EXIT_STATUS=$?
        done
        return "$EXIT_STATUS"
    }
    # Exit if required commands fail to install
    install_gnu_commands \
        awk chmod chown date df diff find getopt realpath sed stat xargs
    # For other commands, warn and continue
    install_gnu_commands || true

    function restart_script() {
        lk_console_message "Restarting ${0##*/}"
        "$0" --no-log "$@"
        exit
    }

    if [ -d "$LK_BASE/.git" ]; then
        lk_console_item "Checking repository:" "$LK_BASE"
        cd "$LK_BASE"
        REPO_OWNER=$(lk_file_owner "$LK_BASE")
        CONFIG_COMMANDS=()
        function check_repo_config() {
            local VALUE
            VALUE=$(git config --local "$1") &&
                [ "$VALUE" = "$2" ] ||
                CONFIG_COMMANDS+=("$(printf 'git config %q %q' "$1" "$2")")
        }
        [ ! -g "$LK_BASE" ] ||
            check_repo_config "core.sharedRepository" "0664"
        check_repo_config "merge.ff" "only"
        check_repo_config "pull.ff" "only"
        if [ ${#CONFIG_COMMANDS[@]} -gt 0 ]; then
            lk_console_detail "Running:" "$(lk_echo_array CONFIG_COMMANDS)"
            sudo -Hu "$REPO_OWNER" \
                bash -c "$(lk_implode ' && ' CONFIG_COMMANDS)"
        fi
        BRANCH=$(git rev-parse --abbrev-ref HEAD) && [ "$BRANCH" != "HEAD" ] ||
            lk_die "no branch checked out"
        LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-$BRANCH}
        if [ "$LK_PLATFORM_BRANCH" != "$BRANCH" ]; then
            lk_console_warning "$(printf "%s is set to %s, but %s is checked out" \
                "LK_PLATFORM_BRANCH" \
                "$LK_BOLD$LK_PLATFORM_BRANCH$LK_RESET" \
                "$LK_BOLD$BRANCH$LK_RESET")"
            if lk_confirm "Switch to $LK_PLATFORM_BRANCH?" N; then
                lk_console_detail "Switching to" "$LK_PLATFORM_BRANCH"
                sudo -Hu "$REPO_OWNER" git checkout "$LK_PLATFORM_BRANCH"
                restart_script "$@"
            else
                LK_PLATFORM_BRANCH=$BRANCH
            fi
        fi
        REMOTE_NAME=$(git rev-parse --abbrev-ref "@{u}" | sed 's/\/.*//') &&
            [ -n "$REMOTE_NAME" ] ||
            lk_die "no upstream remote for current branch"
        FETCH_TIME=$(lk_file_modified ".git/FETCH_HEAD" 2>/dev/null) ||
            FETCH_TIME=0
        if [ $(($(lk_timestamp) - FETCH_TIME)) -gt 300 ]; then
            lk_console_detail "Checking for changes"
            if sudo -Hu "$REPO_OWNER" \
                git fetch --quiet --prune --prune-tags "$REMOTE_NAME" "$BRANCH"; then
                BEHIND=$(git rev-list --count "HEAD..@{upstream}")
                if [ "$BEHIND" -gt 0 ]; then
                    git merge-base --is-ancestor HEAD "@{upstream}" ||
                        lk_die "local branch has diverged from upstream"
                    lk_console_detail \
                        "Updating lk-platform ($BEHIND $(
                            lk_maybe_plural "$BEHIND" "commit" "commits"
                        ) behind)"
                    sudo -Hu "$REPO_OWNER" \
                        git merge --ff-only "@{upstream}"
                    restart_script "$@"
                fi
            else
                lk_console_warning0 "Unable to retrieve changes from upstream"
            fi
        fi
        lk_console_detail "Resetting file permissions"
        (
            DIR_MODE=0755
            FILE_MODE=0644
            [ ! -g "$LK_BASE" ] || {
                DIR_MODE=2775
                FILE_MODE=0664
            }
            cd "$LK_BASE"
            gnu_find . -regextype posix-egrep \
                -type d ! \( -regex '\./var/log' -prune \) \
                ! -perm -"$DIR_MODE" -print0 |
                gnu_xargs -0r gnu_chmod -c +"$DIR_MODE"
            gnu_find . -regextype posix-egrep \
                ! \( -type d -regex '\./(etc|var/log|\.git/objects)' -prune \) \
                -type f ! -perm -"$FILE_MODE" -print0 |
                gnu_xargs -0r gnu_chmod -c +"$FILE_MODE"
            install -d -m 00777 "$LK_BASE/var/log"
        )
    fi

    # Use the opening "Environment:" log entry created by hosting.sh as a last
    # resort when looking for old settings
    function install_env() {
        INSTALL_ENV="${INSTALL_ENV-$(
            [ ! -f "/var/log/${LK_PATH_PREFIX}install.log" ] ||
                awk \
                    -f "$LK_BASE/lib/awk/get-install-env.awk" \
                    <"/var/log/${LK_PATH_PREFIX}install.log"
        )}" && awk -F= \
            -v "SETTING=$1" \
            '$1 ~ "^" SETTING "$" { print $2 }' <<<"$INSTALL_ENV"
    }

    for i in "${OLD_SETTINGS[@]}"; do
        eval "\
LK_$i=\"\${LK_$i-\${LK_DEFAULT_$i-\${$i-\$(\
install_env \"(LK_(DEFAULT_)?)?$i\")}}}\"" || exit
    done

    lk_console_message "Checking lk-platform configuration"
    lk_console_detail "Base directory:" "$LK_BASE"

    # Generate /etc/default/lk-platform
    [ -e "$CONF_FILE" ] || {
        install -d -m 00755 "${CONF_FILE%/*}" &&
            install -m 00644 /dev/null "$CONF_FILE"
    }
    KNOWN_SETTINGS=()
    for i in "${SETTINGS[@]}"; do
        # Don't include null variables
        [ -n "${!i:-}" ] || continue
        KNOWN_SETTINGS+=("$i")
    done
    OTHER_SETTINGS=($(sed -En \
        -e "/^($(lk_implode '|' KNOWN_SETTINGS))=/d" \
        -e 's/^([a-zA-Z_][a-zA-Z0-9_]*)=.*/\1/p' "$CONF_FILE"))
    lk_maybe_replace "$CONF_FILE" "$(lk_get_shell_var \
        "${KNOWN_SETTINGS[@]}" \
        ${OTHER_SETTINGS[@]+"${OTHER_SETTINGS[@]}"})"

    lk_console_detail "Checking symbolic links"
    lk_safe_symlink \
        "$LK_BASE/bin/lk-bash-load.sh" "$LK_BIN_PATH/lk-bash-load.sh"

    LK_HOMES=(
        /etc/skel{,".$LK_PATH_PREFIX_ALPHA"}
        ${SUDO_USER:+"$(lk_expand_paths <<<"~$SUDO_USER")"}
        "$@"
    )
    lk_resolve_files LK_HOMES
    [ ${#LK_HOMES[@]} -gt 0 ] || lk_die "No home directories found"
    lk_echo_array LK_HOMES |
        lk_console_list "Checking startup scripts and SSH config files in:" \
            directory directories

    # Prepare awk to update ~/.bashrc
    LK_BASE_QUOTED=$(printf '%q' "$LK_BASE")
    RC_PATH=$LK_BASE_QUOTED/lib/bash/rc.sh
    LK_BASE_REAL=$(realpath "$LK_BASE")
    [ "$LK_BASE_REAL" != "$LK_BASE" ] &&
        LK_BASE_REAL_QUOTED=$(printf '%q' "$LK_BASE_REAL") ||
        LK_BASE_REAL=
    RC_PATTERNS=("$(lk_escape_ere "$LK_BASE")")
    [ "$LK_BASE_QUOTED" = "$LK_BASE" ] ||
        RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_QUOTED")")
    [ -z "$LK_BASE_REAL" ] || {
        RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_REAL")")
        [ "$LK_BASE_REAL_QUOTED" = "$LK_BASE_REAL" ] ||
            RC_PATTERNS+=("$(lk_escape_ere "$LK_BASE_REAL_QUOTED")")
    }
    IFS='|'
    RC_PATTERN="(${RC_PATTERNS[*]})(\\/.*)?\\/(\\.bashrc|rc\\.sh)"
    RC_PATTERN=${RC_PATTERN//\\/\\\\}
    RC_SH=$(printf '%s\n' \
        "if [ -f $RC_PATH ]; then" \
        "    . $RC_PATH" \
        "fi")
    RC_AWK=(awk
        -f "$LK_BASE/lib/awk/update-bashrc.awk"
        -v "RC_PATTERN=$RC_PATTERN"
        -v "RC_SH=$RC_SH")
    unset IFS

    function maybe_replace_lines() {
        local FILE=$1
        shift
        [ -e "$FILE" ] ||
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        lk_maybe_replace "$FILE" "$([ $# -eq 0 ] || printf "%s\n" "$@")" \
            '^[[:blank:]]*($|#)'
    }

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
        lk_maybe_replace "$FILE" "$("${RC_AWK[@]}" "$FILE")"

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
            lk_maybe_add_newline "$FILE" &&
                echo >>"$FILE" \
                    "[ -z \"\${BASH_VERSION:-}\" ] || [ ! -f ~/.bashrc ] || . ~/.bashrc"
        }

        DIR=$h/.byobu
        if [ ! -e "$DIR/.${LK_PATH_PREFIX}ignore" ] &&
            BYOBU_PATH=$(type -P byobu-launch); then
            for FILE in "${PROFILES[@]}"; do
                grep -q "byobu-launch" "$FILE" || {
                    lk_console_detail "Adding byobu-launch to" "$FILE"
                    lk_maybe_add_newline "$FILE" &&
                        printf '%s_byobu_sourced=1 . %q 2>/dev/null || true\n' \
                            "$(! lk_is_macos ||
                                echo '[ ! "$SSH_CONNECTION" ] || ')" \
                            "$BYOBU_PATH" >>"$FILE"
                }
            done

            [ -d "$DIR" ] ||
                install -d -m 00755 -o "$OWNER" -g "$GROUP" "$DIR"
            LK_NO_DIFF=1
            # Prevent byobu from enabling its prompt on first start
            maybe_replace_lines "$DIR/prompt"
            # Configure status notifications
            maybe_replace_lines "$DIR/status" \
                'screen_upper_left="color"' \
                'screen_upper_right="color whoami hostname #ip_address menu"' \
                'screen_lower_left="color #logo #distro release #arch #session"' \
                'screen_lower_right="color #network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk #time_utc date time"' \
                'tmux_left="#logo #distro release #arch #session"' \
                'tmux_right="#network #disk_io #custom #entropy raid reboot_required #updates_available #apport #services #mail users uptime #ec2_cost #rcs_cost #fan_speed #cpu_temp #battery #wifi_quality #processes load_average cpu_count cpu_freq memory swap disk whoami hostname #ip_address #time_utc date time"'
            # Display date as 20Aug, remove space between date and time, include
            # UTC offset
            maybe_replace_lines "$DIR/datetime.tmux" \
                'BYOBU_DATE="%-d%b"' \
                'BYOBU_TIME="%H:%M:%S%z"'
            # Turn off UTF-8 support
            maybe_replace_lines "$DIR/statusrc" \
                '[ ! -f "/etc/arch-release" ] || RELEASE_ABBREVIATED=1' \
                "BYOBU_CHARMAP=x"
            # Fix output issue when connecting from OpenSSH on Windows
            maybe_replace_lines "$DIR/.tmux.conf" \
                "set -s escape-time 50"
            unset LK_NO_DIFF
        fi
    done

    # Leave ~root/.ssh alone
    lk_remove_false "[ \"{}\" != $(printf '%q' "$(realpath ~root)") ]" LK_HOMES
    if [ -n "${LK_SSH_JUMP_HOST:-}" ]; then
        LK_NO_DIFF=1 lk_ssh_configure "$LK_SSH_JUMP_HOST" \
            "${LK_SSH_JUMP_USER:-}" \
            "${LK_SSH_JUMP_KEY:-}"
    else
        LK_NO_DIFF=1 lk_ssh_configure
    fi

    if lk_is_desktop; then
        . "$LK_BASE/lib/desktop/install.sh"
    fi

    lk_console_success "lk-platform successfully installed"

    exit
}

#!/bin/bash

set -o pipefail

[ "$EUID" -eq 0 ] || {
    # See: https://bugzilla.sudo.ws/show_bug.cgi?id=950
    SUDO_MIN=3
    ! VER=$(sudo -V | awk 'NR == 1 { print $NF }') ||
        printf '%s\n' "$VER" 1.8.9 1.8.32 1.9.0 1.9.4p1 | sort -V |
        awk -v "v=$VER" '$0 == v { l = NR } END { exit 1 - l % 2 }' ||
        SUDO_MIN=4
    sudo -H -E \
        -C "$(($(printf '%s\n' $((SUDO_MIN - 1)) \
            $((_LK_FD ? _LK_FD : 2)) $((BASH_XTRACEFD)) $((_LK_TRACE_FD)) \
            $((_LK_TTY_OUT_FD)) $((_LK_TTY_ERR_FD)) \
            $((_LK_LOG_OUT_FD)) $((_LK_LOG_ERR_FD)) \
            $((_LK_LOG_FD)) | sort -n | tail -n1) + 1))" \
        "$0" "$@" --elevated
    exit
}

set -eu
SH=$(
    lk_die() { echo "${BASH_SOURCE-$0}: $1" >&2 && false || exit; }
    _FILE=$BASH_SOURCE && [ -f "$_FILE" ] && [ ! -L "$_FILE" ] ||
        lk_die "script must be invoked directly"
    [[ $_FILE == */* ]] || _FILE=./$_FILE
    _DIR=$(cd "${_FILE%/*}" && pwd -P) &&
        printf 'export _LK_INST=%q\n' "${_DIR%/bin}" ||
        lk_die "base directory not found"
    # Override LK_* environment variables with the same name as settings in
    # $LK_BASE/etc/lk-platform/lk-platform.conf
    vars() { printf '%s\n' "${!LK_@}"; }
    unset IFS
    VARS=$(vars)
    unset $VARS
    [ ! -r /etc/default/lk-platform ] ||
        . /etc/default/lk-platform
    [ ! -r "${_DIR%/bin}/etc/lk-platform/lk-platform.conf" ] ||
        . "${_DIR%/bin}/etc/lk-platform/lk-platform.conf"
    VARS=$(vars)
    [ -z "${VARS:+1}" ] ||
        declare -p $VARS
) && eval "$SH" && . "$_LK_INST/lib/bash/common.sh" || exit
lk_require git provision

shopt -s nullglob

CONF_FILE=$_LK_INST/etc/lk-platform/lk-platform.conf

DIR_MODE=0755
FILE_MODE=0644
PRIVILEGED_DIR_MODE=0700
[ ! -g "$_LK_INST" ] || {
    DIR_MODE=2775
    FILE_MODE=0664
    PRIVILEGED_DIR_MODE=2770
}

SETTINGS=(
    LK_BASE
    LK_PATH_PREFIX
    LK_NODE_HOSTNAME
    LK_NODE_FQDN
    LK_IPV4_ADDRESS
    LK_IPV4_GATEWAY
    LK_DNS_SERVERS
    LK_DNS_SEARCH
    LK_BRIDGE_INTERFACE
    LK_WIFI_REGDOM
    LK_NODE_TIMEZONE
    LK_NODE_SERVICES
    LK_NODE_PACKAGES
    LK_NODE_LOCALES
    LK_NODE_LANGUAGE
    LK_SAMBA_WORKGROUP
    LK_GRUB_CMDLINE
    LK_NTP_SERVER
    LK_ADMIN_EMAIL
    LK_TRUSTED_IP_ADDRESSES
    LK_SSH_TRUSTED_ONLY
    LK_SSH_TRUSTED_PORT
    LK_SSH_JUMP_HOST
    LK_SSH_JUMP_USER
    LK_SSH_JUMP_KEY
    LK_REJECT_OUTPUT
    LK_ACCEPT_OUTPUT_HOSTS
    LK_INNODB_BUFFER_SIZE
    LK_OPCACHE_MEMORY_CONSUMPTION
    LK_PHP_VERSIONS
    LK_PHP_SETTINGS
    LK_PHP_ADMIN_SETTINGS
    LK_MEMCACHED_MEMORY_LIMIT
    LK_SMTP_RELAY
    LK_SMTP_CREDENTIALS
    LK_SMTP_SENDERS
    LK_EMAIL_DESTINATION
    LK_UPGRADE_EMAIL
    LK_AUTO_REBOOT
    LK_AUTO_REBOOT_TIME
    LK_AUTO_BACKUP_SCHEDULE
    LK_SNAPSHOT_HOURLY_MAX_AGE
    LK_SNAPSHOT_DAILY_MAX_AGE
    LK_SNAPSHOT_WEEKLY_MAX_AGE
    LK_SNAPSHOT_FAILED_MAX_AGE
    LK_LAUNCHPAD_PPA_MIRROR
    LK_SITE_ENABLE
    LK_SITE_DISABLE_WWW
    LK_SITE_DISABLE_HTTPS
    LK_SITE_ENABLE_STAGING
    LK_ARCH_MIRROR
    LK_ARCH_REPOS
    LK_DEBUG
    LK_PLATFORM_BRANCH
    LK_PACKAGES_FILE
)

LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-1}
LK_FILE_BACKUP_MOVE=1
LK_VERBOSE=${LK_VERBOSE-1}

NEW_SETTINGS=()
unset ELEVATED NO_UPGRADE

lk_getopt "s:" "elevated,set:,no-upgrade"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -s | --set)
        [[ $1 =~ ^(LK_[a-zA-Z0-9_]*[a-zA-Z0-9])=(.*) ]] ||
            lk_die "invalid argument: $1"
        NEW_SETTINGS+=("${BASH_REMATCH[1]}")
        eval "${BASH_REMATCH[1]}=\${BASH_REMATCH[2]}"
        shift
        ;;
    --elevated)
        ELEVATED=1
        ;;
    --no-upgrade)
        NO_UPGRADE=1
        ;;
    --)
        break
        ;;
    esac
done

lk_lock

lk_log_start

{
    lk_tty_log "Configuring lk-platform"

    if [[ ${_LK_INST##*/} =~ ^([a-zA-Z0-9]{2,3}-)platform$ ]] &&
        [ "${BASH_REMATCH[1]}" != lk- ]; then
        ORIGINAL_PATH_PREFIX=${BASH_REMATCH[1]}
        OLD_LK_INST=$_LK_INST
        _LK_INST=${_LK_INST%/*}/lk-platform
        lk_tty_print "Renaming installation directory"
        if [ -e "$_LK_INST" ] && [ ! -L "$_LK_INST" ]; then
            BACKUP_DIR=$_LK_INST$(lk_file_get_backup_suffix)
            [ ! -e "$BACKUP_DIR" ] || lk_die "$BACKUP_DIR already exists"
            mv -fv "$_LK_INST" "$BACKUP_DIR"
        fi
        rm -fv "$_LK_INST"
        mv -v "$OLD_LK_INST" "$_LK_INST"
        lk_symlink lk-platform "$OLD_LK_INST"
    fi

    lk_tty_print "Checking environment"
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${PATH_PREFIX:-${ORIGINAL_PATH_PREFIX-}}}
    [ -n "$LK_PATH_PREFIX" ] || lk_no_input || {
        lk_tty_detail "LK_PATH_PREFIX is not set"
        lk_tty_detail \
            "Value must be 2-3 alphanumeric characters followed by a hyphen"
        lk_tty_detail "Default value:" "lk-"
        while [[ ! $LK_PATH_PREFIX =~ ^[a-zA-Z0-9]{2,3}-$ ]]; do
            [ -z "$LK_PATH_PREFIX" ] ||
                lk_tty_error "Invalid LK_PATH_PREFIX:" "$LK_PATH_PREFIX"
            lk_tty_read "Path prefix (required):" LK_PATH_PREFIX
        done
    }
    [ -n "$LK_PATH_PREFIX" ] || lk_die "LK_PATH_PREFIX not set"
    [ -z "${LK_BASE-}" ] ||
        [ "$LK_BASE" = "$_LK_INST" ] ||
        [ "$LK_BASE" = "${OLD_LK_INST-}" ] ||
        [ ! -d "$LK_BASE" ] ||
        {
            lk_tty_print "Existing installation found at" "$LK_BASE"
            lk_confirm "Reconfigure system?" Y || lk_die ""
        }
    export LK_BASE=$_LK_INST

    lk_is_arch && _IS_ARCH=1 || _IS_ARCH=
    _BASHRC='[ -z "${BASH_VERSION-}" ] || [ ! -f ~/.bashrc ] || . ~/.bashrc'
    _BYOBU=
    _BYOBURC=
    if BYOBU_PATH=$(type -P byobu-launch); then
        _BYOBU=$(
            ! lk_is_macos ||
                printf '[ ! "$SSH_CONNECTION" ] || '
            printf '_byobu_sourced=1 . %q 2>/dev/null || true' "$BYOBU_PATH"
        )
        ! lk_is_macos ||
            _BYOBURC='[[ $OSTYPE != darwin* ]] || ! type -P gdf >/dev/null || df() { gdf "$@"; }'
    fi

    lk_tty_print "Checking sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default
    [ ! -e "${FILE}s" ] || [ -e "$FILE" ] ||
        mv -fv "${FILE}s" "$FILE"
    [ -e "$FILE" ] ||
        install -m 00440 /dev/null "$FILE"
    lk_file_replace "$FILE" "$(cat "$LK_BASE/share/sudoers.d/default")"

    lk_tty_print "Checking GNU utilities"
    function install_gnu_commands() {
        local GNU_COMMANDS i STATUS=0
        if ! lk_is_macos; then
            GNU_COMMANDS=(
                gawk gnu_awk 1
                chgrp gnu_chgrp 0
                chmod gnu_chmod 1
                chown gnu_chown 1
                cp gnu_cp 1
                date gnu_date 1
                dd gnu_dd 1
                df gnu_df 1
                diff gnu_diff 1
                du gnu_du 0
                find gnu_find 1
                getopt gnu_getopt 1
                grep gnu_grep 1
                ln gnu_ln 0
                mktemp gnu_mktemp 0
                mv gnu_mv 0
                realpath gnu_realpath 1
                sed gnu_sed 1
                sort gnu_sort 0
                stat gnu_stat 1
                tar gnu_tar 0
                uniq gnu_uniq 1
                xargs gnu_xargs 1
            )
        else
            GNU_COMMANDS=(
                gawk gnu_awk 1
                gchgrp gnu_chgrp 0
                gchmod gnu_chmod 1
                gchown gnu_chown 1
                gcp gnu_cp 1
                gdate gnu_date 1
                gdd gnu_dd 1
                gdf gnu_df 1
                "${HOMEBREW_PREFIX:-$_LK_HOMEBREW_PREFIX}/opt/diffutils/bin/diff" gnu_diff 1
                gdu gnu_du 0
                gfind gnu_find 1
                "${HOMEBREW_PREFIX:-$_LK_HOMEBREW_PREFIX}/opt/gnu-getopt/bin/getopt" gnu_getopt 1
                ggrep gnu_grep 1
                gln gnu_ln 0
                gmktemp gnu_mktemp 0
                gmv gnu_mv 0
                grealpath gnu_realpath 1
                gsed gnu_sed 1
                gsort gnu_sort 0
                gstat gnu_stat 1
                gtar gnu_tar 0
                guniq gnu_uniq 1
                gxargs gnu_xargs 1
            )
        fi
        for ((i = 0; i < ${#GNU_COMMANDS[@]}; i += 3)); do
            lk_symlink_bin "${GNU_COMMANDS[@]:i:2}" ||
                [ "${GNU_COMMANDS[*]:i+2:1}" -eq 0 ] ||
                STATUS=$?
        done
        return "$STATUS"
    }
    install_gnu_commands

    lk_tty_print "Checking lk-platform settings"
    [ -e "$CONF_FILE" ] || {
        install -d -m "$DIR_MODE" "${CONF_FILE%/*}" "${CONF_FILE%/*/*}" &&
            install -m "$FILE_MODE" /dev/null "$CONF_FILE"
    }

    # Use the opening "Environment:" log entry created by hosting.sh as a last
    # resort when looking for settings
    function install_env() {
        [ -n "${INSTALL_ENV+1}" ] ||
            INSTALL_ENV=$(
                FILE=$(lk_first_existing \
                    /var/log/{"$LK_PATH_PREFIX",lk-platform-}install.log) ||
                    exit 0
                awk -f "$LK_BASE/lib/awk/get-install-env.awk" "$FILE"
            ) || return
        [ -n "${INSTALL_ENV:+1}" ] || return 0
        awk -F= \
            -v "SETTING=$1" \
            '$1 == SETTING { print $2 }' <<<"$INSTALL_ENV"
    }

    for i in "${SETTINGS[@]}"; do
        SH=$(printf \
            '%s=${%s-${%s-${%s-${%s-$(install_env "(LK_(NODE_|DEFAULT_)?)?%s")}}}}' \
            "$i" "$i" "LK_NODE_${i#LK_}" "LK_DEFAULT_${i#LK_}" "${i#LK_}" \
            "${i#LK_}") &&
            eval "$SH"
    done

    KNOWN_SETTINGS=()
    for i in "${SETTINGS[@]}"; do
        # Don't include null variables unless they already appear in
        # $LK_BASE/etc/lk-platform/lk-platform.conf
        [ -n "${!i-}" ] ||
            grep -Eq "^$i=" "$CONF_FILE" ||
            lk_in_array "$i" NEW_SETTINGS ||
            continue
        KNOWN_SETTINGS+=("$i")
    done
    OTHER_SETTINGS=($(comm -23 \
        <({ lk_echo_array NEW_SETTINGS &&
            sed -En \
                -e '/^LK_(PATH_PREFIX_ALPHA|SCRIPT_DEBUG|EMAIL_BLACKHOLE)=/d' \
                -e 's/^([a-zA-Z_][a-zA-Z0-9_]*)=.*/\1/p' "$CONF_FILE"; } |
            sort -u) \
        <(lk_echo_array KNOWN_SETTINGS | sort)))
    lk_file_replace "$CONF_FILE" "$(lk_var_sh \
        "${KNOWN_SETTINGS[@]}" \
        ${OTHER_SETTINGS[@]+"${OTHER_SETTINGS[@]}"})"

    function restart_script() {
        lk_lock_drop
        lk_tty_print "Restarting ${0##*/}"
        lk_maybe_trace "$0" --no-log "$@"
        exit
    }

    if [ -d "$LK_BASE/.git" ]; then
        function check_repo_config() {
            local VALUE
            VALUE=$(git config --local "$1") &&
                [ "$VALUE" = "$2" ] ||
                CONFIG_COMMANDS+=("$(printf 'config %q %q' "$1" "$2")")
        }
        function update_repo() {
            local BRANCH=${1:-$BRANCH} _LK_GIT_USER=$REPO_OWNER
            lk_git_update_repo_to -f "$REMOTE" "$BRANCH"
        }
        UMASK=$(umask)
        umask 002
        lk_tty_print "Checking repository"
        cd "$LK_BASE"
        lk_git_maybe_add_safe_directory --system
        REPO_OWNER=$(lk_file_owner "$LK_BASE")
        CONFIG_COMMANDS=()
        [ ! -g "$LK_BASE" ] ||
            check_repo_config "core.sharedRepository" "0664"
        check_repo_config "merge.ff" "only"
        check_repo_config "pull.ff" "only"
        for COMMAND in ${CONFIG_COMMANDS[@]+"${CONFIG_COMMANDS[@]}"}; do
            lk_tty_detail "Running:" "$(lk_quote_args git $COMMAND)"
            lk_run_as "$REPO_OWNER" git $COMMAND
        done
        REMOTE=$(lk_git_branch_upstream_remote) ||
            lk_die "no upstream remote for current branch"
        BRANCH=$(lk_git_branch_current) ||
            lk_die "no branch checked out"
        LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-$BRANCH}
        if [ "$LK_PLATFORM_BRANCH" != "$BRANCH" ]; then
            lk_tty_error "$(printf \
                "%s is set to %s, but %s is checked out" \
                "LK_PLATFORM_BRANCH" \
                "$LK_BOLD$LK_PLATFORM_BRANCH$LK_RESET" \
                "$LK_BOLD$BRANCH$LK_RESET")"
            LK_PLATFORM_BRANCH=$BRANCH
        fi
        if [ -z "${NO_UPGRADE-}" ]; then
            FETCH_TIME=$(lk_file_modified ".git/FETCH_HEAD" 2>/dev/null) ||
                FETCH_TIME=0
            if [ $(($(lk_timestamp) - FETCH_TIME)) -gt 300 ]; then
                lk_tty_detail "Checking for changes"
                ! update_repo ||
                    ! lk_is_true LK_GIT_REPO_UPDATED ||
                    restart_script "$@"
            fi
        fi
        install -d -m 01777 "$LK_BASE/var/log"
        install -d -m 00750 "$LK_BASE/var/backup"
        install -d -m "$PRIVILEGED_DIR_MODE" "$LK_BASE/var/run"{,/dirty}
        LK_VERBOSE='' \
            lk_dir_set_modes "$LK_BASE" \
            "" \
            "+$DIR_MODE" "+$FILE_MODE" \
            '\./(etc|var)/' \
            "$DIR_MODE" "" \
            '\./(etc(/lk-platform)?/sites|var/run(/dirty)?)/' \
            "$PRIVILEGED_DIR_MODE" "" \
            '\./var/(log|backup)/' \
            "" "" \
            '\./\.git/objects/([0-9a-f]{2}|pack)/.*' \
            0555 0444
        umask "$UMASK"
    fi

    lk_tty_print "Checking symbolic links"
    lk_symlink_bin "$LK_BASE/bin/lk-bash-load.sh"

    if lk_is_true ELEVATED; then
        _LK_HOMES=(${SUDO_USER:+"$(lk_expand_path "~$SUDO_USER")"})
    else
        # If invoked by root, include all standard home directories
        lk_mapfile _LK_HOMES <(comm -12 \
            <(lk_echo_args /home/* /srv/www/* /Users/* ~root |
                lk_filter 'test -d' | sort -u) \
            <(if ! lk_is_macos; then
                getent passwd | cut -d: -f6
            else
                dscl . list /Users NFSHomeDirectory | awk '{print $2}'
            fi | sort -u))
    fi
    _LK_HOMES+=(/etc/skel{,".${LK_PATH_PREFIX%-}"})
    lk_remove_missing _LK_HOMES
    lk_resolve_files _LK_HOMES
    [ ${#_LK_HOMES[@]} -gt 0 ] || lk_die "No home directories found"
    lk_tty_print "Checking startup scripts and SSH config files"

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
        lk_file_replace -li '^[[:blank:]]*($|#)' "$FILE" \
            "$([ $# -eq 0 ] || printf "%s\n" "$@")"
    }

    LK_FILE_NO_DIFF=1
    for h in "${_LK_HOMES[@]}"; do
        [ ! -e "$h/.${LK_PATH_PREFIX}ignore" ] || continue
        OWNER=$(lk_file_owner "$h")
        GROUP=$(id -gn "$OWNER")

        # Create ~/.bashrc if it doesn't exist, then add or update commands to
        # source LK_BASE/lib/bash/rc.sh at startup when Bash is running as a
        # non-login shell (e.g. in most desktop terminals on Linux)
        FILE=$h/.bashrc
        [ -e "$FILE" ] ||
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        lk_file_replace -l "$FILE" "$("${RC_AWK[@]}" "$FILE")"

        # Create ~/.profile if no profile file exists, then check that ~/.bashrc
        # is sourced at startup when Bash is running as a login shell (e.g. in a
        # default SSH session or a macOS terminal)
        PROFILES=("$h/.bash_profile" "$h/.bash_login" "$h/.profile")
        lk_remove_missing PROFILES
        [ ${#PROFILES[@]} -gt "0" ] || {
            FILE=$h/.profile
            PROFILES+=("$FILE")
            install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
        }
        grep -q '\.bashrc' "${PROFILES[@]}" || {
            FILE=${PROFILES[0]}
            lk_file_get_text "$FILE" CONTENT &&
                lk_file_replace -l "$FILE" "$CONTENT$_BASHRC"
        }

        install -d -m 00755 -o "$OWNER" -g "$GROUP" "$h/.lk-platform"

        DIR=$h/.byobu
        if [ ! -e "$DIR/.${LK_PATH_PREFIX}ignore" ] &&
            [ -n "$_BYOBU" ]; then
            for FILE in "${PROFILES[@]}"; do
                grep -q "byobu-launch" "$FILE" || {
                    lk_file_get_text "$FILE" CONTENT &&
                        lk_file_replace -l "$FILE" "$CONTENT$_BYOBU"
                }
            done
            FILE=$h/.byoburc
            if [ -n "$_BYOBURC" ] &&
                ! grep -q '\bdf()' "$FILE" 2>/dev/null; then
                lk_tty_detail "Adding df wrapper to" "$FILE"
                if [ ! -e "$FILE" ]; then
                    install -m 00644 -o "$OWNER" -g "$GROUP" /dev/null "$FILE"
                    CONTENT=$'#!/bin/bash\n\n'
                else
                    lk_file_get_text "$FILE" CONTENT
                fi
                lk_file_replace -l "$FILE" "$CONTENT$_BYOBURC"
            fi

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
            # Use Ctrl+A to go to beginning of line
            replace_byobu "$DIR/keybindings.tmux" \
                "set -g prefix F12" \
                "unbind-key -n C-a" \
                "unbind-key -n M-Left" \
                "unbind-key -n M-Right"
            # Fix output issue when connecting from OpenSSH on Windows
            replace_byobu "$DIR/.tmux.conf" \
                "set -s escape-time 50"
        fi
    done

    unset LK_FILE_BACKUP_TAKE

    # Leave ~root/.ssh alone
    lk_remove_false "$(printf '[ "{}" != %q ]' "$(lk_realpath ~root)")" _LK_HOMES
    if [ -n "${LK_SSH_JUMP_HOST-}" ]; then
        lk_ssh_configure "$LK_SSH_JUMP_HOST" \
            "${LK_SSH_JUMP_USER-}" \
            "${LK_SSH_JUMP_KEY-}"
    else
        lk_ssh_configure
    fi

    if lk_is_desktop; then
        . "$LK_BASE/lib/platform/configure-desktop.sh"
    fi

    lk_tty_success "lk-platform successfully configured"

    exit
}

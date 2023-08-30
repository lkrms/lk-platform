#!/bin/bash

set -euo pipefail

lk_die() { s=$? && echo "$0: ${1-error $s}" >&2 && (exit $s) && false || exit; }

SH=$(
    _file=$BASH_SOURCE && [[ -f $_file ]] && [[ ! -L $_file ]] ||
        lk_die "script must be invoked directly"
    [[ $_file == */* ]] || _file=./$_file
    _dir=$(cd "${_file%/*}" && pwd -P) && _dir=${_dir%/bin} ||
        lk_die "base directory not found"
    # Override LK_* environment variables with the same name as settings in
    # $LK_BASE/etc/lk-platform/lk-platform.conf
    unset "${!LK_@}"
    readonly _dir _conf=$_dir/etc/lk-platform/lk-platform.conf
    for _file in /etc/default/lk-platform "$_conf"; do
        [[ ! -r $_file ]] || . "$_file" || lk_die "error loading configuration"
    done >&2
    printf 'export LK_BASE=%q\n' "$_dir" &&
        unset LK_BASE &&
        declare -p "${!LK_@}" &&
        printf 'CONF_FILE=%q\n' "$_conf"
) && eval "$SH" || exit

_LK_CONFIG_LOADED=1 \
    . "$LK_BASE/lib/bash/common.sh"
lk_require git provision

lk_assert_root

shopt -s nullglob

unset IS_ARCH IS_GIT_REPO
DIR_MODE=0755
FILE_MODE=0644
PRIVILEGED_DIR_MODE=0700

lk_is_arch && IS_ARCH=
[[ ! -d $LK_BASE/.git ]] || {
    IS_GIT_REPO=
    [[ ! -g $LK_BASE ]] || {
        DIR_MODE=2775
        FILE_MODE=0664
        PRIVILEGED_DIR_MODE=2770
    }
}

LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-1}
LK_FILE_BACKUP_MOVE=1
LK_VERBOSE=${LK_VERBOSE-1}

unset RENAME SUDOERS PREVIOUS_PREFIX
NO_UPGRADE=1

SETTINGS_SH=$(lk_settings_getopt "$@")
eval "$SETTINGS_SH"
shift "$_LK_SHIFT"

lk_getopt -"$_LK_SHIFT" "r::" "rename::,sudo,no-upgrade"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -r | --rename)
        RENAME=${1:-lk-platform}
        shift
        ;;
    --sudo)
        SUDOERS=1
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

    if [[ -n ${RENAME-} ]] &&
        [[ ${LK_BASE##*/} != "$RENAME" ]] &&
        [[ -n ${IS_GIT_REPO+1} ]]; then
        [[ ! ${LK_BASE##*/} =~ (^[a-zA-Z0-9]{2,3}-)?platform ]] ||
            PREVIOUS_PREFIX=${BASH_REMATCH[1]}
        PREVIOUS_BASE=$LK_BASE
        LK_BASE=${LK_BASE%/*}/$RENAME
        lk_tty_print "Renaming installation directory"
        [[ ! -e $LK_BASE ]] || [[ -L $LK_BASE ]] ||
            lk_die "$LK_BASE already exists"
        rm -fv "$LK_BASE"
        mv -v "$PREVIOUS_BASE" "$LK_BASE"
        ln -s "$RENAME" "$PREVIOUS_BASE"
    fi

    lk_tty_print "Checking environment"
    LK_PATH_PREFIX=${LK_PATH_PREFIX:-${PREVIOUS_PREFIX-}}
    [[ -n $LK_PATH_PREFIX ]] ||
        if ! lk_no_input; then
            lk_tty_detail "LK_PATH_PREFIX is not set"
            lk_tty_detail \
                "Value must be 2-3 alphanumeric characters followed by a hyphen"
            while [[ ! $LK_PATH_PREFIX =~ ^[a-zA-Z0-9]{2,3}-$ ]]; do
                [[ -z $LK_PATH_PREFIX ]] ||
                    lk_tty_error "Invalid LK_PATH_PREFIX:" "$LK_PATH_PREFIX"
                lk_tty_read "Path prefix:" LK_PATH_PREFIX lk-
            done
        else
            lk_warn "LK_PATH_PREFIX not set, using 'lk-'" || LK_PATH_PREFIX=lk-
        fi

    (LK_VERBOSE=1 &&
        lk_settings_persist "$SETTINGS_SH$(printf '\n%s=%q' \
            LK_BASE "$LK_BASE" \
            LK_PATH_PREFIX "$LK_PATH_PREFIX")")

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

    if [[ -n ${SUDOERS-} ]]; then
        lk_tty_print "Checking sudo"
        lk_sudo_apply_sudoers "$LK_BASE/share/sudoers.d/default"
    fi

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
                du gnu_du 1
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
                timeout gnu_timeout 0
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
                gdu gnu_du 1
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
                gtimeout gnu_timeout 0
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

    function restart_script() {
        lk_lock_drop
        lk_tty_print "Restarting ${0##*/}"
        lk_maybe_trace "$0" --no-log "$@"
        exit
    }

    if [ -d "$LK_BASE/.git" ]; then
        function check_repo_config() {
            local VALUE
            VALUE=$(lk_git config --local "$1") &&
                [ "$VALUE" = "$2" ] ||
                CONFIG_COMMANDS+=("$(printf 'config %q %q' "$1" "$2")")
        }
        function update_repo() {
            local BRANCH=${1:-$BRANCH}
            lk_git_update_repo_to -f "$REMOTE" "$BRANCH"
        }
        UMASK=$(umask)
        umask 002
        lk_tty_print "Checking repository"
        cd "$LK_BASE"
        lk_git_maybe_add_safe_directory --system
        _LK_GIT_USER=$(lk_file_owner "$LK_BASE")
        CONFIG_COMMANDS=()
        [ ! -g "$LK_BASE" ] ||
            check_repo_config "core.sharedRepository" "0664"
        check_repo_config "merge.ff" "only"
        check_repo_config "pull.ff" "only"
        for COMMAND in ${CONFIG_COMMANDS[@]+"${CONFIG_COMMANDS[@]}"}; do
            lk_tty_run_detail -1=git lk_git $COMMAND
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
                    ! lk_true LK_GIT_REPO_UPDATED ||
                    restart_script "$@"
            fi
        fi
        unset _LK_GIT_USER
        install -d -m 01777 "$LK_BASE/var/log"
        install -d -m 00750 "$LK_BASE/var/backup"
        install -d -m "$PRIVILEGED_DIR_MODE" "$LK_BASE/var/lib/lk-platform/dirty"
        LK_VERBOSE='' \
            lk_dir_set_modes "$LK_BASE" \
            "" \
            "+$DIR_MODE" "+$FILE_MODE" \
            '\./(etc|var)/' \
            "$DIR_MODE" "" \
            '\./(etc(/lk-platform)?/sites|var/(run|lib/lk-platform)/(dirty|sites))/' \
            "$PRIVILEGED_DIR_MODE" "" \
            '\./var/(log|backup)/' \
            "" "" \
            '\./\.git/objects/([0-9a-f]{2}|pack)/.*' \
            0555 0444
        umask "$UMASK"
    fi

    lk_tty_print "Checking symbolic links"
    lk_symlink_bin "$LK_BASE/bin/lk-bash-load.sh"

    # Include all standard home directories
    lk_mapfile _LK_HOMES <(comm -12 \
        <(lk_echo_args /home/* /srv/www/* /Users/* ~root |
            lk_filter 'test -d' | sort -u) \
        <(if ! lk_is_macos; then
            getent passwd | cut -d: -f6
        else
            dscl . list /Users NFSHomeDirectory | awk '{print $2}'
        fi | sort -u))
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
    # Some awk variants fail with "newline in string" when a newline character
    # appears in a command-line variable, so leave newlines as '\n' literals
    RC_SH="if [ -f $RC_PATH ]; then\\n    . $RC_PATH\\nfi"
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
    lk_mktemp_with TEMP
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
        grep -Fq " $RC_PATH " "$FILE" ||
            { "${RC_AWK[@]}" "$FILE" >"$TEMP" &&
                lk_file_replace -l "$FILE" "$(<"$TEMP")"; }

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
                ${IS_ARCH+'[ ! -f "/etc/arch-release" ] || RELEASE_ABBREVIATED=1'} \
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

#!/bin/bash

# To provision macOS using the script below:
#
#     [LK_NO_INPUT=1] bash -c "$(curl -fsSL http://lkr.ms/macos)"
#
# Or, to test the 'develop' branch:
#
#     [LK_NO_INPUT=1] LK_PLATFORM_BRANCH=develop _LK_FD=3 \
#         bash -xc "$(curl -fsSL http://lkr.ms/macos-dev)" 3>&2 2>~/lk-install.err

LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}
export LK_BASE=${LK_BASE:-/opt/lk-platform}

set -euo pipefail
lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (exit $s) && false || exit; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[[ $OSTYPE == darwin* ]] || lk_die "not running on macOS"
[[ $- != *s* ]] || lk_die "cannot run from standard input"

umask 002

function exit_trap() {
    local EXT _LOG_FILE LOG_FILE _LK_LOG_BASENAME=lk-provision-macos.sh \
        _LOG=$_LK_LOG_FILE_LOG _OUT=$_LK_LOG_FILE_OUT
    lk_log_close || return
    for EXT in log out; do
        _LOG_FILE=_$(lk_upper "$EXT") &&
            _LOG_FILE=${!_LOG_FILE} &&
            LOG_FILE=$(lk_log_create_file -e "$EXT") &&
            [ "$LOG_FILE" != "$_LOG_FILE" ] || continue
        lk_console_log "Moving:" "$_LOG_FILE -> $LOG_FILE"
        cat "$_LOG_FILE" >>"$LOG_FILE" &&
            rm "$_LOG_FILE" ||
            lk_console_warning "Error moving" "$_LOG_FILE"
    done
}

{
    export SUDO_PROMPT="[sudo] password for %p: "

    CURL_OPTIONS=(
        --fail
        --header "Cache-Control: no-cache"
        --header "Pragma: no-cache"
        --location
        --retry 2
        --show-error
        --silent
    )

    _DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$_DIR"

    STATUS=0
    unset BREW

    function load_settings() {
        local FILE
        for FILE in /etc/default/lk-platform \
            "$LK_BASE/etc/lk-platform"/lk{-platform,}.conf; do
            [ ! -f "$FILE" ] || . "$FILE" || return
        done
        SETTINGS_SH=$(lk_settings_getopt "$@") &&
            eval "$SETTINGS_SH" &&
            shift "$_LK_SHIFT" || return

        LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE-}}
        PACKAGES_REL=
        [ -n "$LK_PACKAGES_FILE" ] || return 0
        [ -f "$LK_PACKAGES_FILE" ] || {
            FILE=${LK_PACKAGES_FILE##*/}
            FILE=${FILE#packages-macos-}
            FILE=${FILE%.sh}
            FILE=$LK_BASE/share/packages/macos/$FILE.sh
            [ -f "$FILE" ] || PACKAGES_REL=${FILE#"$LK_BASE/"}
            LK_PACKAGES_FILE=$FILE
        }
        SETTINGS_SH=$(
            [ -z "${SETTINGS_SH:+1}" ] || cat <<<"$SETTINGS_SH"
            printf '%s=%q\n' LK_PACKAGES_FILE "$LK_PACKAGES_FILE"
        )
    }

    if [ -f "$LK_BASE/lib/bash/include/core.sh" ]; then
        . "$LK_BASE/lib/bash/include/core.sh"
        lk_include brew macos provision whiptail
        SUDOERS=$LK_BASE/share/sudoers.d/default
        load_settings "$@"
        ${PACKAGES_REL:+. "$LK_BASE/$PACKAGES_REL"}
    else
        YELLOW=$'\E[33m'
        CYAN=$'\E[36m'
        BOLD=$'\E[1m'
        RESET=$'\E[m\017'
        echo "$BOLD$CYAN==> $RESET${BOLD}Checking prerequisites$RESET" >&2
        REPO_URL=https://raw.githubusercontent.com/lkrms/lk-platform
        for FILE_PATH in \
            lib/bash/include/{core,brew,macos,provision,whiptail}.sh \
            share/sudoers.d/default{,-macos} ""; do
            [ -n "$FILE_PATH" ] || {
                load_settings "$@"
                [ -n "$PACKAGES_REL" ] || break
                FILE_PATH=$PACKAGES_REL
            }
            FILE=$_DIR/${FILE_PATH//\//__}
            URL=$REPO_URL/$LK_PLATFORM_BRANCH/$FILE_PATH
            MESSAGE="$BOLD$YELLOW -> $RESET{}$YELLOW $URL$RESET"
            if [ ! -e "$FILE" ]; then
                echo "${MESSAGE/{\}/Downloading:}" >&2
                curl "${CURL_OPTIONS[@]}" --output "$FILE" "$URL" || {
                    rm -f "$FILE"
                    lk_die "unable to download: $URL"
                }
            else
                echo "${MESSAGE/{\}/Already downloaded:}" >&2
            fi
            [[ ! $FILE_PATH =~ /include/[a-z0-9_]+\.sh$ ]] ||
                . "$FILE"
        done
        SUDOERS=$_DIR/share__sudoers.d__default
    fi

    ! lk_is_system_apple_silicon || lk_is_apple_silicon ||
        lk_die "not running on native architecture"

    LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-1}
    LK_FILE_BACKUP_MOVE=1

    lk_log_start ~/"${LK_PATH_PREFIX}install"
    lk_trap_add EXIT exit_trap

    lk_console_log "Provisioning macOS"

    lk_sudo_offer_nopasswd || lk_die "unable to run commands as root"

    sudo systemsetup -getremotelogin | grep -Ei '\<On$' >/dev/null || {
        [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 01 ] || lk_die ""
        ! lk_confirm "Enable remote access to this computer via SSH?" N || {
            lk_tty_print "Enabling Remote Login (SSH)"
            lk_run_detail sudo systemsetup -setremotelogin on
        }
    }

    sudo systemsetup -getcomputersleep | grep -Ei '\<Never$' >/dev/null || {
        [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 01 ] || lk_die ""
        ! lk_confirm "Prevent sleep when display is off?" N || {
            lk_tty_print "Disabling computer sleep"
            lk_run_detail sudo systemsetup -setcomputersleep off
        }
    }

    scutil --get HostName &>/dev/null || {
        [ -n "${LK_NODE_HOSTNAME-}" ] ||
            lk_tty_read "System hostname (optional):" LK_NODE_HOSTNAME ||
            lk_die ""
        [ -z "$LK_NODE_HOSTNAME" ] ||
            lk_macos_set_hostname "$LK_NODE_HOSTNAME"
    }

    CURRENT_SHELL=$(lk_dscl_read UserShell)
    [[ $CURRENT_SHELL == */bash ]] ||
        ! lk_confirm "Use Bash as the default shell for user '$USER'?" N || {
        lk_tty_print "Setting default shell"
        lk_run_detail sudo chsh -s /bin/bash "$USER"
    }

    lk_tty_print "Configuring sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default
    sudo test ! -e "${FILE}s" || sudo test -e "$FILE" ||
        sudo mv -v "${FILE}s" "$FILE"
    for SUFFIX in "" -macos; do
        [ -z "$SUFFIX" ] || FILE=${FILE%/*}/zz-${FILE##*/}
        sudo test -e "$FILE$SUFFIX" ||
            sudo install -m 00440 /dev/null "$FILE$SUFFIX"
        (LK_SUDO=1 && lk_file_replace -f "$SUDOERS$SUFFIX" "$FILE$SUFFIX")
    done

    lk_tty_print "Configuring default umask"
    { defaults read /var/db/com.apple.xpc.launchd/config/user.plist Umask |
        grep -Fx 2; } &>/dev/null ||
        lk_run_detail sudo launchctl config user umask 002 >/dev/null
    FILE=/etc/profile
    [ ! -r "$FILE" ] || grep -Eq '\<umask\>' "$FILE" || {
        lk_tty_detail "Setting umask in" "$FILE"
        (LK_SUDO=1 && lk_file_keep_original "$FILE") &&
            sudo tee -a "$FILE" <<"EOF" >/dev/null

if [ "$(id -u)" -ne 0 ]; then
    umask 002
else
    umask 022
fi
EOF
    }

    function path_add() {
        local STATUS
        while [ $# -gt 0 ]; do
            [[ :$_PATH: == *:$1:* ]] || {
                _PATH=$1:${_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
                STATUS=1
            }
            shift
        done
        return "${STATUS:-0}"
    }
    PATH_ADD=(/usr/local/{sbin,bin})
    BREW_PATH=(/usr/local/bin/brew)
    BREW_ARCH=("")
    BREW_NAMES=("Homebrew")
    ! lk_is_apple_silicon || {
        PATH_ADD+=(/opt/homebrew/{sbin,bin})
        BREW_PATH=(/opt/homebrew/bin/brew)
    }
    lk_tty_print "Configuring default PATH"
    _PATH=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist \
        PathEnvironmentVariable 2>/dev/null) || _PATH=
    path_add "${PATH_ADD[@]}" ||
        lk_run_detail sudo launchctl config user path "$_PATH" >/dev/null
    _PATH=$PATH
    path_add "${PATH_ADD[@]}" ||
        PATH=$_PATH

    # Disable sleep when charging
    sudo pmset -c sleep 0

    # Always restart on power loss
    sudo pmset -a autorestart 1

    lk_macos_xcode_maybe_accept_license
    lk_macos_install_command_line_tools

    # If Xcode and the standalone Command Line Tools package are both installed,
    # switch to Xcode or commands like opendiff won't work
    if [ -e /Applications/Xcode.app ]; then
        TOOLS_PATH=$(lk_macos_command_line_tools_path)
        if [[ $TOOLS_PATH != /Applications/Xcode.app* ]]; then
            lk_tty_print "Configuring Xcode"
            lk_run_detail sudo xcode-select --switch /Applications/Xcode.app
            OLD_TOOLS_PATH=$TOOLS_PATH
            TOOLS_PATH=$(lk_macos_command_line_tools_path)
            lk_tty_detail "Development tools directory:" \
                "$OLD_TOOLS_PATH -> $LK_BOLD$TOOLS_PATH$LK_RESET"
        fi
    fi

    if [ ! -e "$LK_BASE" ] || [ -z "$(ls -A "$LK_BASE")" ]; then
        lk_tty_print "Installing lk-platform to" "$LK_BASE"
        sudo install -d -m 02775 -o "$USER" -g admin "$LK_BASE"
        lk_faketty caffeinate -d git clone -b "$LK_PLATFORM_BRANCH" \
            https://github.com/lkrms/lk-platform.git "$LK_BASE"
        sudo install -d -m 02775 -g admin "$LK_BASE"/{etc{,/lk-platform},var}
        sudo install -d -m 01777 -g admin "$LK_BASE"/var/log
        sudo install -d -m 00750 -g admin "$LK_BASE"/var/backup
        FILE=$LK_BASE/etc/lk-platform/lk-platform.conf
        sudo install -m 00664 -g admin /dev/null "$FILE"
        lk_var_sh \
            LK_BASE \
            LK_PATH_PREFIX \
            LK_PLATFORM_BRANCH \
            LK_PACKAGES_FILE |
            sudo tee "$FILE" >/dev/null
        lk_console_detail_file "$FILE"
    fi

    (
        LK_VERBOSE=1
        LK_SUDO=1
        lk_settings_persist "$SETTINGS_SH"
    )

    [ -z "$LK_PACKAGES_FILE" ] ||
        . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/macos/packages.sh"

    function brew_loop() {
        local i SH BREW BREW_NAME _LK_CACHE_NAMESPACE
        for i in "${!BREW_PATH[@]}"; do
            if ((!i)); then
                SH=$(_lk_macos_env '^/usr/local(/|$)')
            else
                SH=$(_lk_macos_env '^/opt/homebrew(/|$)')
                _LK_CACHE_NAMESPACE=x86_64
            fi && BREW=(
                env "PATH=$(eval "$SH" && echo "$PATH")"
                ${BREW_ARCH[i]:+arch "-${BREW_ARCH[i]}"}
                "${BREW_PATH[i]}"
            ) || return
            BREW_NAME=${BREW_NAMES[i]}
            "$@" || return
        done
    }

    function brew() {
        if [ "$BASH_SUBSHELL" -eq 0 ]; then
            lk_faketty caffeinate -d "${BREW[@]:-brew}" "$@"
        else
            command "${BREW[@]:-brew}" "$@"
        fi
    }

    function check_homebrew() {
        [ -z "${BREW_NEW[i]-}" ] || return 0
        HAVE_SUDO_ACCESS=0 \
            lk_brew_install_homebrew "${BREW_PATH[i]%/bin/brew}" ||
            lk_die "$BREW_NAME installation failed"
        BREW_NEW[i]=$LK_BREW_NEW_INSTALL
        lk_tty_print "Found $BREW_NAME at:" "$("${BREW_PATH[i]}" --prefix)"
        lk_brew_tap "${HOMEBREW_TAPS[@]}" ||
            lk_die "unable to tap formula repositories"
        lk_brew_enable_autoupdate ${BREW_ARCH[i]:+"${BREW_ARCH[i]}"} ||
            lk_die 'unable to enable automatic `brew update`'
        [ "$LK_BREW_NEW_INSTALL" -eq 1 ] || {
            lk_tty_print "Updating formulae"
            brew update --quiet &&
                lk_brew_flush_cache
        }
    }

    INSTALL=(
        coreutils
        diffutils
        findutils
        gawk
        gnu-getopt
        grep
        inetutils
        gnu-sed
        gnu-tar
        wget

        #
        bash-completion
        icdiff
        jq
        newt
        pv
        python-yq
        rsync
        trash
    )

    ! MACOS_VERSION=$(lk_macos_version) ||
        ! lk_version_at_least "$MACOS_VERSION" 10.15 ||
        INSTALL+=(mas)
    HOMEBREW_FORMULAE=($(lk_echo_array HOMEBREW_FORMULAE INSTALL | sort -u))

    BREW_NEW=()
    brew_loop check_homebrew
    INSTALL=($(comm -13 \
        <(lk_brew_list_formulae | sort -u) \
        <(lk_echo_array INSTALL | sort -u)))
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_tty_print "Installing lk-platform dependencies"
        brew install --formula "${INSTALL[@]}" &&
            lk_brew_flush_cache
    }

    FOREIGN=($(lk_brew_formulae_list_not_native "${HOMEBREW_FORMULAE[@]}"))
    if lk_is_apple_silicon && {
        [ -e /usr/local/bin/brew ] || { [ ${#FOREIGN[@]} -gt 0 ] &&
            lk_echo_array FOREIGN | lk_console_list \
                "Not supported on Apple Silicon:" formula formulae &&
            lk_confirm \
                "Install an Intel instance of Homebrew for the above?" Y; }
    }; then
        lk_macos_install_rosetta2
        BREW_PATH=(/opt/homebrew/bin/brew /usr/local/bin/brew)
        BREW_ARCH=("" x86_64)
        BREW_NAMES=("Homebrew (native)" "Homebrew (Intel)")
    elif [ ${#FOREIGN[@]} -gt 0 ]; then
        lk_console_warning "Skipping unsupported formulae"
        HOMEBREW_FORMULAE=($(comm -23 \
            <(lk_echo_array HOMEBREW_FORMULAE | sort -u) \
            <(lk_echo_array FOREIGN | sort -u)))
        FOREIGN=()
    fi

    brew_loop check_homebrew

    lk_tty_print "Applying user defaults"
    XQ='
.plist.dict.key |
    [ .[] |
        select(test("^seed-numNotifications-.*")) |
        sub("-numNotifications-"; "-viewed-") ] -
    [ .[] |
        select(test("^seed-viewed-.*")) ] | .[]'
    for DOMAIN in com.apple.touristd com.apple.tourist; do
        [ -e ~/Library/Preferences/"$DOMAIN.plist" ] || continue
        KEYS=$(plutil -convert xml1 -o - \
            ~/Library/Preferences/"$DOMAIN.plist" |
            xq -r "$XQ")
        if [ -n "$KEYS" ]; then
            lk_tty_detail "Disabling tour notifications in" "$DOMAIN"
            xargs -J % -n 1 \
                defaults write "$DOMAIN" % -date "$(date -uR)" <<<"$KEYS"
        fi
    done
    lk_macos_defaults_maybe_write 1 com.apple.Spotlight showedFTE -bool true
    lk_macos_defaults_maybe_write 1 com.apple.Spotlight showedLearnMore -bool true
    lk_macos_defaults_maybe_write 3 com.apple.Spotlight useCount -int 3

    # source ~/.bashrc in ~/.bash_profile, creating both files if necessary
    [ -s ~/.bashrc ] ||
        echo "# ~/.bashrc for interactive bash shells" >~/.bashrc
    [ -s ~/.bash_profile ] ||
        echo "# ~/.bash_profile for bash login shells" >~/.bash_profile
    if ! grep -q "\.bashrc" ~/.bash_profile; then
        _FILE=$(<~/.bash_profile)
        lk_file_replace ~/.bash_profile "$(echo "$_FILE" &&
            echo "[ ! -f ~/.bashrc ] || . ~/.bashrc")"
    fi

    LK_SUDO=1
    lk_console_blank
    LK_NO_LOG=1 \
        lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh"
    unset LK_SUDO

    lk_console_blank
    lk_tty_print "Checking Homebrew packages"
    UPGRADE_CASKS=()
    function check_updates() {
        local UPGRADE_FORMULAE
        [ "${BREW_NEW[i]}" -eq 0 ] || return 0
        [ "$i" -eq 0 ] || local OUTDATED
        OUTDATED=$(brew outdated --json=v2) &&
            UPGRADE_FORMULAE=($(jq -r \
                ".formulae[]|select(.pinned|not).name" <<<"$OUTDATED")) &&
            lk_mapfile "UPGRADE_FORMULAE_TEXT_$i" <(jq <<<"$OUTDATED" -r '
.formulae[] | select(.pinned | not) |
    .name + " (" + (.installed_versions | join(" ")) + " -> " +
        .current_version + ")"') || return
        eval "UPGRADE_FORMULAE_$i=(\${UPGRADE_FORMULAE[@]+\"\${UPGRADE_FORMULAE[@]}\"})"
    }
    brew_loop check_updates
    lk_mapfile UPGRADE_FORMULAE_TEXT \
        <(lk_echo_array "${!UPGRADE_FORMULAE_TEXT_@}" | sort -u)
    [ ${#UPGRADE_FORMULAE_TEXT[@]} -eq 0 ] || {
        lk_echo_array UPGRADE_FORMULAE_TEXT |
            lk_console_detail_list "$(
                lk_plural ${#UPGRADE_FORMULAE_TEXT[@]} Update Updates
            ) available:" formula formulae
        lk_confirm "OK to upgrade outdated formulae?" Y ||
            unset "${!UPGRADE_FORMULAE_@}"
    }

    if [ "${BREW_NEW[0]}" -eq 0 ]; then
        UPGRADE_CASKS=($(jq -r \
            ".casks[]|select(.pinned|not).name" <<<"$OUTDATED"))
        [ ${#UPGRADE_CASKS[@]} -eq 0 ] || {
            jq <<<"$OUTDATED" -r '
.casks[] | select(.pinned | not) |
    .name + " (" + .installed_versions + " -> " +
        .current_version + ")"' |
                lk_console_detail_list "$(
                    lk_plural ${#UPGRADE_CASKS[@]} Update Updates
                ) available:" cask casks
            lk_confirm "OK to upgrade outdated casks?" Y ||
                UPGRADE_CASKS=()
        }
    fi

    function get_arch_formulae() {
        local COUNT JQ='
def is_native:
    (.versions.bottle | not) or
        ([.bottle[].files | keys[] | select(match("^(all$|arm64_)"))] | length > 0);'
        # Exclude formulae with no arm64 bottle on Apple Silicon unless using
        # `arch -x86_64`
        if [ -z "${BREW_ARCH[i]}" ]; then
            HOMEBREW_FORMULAE=($(jq -r \
                "$JQ"'.formulae[]|select(is_native).full_name' \
                <<<"$HOMEBREW_FORMULAE_JSON" | grep -Ev "^$(lk_regex_implode \
                    ${HOMEBREW_FORCE_INTEL[@]+"${HOMEBREW_FORCE_INTEL[@]}"})\$")) || true
        else
            HOMEBREW_FORMULAE=($({ [ ${#HOMEBREW_FORCE_INTEL[@]} -eq 0 ] || jq -r \
                "$JQ"'.formulae[]|select(is_native).full_name' \
                <<<"$HOMEBREW_FORMULAE_JSON" | grep -E "^$(lk_regex_implode \
                    ${HOMEBREW_FORCE_INTEL[@]+"${HOMEBREW_FORCE_INTEL[@]}"})\$" || true; } &&
                jq -r \
                    "$JQ"'.formulae[]|select(is_native|not).full_name' \
                    <<<"$HOMEBREW_FORMULAE_JSON"))
        fi
        COUNT=${#HOMEBREW_FORMULAE[@]}
        ! lk_verbose || [ -z "${FORMULAE_COUNT-}" ] || lk_tty_detail \
            "$BREW_NAME formulae ($COUNT of $FORMULAE_COUNT):" \
            $'\n'"${HOMEBREW_FORMULAE[*]}"
    }
    function check_installed() {
        ! lk_is_apple_silicon || {
            local HOMEBREW_FORMULAE
            get_arch_formulae
        }
        lk_mapfile "INSTALL_FORMULAE_$i" <(comm -13 \
            <(lk_brew_list_formulae | sort -u) \
            <(lk_echo_array HOMEBREW_FORMULAE | sort -u))
    }
    function check_selected() {
        lk_mapfile "INSTALL_FORMULAE_$i" <(comm -12 \
            <(lk_echo_array "INSTALL_FORMULAE_$i" | sort -u) \
            <(lk_echo_array INSTALL_FORMULAE | sort -u))
    }
    # Resolve formulae to their full names, e.g. python -> python@3.8
    HOMEBREW_FORMULAE_JSON=$(lk_brew_info --formula --json=v2 \
        "${HOMEBREW_FORMULAE[@]}") && HOMEBREW_FORMULAE=($(jq -r \
            ".formulae[].full_name" <<<"$HOMEBREW_FORMULAE_JSON"))
    FORMULAE_COUNT=${#HOMEBREW_FORMULAE[@]}
    brew_loop check_installed
    unset FORMULAE_COUNT
    INSTALL_FORMULAE=($(lk_echo_array "${!INSTALL_FORMULAE_@}" | sort -u))
    if [ ${#INSTALL_FORMULAE[@]} -gt 0 ]; then
        FORMULAE=()
        for FORMULA in "${INSTALL_FORMULAE[@]}"; do
            FORMULA_DESC="$(jq <<<"$HOMEBREW_FORMULAE_JSON" -r \
                --arg formula "$FORMULA" '
.formulae[] | select(.full_name == $formula) |
    "\(.full_name)@\(.versions.stable): \(
        if .desc != null then ": " + .desc else "" end
    )"')"
            FORMULAE+=(
                "$FORMULA"
                "$FORMULA_DESC"
            )
        done
        if INSTALL_FORMULAE=($(lk_whiptail_checklist \
            "Installing new formulae" \
            "Selected Homebrew formulae will be installed:" \
            "${FORMULAE[@]}")) && [ ${#INSTALL_FORMULAE[@]} -gt 0 ]; then
            brew_loop check_selected
        else
            unset "${!INSTALL_FORMULAE@}"
        fi
    fi

    INSTALL_CASKS=($(comm -13 \
        <(lk_brew_list_casks | sort -u) \
        <(lk_echo_array HOMEBREW_CASKS |
            sort -u)))
    if [ ${#INSTALL_CASKS[@]} -gt 0 ]; then
        HOMEBREW_CASKS_JSON=$(lk_brew_info --cask --json=v2 "${INSTALL_CASKS[@]}")
        CASKS=()
        for CASK in "${INSTALL_CASKS[@]}"; do
            CASK_DESC="$(jq <<<"$HOMEBREW_CASKS_JSON" -r \
                --arg cask "${CASK##*/}" '
.casks[] | select(.token == $cask) |
    "\(.name[0]//.token) \(.version)\(
        if .desc != null then ": " + .desc else "" end
    )"')"
            CASKS+=(
                "$CASK"
                "$CASK_DESC"
            )
        done
        INSTALL_CASKS=($(lk_whiptail_checklist \
            "Installing new casks" \
            "Selected Homebrew casks will be installed:" \
            "${CASKS[@]}")) && [ ${#INSTALL_CASKS[@]} -gt 0 ] ||
            INSTALL_CASKS=()
    fi

    INSTALL_APPS=()
    UPGRADE_APPS=()
    if [ ${#MAS_APPS[@]} -gt "0" ] && lk_command_exists mas; then
        lk_tty_print "Checking Mac App Store apps"
        while ! lk_version_at_least "$MACOS_VERSION" 12.0 &&
            ! APPLE_ID=$(mas account 2>/dev/null); do
            APPLE_ID=
            lk_tty_detail "\
Unable to retrieve Apple ID
Please open the Mac App Store and sign in"
            lk_confirm "Try again?" Y || break
        done

        if lk_version_at_least "$MACOS_VERSION" 12.0 ||
            [ -n "$APPLE_ID" ]; then
            lk_tty_detail "Apple ID:" "${APPLE_ID:-<unknown>}"

            OUTDATED=$(mas outdated)
            if UPGRADE_APPS=($(grep -Eo '^[0-9]+' <<<"$OUTDATED")); then
                sed -E "s/^[0-9]+$S+(.*$NS)$S+\(/\1 (/" <<<"$OUTDATED" |
                    lk_console_detail_list "$(
                        lk_plural ${#UPGRADE_APPS[@]} Update Updates
                    ) available:" app apps
                lk_confirm "OK to upgrade outdated apps?" Y ||
                    UPGRADE_APPS=()
            fi

            INSTALL_APPS=($(comm -13 \
                <(mas list | grep -Eo '^[0-9]+' | sort -u) \
                <(lk_echo_array MAS_APPS | sort -u)))
            PROG='
NR == 1       { printf "%s=%s\n", "APP_NAME", gensub(/(.*) [0-9]+(\.[0-9]+)*( \[[0-9]+\.[0-9]+\])?$/, "\\1", "g")
                printf "%s=%s\n", "APP_VER" , gensub(/.* ([0-9]+(\.[0-9]+)*)( \[[0-9]+\.[0-9]+\])?$/, "\\1", "g") }
/^Size: /     { printf "%s=%s\n", "APP_SIZE", gensub(/^Size: /, "", "g")     }
/^Released: / { printf "%s=%s\n", "APP_DATE", gensub(/^Released: /, "", "g") }'
            APPS=()
            APP_NAMES=()
            for i in "${!INSTALL_APPS[@]}"; do
                APP_ID=${INSTALL_APPS[i]}
                if APP_SH=$(
                    mas info "$APP_ID" 2>/dev/null |
                        gnu_awk "$PROG"
                ); then
                    APP_SH=$(while IFS='=' read -r KEY VALUE; do
                        printf '%s=%q\n' "$KEY" "$VALUE"
                    done <<<"$APP_SH")
                    eval "$APP_SH"
                    APPS+=(
                        "$APP_ID"
                        "$APP_NAME ($APP_SIZE, Version $APP_VER, $APP_DATE)"
                    )
                    APP_NAMES+=("$APP_NAME")
                    continue
                fi
                lk_console_warning "Unknown App ID:" "$APP_ID"
                unset "INSTALL_APPS[i]"
            done
            if [ ${#INSTALL_APPS[@]} -gt 0 ]; then
                APP_IDS=("${INSTALL_APPS[@]}")
                if INSTALL_APPS=($(lk_whiptail_checklist \
                    "Installing new apps" \
                    "Selected apps will be installed from the Mac App Store:" \
                    "${APPS[@]}")) && [ ${#INSTALL_APPS[@]} -gt 0 ]; then
                    for i in "${!APP_IDS[@]}"; do
                        lk_in_array "${APP_IDS[i]}" INSTALL_APPS ||
                            unset "APP_NAMES[i]"
                    done
                else
                    INSTALL_APPS=()
                fi
            fi
        fi
    fi

    lk_mapfile INSTALL_UPDATES <(lk_macos_update_list_available |
        awk -F'\t' '{
    print $1
    print $2 " (" $4 ($6 ? ", Action: " $6 : "") ", Version: " $3 ")"
    print $5 == "Y" ? "on" : "off"
}')
    if [ ${#INSTALL_UPDATES[@]} -gt 0 ]; then
        lk_mapfile INSTALL_UPDATES <(lk_whiptail_checklist -s \
            "Installing system software updates" \
            "Selected updates will be installed:" \
            "${INSTALL_UPDATES[@]}")
    fi

    function commit_changes() {
        local _ARR="$2_${i}[@]" ARR
        ARR=(${!_ARR+"${!_ARR}"})
        [ ${#ARR[@]} -eq 0 ] || {
            local s='{}' MESSAGE
            MESSAGE=${3//"$s"/$BREW_NAME}
            lk_echo_array ARR |
                lk_console_list "$MESSAGE" formula formulae
            brew "$1" --formula "${ARR[@]}" &&
                lk_brew_flush_cache || STATUS=$?
        }
    }
    brew_loop commit_changes upgrade UPGRADE_FORMULAE \
        "Upgrading {} formulae:"
    brew_loop commit_changes install INSTALL_FORMULAE \
        "Installing new {} formulae:"

    [ ${#UPGRADE_CASKS[@]} -eq 0 ] || {
        lk_tty_print "Upgrading casks"
        brew upgrade --cask "${UPGRADE_CASKS[@]}" &&
            lk_brew_flush_cache || STATUS=$?
    }

    [ ${#INSTALL_CASKS[@]} -eq 0 ] || {
        lk_echo_array INSTALL_CASKS |
            lk_console_list "Installing new casks:"
        brew install --cask "${INSTALL_CASKS[@]}" &&
            lk_brew_flush_cache || STATUS=$?
    }

    [ ${#UPGRADE_APPS[@]} -eq 0 ] || {
        lk_tty_print "Upgrading apps"
        lk_faketty caffeinate -d \
            mas upgrade "${UPGRADE_APPS[@]}" || STATUS=$?
    }

    [ ${#INSTALL_APPS[@]} -eq 0 ] || {
        lk_echo_array APP_NAMES |
            lk_console_list "Installing new apps:"
        lk_faketty caffeinate -d \
            mas install "${INSTALL_APPS[@]}" || STATUS=$?
    }

    [ ${#INSTALL_UPDATES[@]} -eq 0 ] || {
        lk_echo_array INSTALL_UPDATES |
            lk_console_list "Installing system software updates:"
        lk_faketty caffeinate -d \
            sudo softwareupdate --no-scan \
            --install "${INSTALL_UPDATES[@]}" --restart || STATUS=$?
    }

    lk_macos_xcode_maybe_accept_license

    # `brew deps` is buggy AF, so find dependencies recursively via `brew info`
    lk_tty_print "Checking for orphaned packages"
    function check_orphans() {
        local ALL_FORMULAE LAST_FORMULAE NEW_JSON LAST_CASKS \
            NEW_FORMULAE NEW_CASKS PURGE_FORMULAE j=0
        ! lk_is_apple_silicon || {
            local HOMEBREW_FORMULAE
            get_arch_formulae
        }
        lk_mktemp_with ALL_FORMULAE comm -12 \
            <(lk_brew_list_formulae | sort -u) \
            <(lk_echo_array HOMEBREW_FORMULAE HOMEBREW_KEEP_FORMULAE | sort -u) &&
            lk_mktemp_with LAST_FORMULAE &&
            lk_mktemp_with NEW_JSON
        ((i > 0)) || {
            lk_mktemp_with ALL_CASKS comm -12 \
                <(lk_brew_list_casks | sort -u) \
                <(lk_echo_array HOMEBREW_CASKS HOMEBREW_KEEP_CASKS | sort -u) &&
                lk_mktemp_with LAST_CASKS || return
        }
        while :; do
            ((++j))
            lk_mktemp_with -r NEW_FORMULAE \
                comm -23 "$ALL_FORMULAE" "$LAST_FORMULAE" || return
            ! lk_verbose || [ ! -s "$NEW_FORMULAE" ] ||
                lk_tty_detail \
                    "$BREW_NAME formulae dependencies (iteration #$j):" \
                    $'\n'"$(tr '\n' ' ' <"$NEW_FORMULAE")"
            ((i > 0)) || {
                lk_mktemp_with -r NEW_CASKS \
                    comm -23 "$ALL_CASKS" "$LAST_CASKS" || return
                ! lk_verbose || [ ! -s "$NEW_CASKS" ] ||
                    lk_tty_detail \
                        "$BREW_NAME cask dependencies (iteration #$j):" \
                        $'\n'"$(tr '\n' ' ' <"$NEW_CASKS")"
            }
            [ -s "$NEW_FORMULAE" ] || [ -s "$NEW_CASKS" ] || break
            cp "$ALL_FORMULAE" "$LAST_FORMULAE" || return
            ((i > 0)) ||
                cp "$ALL_CASKS" "$LAST_CASKS" || return
            {
                [ ! -s "$NEW_FORMULAE" ] ||
                    lk_brew_info --json=v2 --installed |
                    jq '{ "casks": [], "formulae": [.formulae[] |
  select(.full_name | IN($ARGS.positional[]))] }' --args $(<"$NEW_FORMULAE") ||
                    return
                ((i > 0)) || [ ! -s "$NEW_CASKS" ] ||
                    lk_brew_info --json=v2 --installed |
                    jq '{ "formulae": [], "casks": [.casks[] |
  select(.token | IN($ARGS.positional[]))] }' --args $(<"$NEW_CASKS")
            } | jq --slurp '{ "formulae": [ .[].formulae[] ],
  "casks": [ .[].casks[] ] }' >"$NEW_JSON" || return
            { cat "$LAST_FORMULAE" && jq -r \
                ".formulae[].dependencies[]?,.casks[].depends_on.formula[]?" \
                <"$NEW_JSON"; } | sort -u >"$ALL_FORMULAE" || return
            ((i > 0)) || { cat "$LAST_CASKS" && jq -r \
                ".casks[].depends_on.cask[]?" <"$NEW_JSON"; } |
                sort -u >"$ALL_CASKS" || return
        done

        lk_mktemp_with PURGE_FORMULAE comm -23 \
            <(lk_brew_list_formulae | sort -u) \
            "$ALL_FORMULAE" || return
        [ ! -s "$PURGE_FORMULAE" ] || {
            lk_tty_list - \
                "Installed by $BREW_NAME but no longer required:" \
                formula formulae <"$PURGE_FORMULAE" || return
            ! lk_confirm "Remove the above?" N || {
                brew uninstall --formula \
                    --force --ignore-dependencies $(<"$PURGE_FORMULAE") &&
                    lk_brew_flush_cache
            }
        }
    }
    brew_loop check_orphans

    lk_mktemp_with PURGE_CASKS comm -23 \
        <(lk_brew_list_casks | sort -u) \
        "$ALL_CASKS"
    [ ! -s "$PURGE_CASKS" ] || {
        lk_tty_list - \
            "Installed but no longer required:" cask casks <"$PURGE_CASKS"
        ! lk_confirm "Remove the above?" N || {
            brew uninstall --cask $(<"$PURGE_CASKS") &&
                lk_brew_flush_cache
        }
    }

    function check_unlinked() {
        local UNLINK
        lk_mktemp_with UNLINK
        lk_brew_info --json=v2 --installed | jq -r '
.formulae[] | select((.full_name | IN($ARGS.positional[])) and
  .linked_keg != null).full_name' \
            --args "${HOMEBREW_UNLINK_FORMULAE[@]}" >"$UNLINK" || return
        [ ! -s "$UNLINK" ] || {
            lk_run_detail brew unlink $(<"$UNLINK") &&
                lk_brew_flush_cache
        }
    }
    [ -z "${HOMEBREW_UNLINK_FORMULAE+1}" ] || {
        lk_tty_print "Unlinking packages"
        brew_loop check_unlinked
    }

    function check_linked() {
        local LINK
        lk_mktemp_with LINK
        lk_brew_info --json=v2 --installed | jq -r '
.formulae[] | select((.full_name | IN($ARGS.positional[])) and
  .linked_keg == null).full_name' \
            --args "${HOMEBREW_LINK_KEGS[@]}" >"$LINK" || return
        [ ! -s "$LINK" ] || {
            lk_run_detail brew link $(<"$LINK") &&
                lk_brew_flush_cache
        }
    }
    [ -z "${HOMEBREW_LINK_KEGS+1}" ] || {
        lk_tty_print "Unlinking packages"
        brew_loop check_linked
    }

    lk_remove_missing LOGIN_ITEMS
    if [ ${#LOGIN_ITEMS[@]} -gt 0 ]; then
        lk_tty_print "Checking Login Items for user '$USER'"
        lk_mapfile LOGIN_ITEMS <(comm -13 \
            <("$LK_BASE/lib/macos/login-items-list.js" | tail -n+2 |
                cut -f2 | sort -u) \
            <(lk_echo_array LOGIN_ITEMS | sort -u))
        [ ${#LOGIN_ITEMS[@]} -eq 0 ] || {
            ! { lk_whiptail_build_list \
                LOGIN_ITEMS 's/^.*\///;s/\.app$//' "${LOGIN_ITEMS[@]}" &&
                lk_mapfile LOGIN_ITEMS <(lk_whiptail_checklist \
                    "Adding Login Items for user '$USER'" \
                    "Selected items will open automatically when you log in:" \
                    "${LOGIN_ITEMS[@]}"); } ||
                [ ${#LOGIN_ITEMS[@]} -eq 0 ] || {
                lk_echo_array LOGIN_ITEMS |
                    lk_console_list "Adding to Login Items:" app apps
                "$LK_BASE/lib/macos/login-items-add.js" "${LOGIN_ITEMS[@]}"
            }
        }
    fi

    if [ "$STATUS" -eq 0 ]; then
        lk_console_success "Provisioning complete"
    else
        lk_console_error "Provisioning completed with errors"
        (exit "$STATUS") || lk_die ""
    fi
}

#!/bin/bash

# shellcheck disable=SC2031,SC2153

LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}
export LK_BASE=${LK_BASE:-/opt/lk-platform}

set -euo pipefail
lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (exit $s) && false || exit; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[[ $OSTYPE == darwin* ]] || lk_die "not running on macOS"
[[ $- != *s* ]] || lk_die "cannot run from standard input"

function exit_trap() {
    local _LOG_FILE=$_LK_LOG_FILE LOG_FILE
    if lk_log_close &&
        LOG_FILE=$(lk_log_create) &&
        [ "$LOG_FILE" != "$_LOG_FILE" ]; then
        lk_console_log "Moving:" "$_LOG_FILE -> $LOG_FILE"
        cat "$_LOG_FILE" >>"$LOG_FILE" &&
            rm "$_LOG_FILE" ||
            lk_console_warning \
                "Error moving provisioning log entries to" "$LOG_FILE"
    fi
}

{
    export SUDO_PROMPT="[sudo] password for %p: "

    CURL_OPTIONS=(
        --fail
        --header "Cache-Control: no-cache"
        --location
        --retry 8
        --show-error
        --silent
    )

    _DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$_DIR"

    EXIT_STATUS=0

    SH=$([ ! -f /etc/default/lk-platform ] || { . /etc/default/lk-platform &&
        declare -p LK_PACKAGES_FILE; } 2>/dev/null) &&
        eval "$SH"
    LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE:-}}
    PACKAGES_REL=
    if [ -n "$LK_PACKAGES_FILE" ]; then
        if [ ! -f "$LK_PACKAGES_FILE" ]; then
            FILE=${LK_PACKAGES_FILE##*/}
            FILE=${FILE#packages-macos-}
            FILE=${FILE%.sh}
            FILE=$LK_BASE/share/packages/macos/$FILE.sh
            [ -f "$FILE" ] || PACKAGES_REL=${FILE#$LK_BASE/}
            LK_PACKAGES_FILE=$FILE
        fi
        export LK_PACKAGES_FILE
    fi

    if [ -f "$LK_BASE/lib/bash/include/core.sh" ]; then
        . "$LK_BASE/lib/bash/include/core.sh"
        lk_include macos provision whiptail
        SUDOERS=$(cat "$LK_BASE/share/sudoers.d/default")
        ${PACKAGES_REL:+. "$LK_BASE/$PACKAGES_REL"}
    else
        echo $'\E[1m\E[36m==> \E[0m\E[1mChecking prerequisites\E[0m' >&2
        REPO_URL=https://raw.githubusercontent.com/lkrms/lk-platform
        for FILE_PATH in \
            ${PACKAGES_REL:+"/$PACKAGES_REL"} \
            /lib/bash/include/core.sh \
            /lib/bash/include/macos.sh \
            /lib/bash/include/provision.sh \
            /lib/bash/include/whiptail.sh \
            /share/sudoers.d/default; do
            FILE=$_DIR/${FILE_PATH##*/}
            URL=$REPO_URL/$LK_PLATFORM_BRANCH$FILE_PATH
            MESSAGE=$'\E[1m\E[33m   -> \E[0m{}\E[0m\E[33m '"$URL"$'\E[0m'
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
        SUDOERS=$(cat "$_DIR/default")
    fi

    LK_FILE_TAKE_BACKUP=${LK_FILE_TAKE_BACKUP-1}

    lk_log_output ~/"${LK_PATH_PREFIX}install.log"
    trap exit_trap EXIT

    lk_console_log "Provisioning macOS"

    LK_DEFAULTS_DIR=~/.${LK_PATH_PREFIX}defaults/00000000000000
    if [ ! -e "$LK_DEFAULTS_DIR" ]; then
        lk_console_item "Dumping user defaults to domain files in" \
            ~/".${LK_PATH_PREFIX}defaults"
        lk_macos_defaults_dump
    fi

    # This doubles as an early Full Disk Access check/reminder
    STATUS=$(sudo systemsetup -getremotelogin)
    if [[ ! "$STATUS" =~ ${S}On$ ]]; then
        lk_console_message "Enabling Remote Login (SSH)"
        lk_run_detail sudo systemsetup -setremotelogin on
    fi

    STATUS=$(sudo systemsetup -getcomputersleep)
    if [[ ! "$STATUS" =~ ${S}Never$ ]]; then
        lk_console_message "Disabling computer sleep"
        lk_run_detail sudo systemsetup -setcomputersleep off
    fi

    lk_sudo_offer_nopasswd || true

    scutil --get HostName &>/dev/null ||
        [ -z "${LK_NODE_HOSTNAME:=$(
            lk_console_read "Hostname for this system:"
        )}" ] ||
        lk_macos_set_hostname "$LK_NODE_HOSTNAME"

    CURRENT_SHELL=$(dscl . -read ~/ UserShell | sed 's/^UserShell: //')
    if [ "$CURRENT_SHELL" != /bin/bash ]; then
        lk_console_item "Setting default shell for user '$USER' to:" /bin/bash
        sudo chsh -s /bin/bash "$USER"
    fi

    lk_console_message "Configuring sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default
    sudo test ! -e "${FILE}s" || sudo test -e "$FILE" ||
        sudo mv -v "${FILE}s" "$FILE"
    sudo test -e "$FILE" ||
        sudo install -m 00440 /dev/null "$FILE"
    LK_SUDO=1 lk_file_replace "$FILE" "$SUDOERS"

    lk_console_message "Configuring default umask"
    if ! USER_UMASK=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist \
        Umask 2>/dev/null) ||
        [ "$USER_UMASK" -ne 2 ]; then
        lk_run_detail sudo launchctl config user umask 002 >/dev/null
    fi
    FILE=/etc/profile
    if [ -r "$FILE" ] && ! grep -q umask "$FILE"; then
        lk_console_detail "Setting umask in" "$FILE"
        LK_SUDO=1 lk_file_keep_original "$FILE"
        sudo tee -a "$FILE" <<"EOF" >/dev/null

if [ "$(id -u)" -ne 0 ]; then
    umask 002
else
    umask 022
fi
EOF
    fi
    umask 002

    function path_add() {
        local EXIT_STATUS
        while [ $# -gt 0 ]; do
            [[ :$_PATH: == *:$1:* ]] || {
                _PATH=$1:${_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
                EXIT_STATUS=1
            }
            shift
        done
        return "${EXIT_STATUS:-0}"
    }
    PATH_ADD=(/usr/local/bin)
    BREW_CMD=(brew)
    BREW_ARCH=("")
    if lk_is_apple_silicon; then
        [ -f /Library/Apple/System/Library/LaunchDaemons/com.apple.oahd.plist ] || {
            lk_console_message "Installing Rosetta 2"
            lk_run_detail sudo \
                softwareupdate --install-rosetta --agree-to-license
        }
        PATH_ADD+=(/opt/homebrew/bin)
        BREW_CMD=(/opt/homebrew/bin/brew /usr/local/bin/brew)
        BREW_ARCH=("" x86_64)
    fi
    lk_mapfile BREW_NAMES <(lk_echo_array BREW_ARCH |
        sed -Ee 's/.+/Homebrew (&)/' -e 's/^$/Homebrew/')
    lk_console_message "Configuring default PATH"
    _PATH=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist \
        PathEnvironmentVariable 2>/dev/null) || _PATH=
    path_add "${PATH_ADD[@]}" ||
        lk_run_detail sudo launchctl config user path "$_PATH" >/dev/null
    _PATH=$PATH
    path_add "${PATH_ADD[@]}" ||
        PATH=$_PATH

    # disable sleep when charging
    sudo pmset -c sleep 0

    # always restart on power loss
    sudo pmset -a autorestart 1

    lk_macos_xcode_maybe_accept_license
    lk_macos_install_command_line_tools

    # If Xcode and the standalone Command Line Tools package are both installed,
    # switch to Xcode or commands like opendiff won't work
    if [ -e /Applications/Xcode.app ]; then
        TOOLS_PATH=$(lk_macos_command_line_tools_path)
        if [[ "$TOOLS_PATH" != /Applications/Xcode.app* ]]; then
            lk_console_message "Configuring Xcode"
            lk_console_detail \
                "Switching from command line tools to Xcode with:" \
                "xcode-select --switch /Applications/Xcode.app"
            sudo xcode-select --switch /Applications/Xcode.app
            OLD_TOOLS_PATH=$TOOLS_PATH
            TOOLS_PATH=$(lk_macos_command_line_tools_path)
            lk_console_detail "Development tools directory:" \
                "$OLD_TOOLS_PATH -> $LK_BOLD$TOOLS_PATH$LK_RESET"
        fi
    fi

    if [ ! -e "$LK_BASE" ] || [ -z "$(ls -A "$LK_BASE")" ]; then
        lk_console_item "Installing lk-platform to" "$LK_BASE"
        sudo install -d -m 02775 -o "$USER" -g admin "$LK_BASE"
        lk_tty caffeinate -i git clone -b "$LK_PLATFORM_BRANCH" \
            https://github.com/lkrms/lk-platform.git "$LK_BASE"
        lk_file_keep_original /etc/default/lk-platform
        [ -e /etc/default ] ||
            sudo install -d -m 00755 -g wheel /etc/default
        sudo install -m 00664 -g admin /dev/null /etc/default/lk-platform
        lk_get_shell_var \
            LK_BASE \
            LK_PATH_PREFIX \
            LK_PLATFORM_BRANCH \
            LK_PACKAGES_FILE |
            sudo tee /etc/default/lk-platform >/dev/null
        lk_console_detail_file /etc/default/lk-platform
    fi

    [ -z "$LK_PACKAGES_FILE" ] ||
        . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/macos/packages.sh"

    function lk_brew_loop() {
        local BREW_PATH BREW BREW_NAME
        for i in "${!BREW_CMD[@]}"; do
            BREW_PATH=${BREW_CMD[$i]}
            BREW=(${BREW_ARCH[$i]:+arch "--${BREW_ARCH[$i]}"} "$BREW_PATH")
            BREW_NAME=${BREW_NAMES[$i]}
            "$@" || return
        done
    }

    function brew() {
        command "${BREW[@]:-brew}" "$@"
    }

    function lk_brew() {
        lk_tty caffeinate -i "${BREW[@]:-brew}" "$@"
    }

    function lk_brew_check_taps() {
        local TAP
        TAP=($(comm -13 \
            <(brew tap | sort -u) \
            <(lk_echo_array HOMEBREW_TAPS | sort -u)))
        [ ${#TAP[@]} -eq 0 ] || {
            for TAP in "${TAP[@]}"; do
                lk_console_detail "Tapping" "$TAP"
                lk_brew tap --quiet "$TAP" || return
            done
        }
    }

    function lk_brew_formulae() {
        brew list --formula --full-name
    }

    function lk_brew_casks() {
        brew list --cask --full-name
    }

    function install_homebrew() {
        local FILE URL
        BREW_NEW[$i]=0
        if ! lk_command_exists "$BREW_PATH"; then
            lk_console_message "Installing $BREW_NAME"
            FILE=$_DIR/homebrew-install.sh
            URL=https://raw.githubusercontent.com/Homebrew/install/master/install.sh
            if [ ! -e "$FILE" ]; then
                curl --retry 8 --fail --output "$FILE" "$URL" || {
                    rm -f "$FILE"
                    lk_die "unable to download: $URL"
                }
            fi
            CI=1 lk_tty caffeinate -i \
                ${BREW_ARCH[$i]:+arch "--${BREW_ARCH[$i]}"} bash "$FILE" ||
                lk_die "$BREW_NAME installer failed"
            lk_command_exists "$BREW_PATH" || lk_die "command not found: $BREW_PATH"
            BREW_NEW[$i]=1
        fi
        lk_console_item "Found $BREW_NAME at:" "$("$BREW_PATH" --prefix)"
        ((i)) || {
            SH=$(. "$LK_BASE/lib/bash/env.sh") &&
                eval "$SH"
        }
        lk_brew_check_taps
        [ "${BREW_NEW[$i]}" -eq 1 ] || {
            lk_console_detail "Updating formulae"
            lk_brew update --quiet
        }
    }
    BREW_NEW=()
    lk_brew_loop install_homebrew

    INSTALL=(
        coreutils  # GNU utilities
        diffutils  #
        findutils  #
        gawk       #
        gnu-getopt #
        grep       #
        inetutils  #
        gnu-sed    #
        gnu-tar    #
        wget       #
        jq         # for parsing `brew info` output
        newt       # for `whiptail`
        python-yq  # for plist parsing with `xq`
    )
    ! MACOS_VERSION=$(lk_macos_version) ||
        ! lk_version_at_least "$MACOS_VERSION" 10.15 ||
        INSTALL+=(
            mas # for managing Mac App Store apps
        )
    HOMEBREW_FORMULAE=($(lk_echo_array HOMEBREW_FORMULAE INSTALL | sort -u))
    INSTALL=($(comm -13 \
        <(lk_brew_formulae | sort -u) \
        <(lk_echo_array INSTALL | sort -u)))
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_console_message "Installing lk-platform dependencies"
        lk_brew install --formula "${INSTALL[@]}"
    }

    lk_console_message "Applying user defaults"
    XQ="\
.plist.dict.key |
    [ .[] |
        select(test(\"^seed-numNotifications-.*\")) |
        sub(\"-numNotifications-\"; \"-viewed-\") ] -
    [ .[] |
        select(test(\"^seed-viewed-.*\")) ] | .[]"
    for DOMAIN in com.apple.touristd com.apple.tourist; do
        [ -e ~/Library/Preferences/"$DOMAIN.plist" ] || continue
        KEYS=$(plutil -convert xml1 -o - \
            ~/Library/Preferences/"$DOMAIN.plist" |
            xq -r "$XQ")
        if [ -n "$KEYS" ]; then
            lk_console_detail "Disabling tour notifications in" "$DOMAIN"
            xargs -J % -n 1 \
                defaults write "$DOMAIN" % -date "$(date -uR)" <<<"$KEYS"
        fi
    done
    lk_macos_defaults_maybe_write 1 com.apple.Spotlight showedFTE -bool true
    lk_macos_defaults_maybe_write 3 com.apple.Spotlight useCount -int 3

    # source ~/.bashrc in ~/.bash_profile, creating both files if necessary
    [ -f ~/.bashrc ] ||
        echo "# ~/.bashrc for interactive bash shells" >~/.bashrc
    [ -f ~/.bash_profile ] ||
        echo "# ~/.bash_profile for bash login shells" >~/.bash_profile
    if ! grep -q "\.bashrc" ~/.bash_profile; then
        lk_file_add_newline ~/.bash_profile
        echo "[ ! -f ~/.bashrc ] || . ~/.bashrc" >>~/.bash_profile
    fi

    lk_console_blank
    LK_SUDO=1 lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh" --no-log \
        ${LK_PACKAGES_FILE:+--set LK_PACKAGES_FILE="$LK_PACKAGES_FILE"}

    lk_console_blank
    lk_console_message "Checking Homebrew packages"
    UPGRADE_CASKS=()
    function check_updates() {
        local UPGRADE_FORMULAE
        [ "${BREW_NEW[$i]}" -eq 0 ] || return 0
        [ "$i" -eq 0 ] || local OUTDATED
        OUTDATED=$(brew outdated --json=v2) &&
            UPGRADE_FORMULAE=($(jq -r ".formulae[].name" <<<"$OUTDATED")) &&
            lk_mapfile "UPGRADE_FORMULAE_TEXT_$i" <(jq <<<"$OUTDATED" -r "\
.formulae[] |
    .name + \" (\" + (.installed_versions | join(\" \")) + \" -> \" +
        .current_version + \")\"") || return
        eval "UPGRADE_FORMULAE_$i=(\${UPGRADE_FORMULAE[@]+\"\${UPGRADE_FORMULAE[@]}\"})"
    }
    lk_brew_loop check_updates
    lk_mapfile UPGRADE_FORMULAE_TEXT \
        <(lk_echo_array "${!UPGRADE_FORMULAE_TEXT_@}" | sort -u)
    [ ${#UPGRADE_FORMULAE_TEXT[@]} -eq 0 ] || {
        lk_echo_array UPGRADE_FORMULAE_TEXT |
            lk_console_detail_list "$(
                lk_maybe_plural ${#UPGRADE_FORMULAE_TEXT[@]} Update Updates
            ) available:" formula formulae
        lk_confirm "OK to upgrade outdated formulae?" Y ||
            unset "${!UPGRADE_FORMULAE_@}"
    }

    if [ "${BREW_NEW[0]}" -eq 0 ]; then
        UPGRADE_CASKS=($(jq -r ".casks[].name" <<<"$OUTDATED"))
        [ ${#UPGRADE_CASKS[@]} -eq 0 ] || {
            jq <<<"$OUTDATED" -r "\
.casks[] |
    .name + \" (\" + .installed_versions + \" -> \" +
        .current_version + \")\"" |
                lk_console_detail_list "$(
                    lk_maybe_plural ${#UPGRADE_CASKS[@]} Update Updates
                ) available:" cask casks
            lk_confirm "OK to upgrade outdated casks?" Y ||
                UPGRADE_CASKS=()
        }
    fi

    function get_arch_formulae() {
        local JQ="\
def is_native:
    (.versions.bottle | not) or 
        ([.bottle[].files | keys[] | select(match(\"^arm64_\"))] | length > 0);"
        # Exclude formulae with no arm64 bottle on Apple Silicon unless
        # using `arch --x86_64`
        if [ -z "${BREW_ARCH[$i]}" ]; then
            HOMEBREW_FORMULAE=($(jq -r \
                "$JQ"'.formulae[]|select(is_native).full_name' \
                <<<"$HOMEBREW_FORMULAE_JSON" | grep -Ev "^$(lk_regex_implode \
                    ${FORCE_IBREW[@]+"${FORCE_IBREW[@]}"})\$")) || true
        else
            HOMEBREW_FORMULAE=($({ [ ${#FORCE_IBREW[@]} -eq 0 ] || jq -r \
                "$JQ"'.formulae[]|select(is_native).full_name' \
                <<<"$HOMEBREW_FORMULAE_JSON" | grep -E "^$(lk_regex_implode \
                    ${FORCE_IBREW[@]+"${FORCE_IBREW[@]}"})\$" || true; } &&
                jq -r \
                    "$JQ"'.formulae[]|select(is_native|not).full_name' \
                    <<<"$HOMEBREW_FORMULAE_JSON"))
        fi
    }
    function check_installed() {
        ! lk_is_apple_silicon || {
            local HOMEBREW_FORMULAE
            get_arch_formulae
        }
        lk_mapfile "INSTALL_FORMULAE_$i" <(comm -13 \
            <(lk_brew_formulae | sort -u) \
            <(lk_echo_array HOMEBREW_FORMULAE | sort -u))
    }
    function check_selected() {
        lk_mapfile "INSTALL_FORMULAE_$i" <(comm -12 \
            <(lk_echo_array "INSTALL_FORMULAE_$i" | sort -u) \
            <(lk_echo_array INSTALL_FORMULAE | sort -u))
    }
    # Resolve formulae to their full names, e.g. python -> python@3.8
    HOMEBREW_FORMULAE_JSON=$(brew info --formula --json=v2 \
        "${HOMEBREW_FORMULAE[@]}") && HOMEBREW_FORMULAE=($(jq -r \
            ".formulae[].full_name" <<<"$HOMEBREW_FORMULAE_JSON"))
    lk_brew_loop check_installed
    INSTALL_FORMULAE=($(lk_echo_array "${!INSTALL_FORMULAE_@}" | sort -u))
    if [ ${#INSTALL_FORMULAE[@]} -gt 0 ]; then
        FORMULAE=()
        for FORMULA in "${INSTALL_FORMULAE[@]}"; do
            FORMULA_DESC="$(jq <<<"$HOMEBREW_FORMULAE_JSON" -r \
                --arg formula "$FORMULA" "\
.formulae[] | select(.full_name == \$formula) |
    \"\\(.full_name)@\\(.versions.stable): \\(
        if .desc != null then \": \" + .desc else \"\" end
    )\"")"
            FORMULAE+=(
                "$FORMULA"
                "$FORMULA_DESC"
            )
        done
        if INSTALL_FORMULAE=($(lk_log_bypass_stderr lk_whiptail_checklist \
            "Installing new formulae" \
            "Selected Homebrew formulae will be installed:" \
            "${FORMULAE[@]}")) && [ ${#INSTALL_FORMULAE[@]} -gt 0 ]; then
            lk_brew_loop check_selected
        else
            unset "${!INSTALL_FORMULAE@}"
        fi
    fi

    INSTALL_CASKS=($(comm -13 \
        <(lk_brew_casks | sort -u) \
        <(lk_echo_array HOMEBREW_CASKS |
            sort -u)))
    if [ ${#INSTALL_CASKS[@]} -gt 0 ]; then
        HOMEBREW_CASKS_JSON=$(brew info --cask --json=v2 "${INSTALL_CASKS[@]}")
        CASKS=()
        for CASK in "${INSTALL_CASKS[@]}"; do
            CASK_DESC="$(jq <<<"$HOMEBREW_CASKS_JSON" -r \
                --arg cask "${CASK##*/}" "\
.casks[] | select(.token == \$cask) |
    \"\\(.name[0]//.token) \\(.version)\\(
        if .desc != null then \": \" + .desc else \"\" end
    )\"")"
            CASKS+=(
                "$CASK"
                "$CASK_DESC"
            )
        done
        INSTALL_CASKS=($(lk_log_bypass_stderr lk_whiptail_checklist \
            "Installing new casks" \
            "Selected Homebrew casks will be installed:" \
            "${CASKS[@]}")) && [ ${#INSTALL_CASKS[@]} -gt 0 ] ||
            INSTALL_CASKS=()
    fi

    INSTALL_APPS=()
    UPGRADE_APPS=()
    if [ ${#MAS_APPS[@]} -gt "0" ] && lk_command_exists mas; then
        lk_console_message "Checking Mac App Store apps"
        while ! APPLE_ID=$(mas account 2>/dev/null); do
            APPLE_ID=
            lk_console_detail "\
Unable to retrieve Apple ID
Please open the Mac App Store and sign in"
            lk_confirm "Try again?" Y || break
        done

        if [ -n "$APPLE_ID" ]; then
            lk_console_detail "Apple ID:" "$APPLE_ID"

            # `mas outdated` and `mas upgrade` stopped working after Mojave
            if MACOS_VERSION=$(lk_macos_version) &&
                lk_version_at_least 10.14 "$MACOS_VERSION"; then
                OUTDATED=$(mas outdated)
                if UPGRADE_APPS=($(grep -Eo '^[0-9]+' <<<"$OUTDATED")); then
                    sed -E "s/^[0-9]+$S*//" <<<"$OUTDATED" |
                        lk_console_detail_list "$(
                            lk_maybe_plural ${#UPGRADE_APPS[@]} Update Updates
                        ) available:" app apps
                    lk_confirm "OK to upgrade outdated apps?" Y ||
                        UPGRADE_APPS=()
                fi
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
                APP_ID=${INSTALL_APPS[$i]}
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
                unset "INSTALL_APPS[$i]"
            done
            if [ ${#INSTALL_APPS[@]} -gt 0 ]; then
                APP_IDS=("${INSTALL_APPS[@]}")
                if INSTALL_APPS=($(lk_log_bypass_stderr lk_whiptail_checklist \
                    "Installing new apps" \
                    "Selected apps will be installed from the Mac App Store:" \
                    "${APPS[@]}")) && [ ${#INSTALL_APPS[@]} -gt 0 ]; then
                    for i in "${!APP_IDS[@]}"; do
                        lk_in_array "${APP_IDS[$i]}" INSTALL_APPS ||
                            unset "APP_NAMES[$i]"
                    done
                else
                    INSTALL_APPS=()
                fi
            fi
        fi
    fi

    function commit_changes() {
        local _ARR="$2_${i}[@]" ARR
        ARR=(${!_ARR+"${!_ARR}"})
        [ ${#ARR[@]} -eq 0 ] || {
            local s='{}' MESSAGE
            MESSAGE=${3//"$s"/$BREW_NAME}
            lk_echo_array ARR |
                lk_console_list "$MESSAGE" formula formulae
            lk_brew "$1" --formula "${ARR[@]}" || EXIT_STATUS=$?
        }
    }
    lk_brew_loop commit_changes upgrade UPGRADE_FORMULAE \
        "Upgrading {} formulae:"
    lk_brew_loop commit_changes install INSTALL_FORMULAE \
        "Installing new {} formulae:"

    [ ${#UPGRADE_CASKS[@]} -eq 0 ] || {
        lk_console_message "Upgrading casks"
        lk_brew upgrade --cask "${UPGRADE_CASKS[@]}" || EXIT_STATUS=$?
    }

    [ ${#INSTALL_CASKS[@]} -eq 0 ] || {
        lk_echo_array INSTALL_CASKS |
            lk_console_list "Installing new casks:"
        lk_brew install --cask "${INSTALL_CASKS[@]}" || EXIT_STATUS=$?
    }

    [ ${#UPGRADE_APPS[@]} -eq 0 ] || {
        lk_console_message "Upgrading apps"
        lk_tty caffeinate -i \
            mas upgrade "${UPGRADE_APPS[@]}" || EXIT_STATUS=$?
    }

    [ ${#INSTALL_APPS[@]} -eq 0 ] || {
        lk_echo_array APP_NAMES |
            lk_console_list "Installing new apps:"
        lk_tty caffeinate -i \
            mas install "${INSTALL_APPS[@]}" || EXIT_STATUS=$?
    }

    lk_macos_xcode_maybe_accept_license

    # `brew deps` is buggy AF, so find dependencies recursively via `brew info`
    lk_console_message "Checking for orphaned packages"
    function check_orphans() {
        local ALL_FORMULAE PURGE_FORMULAE \
            LAST_FORMULAE=() NEW_FORMULAE=() LAST_CASKS=() NEW_CASKS=()
        ! lk_is_apple_silicon || {
            local HOMEBREW_FORMULAE
            get_arch_formulae
        }
        ALL_FORMULAE=($(comm -12 \
            <(lk_brew_formulae | sort -u) \
            <(lk_echo_array HOMEBREW_FORMULAE HOMEBREW_KEEP_FORMULAE | sort -u)))
        [ "$i" -gt 0 ] ||
            ALL_CASKS=($(comm -12 \
                <(lk_brew_casks | sort -u) \
                <(lk_echo_array HOMEBREW_CASKS HOMEBREW_KEEP_CASKS | sort -u)))
        while :; do
            NEW_FORMULAE=($(comm -23 \
                <(lk_echo_array ALL_FORMULAE) \
                <(lk_echo_array LAST_FORMULAE)))
            [ "$i" -gt 0 ] ||
                NEW_CASKS=($(comm -23 \
                    <(lk_echo_array ALL_CASKS) \
                    <(lk_echo_array LAST_CASKS)))
            [ ${#NEW_FORMULAE[@]}+${#NEW_CASKS[@]} != 0+0 ] || break
            LAST_FORMULAE=(${ALL_FORMULAE[@]+"${ALL_FORMULAE[@]}"})
            [ "$i" -gt 0 ] ||
                LAST_CASKS=(${ALL_CASKS[@]+"${ALL_CASKS[@]}"})
            NEW_JSON=$({
                [ ${#NEW_FORMULAE[@]} -eq 0 ] ||
                    brew info --json=v2 --formula "${NEW_FORMULAE[@]}"
                [ "$i" -gt 0 ] || [ ${#NEW_CASKS[@]} -eq 0 ] ||
                    brew info --json=v2 --cask "${NEW_CASKS[@]}"
            } | jq --slurp '{"formulae":[.[].formulae[]],"casks":[.[].casks[]]}')
            ALL_FORMULAE=($({ lk_echo_array ALL_FORMULAE && jq -r "\
.formulae[].dependencies[]?,\
.casks[].depends_on.formula[]?" <<<"$NEW_JSON"; } | sort -u))
            [ "$i" -gt 0 ] ||
                ALL_CASKS=($({ lk_echo_array ALL_CASKS && jq -r "\
.casks[].depends_on.cask[]?" <<<"$NEW_JSON"; } | sort -u))
        done

        PURGE_FORMULAE=($(comm -23 \
            <(lk_brew_formulae | sort -u) \
            <(lk_echo_array ALL_FORMULAE)))
        [ ${#PURGE_FORMULAE[@]} -eq 0 ] || {
            lk_echo_array PURGE_FORMULAE |
                lk_console_list \
                    "Installed by $BREW_NAME but no longer required:" \
                    formula formulae
            ! lk_confirm "Remove the above?" N ||
                brew uninstall --formula \
                    --force --ignore-dependencies "${PURGE_FORMULAE[@]}"
        }
    }
    lk_brew_loop check_orphans

    PURGE_CASKS=($(comm -23 \
        <(lk_brew_casks | sort -u) \
        <(lk_echo_array ALL_CASKS)))
    [ ${#PURGE_CASKS[@]} -eq 0 ] || {
        lk_echo_array PURGE_CASKS |
            lk_console_list "Installed but no longer required:" cask casks
        ! lk_confirm "Remove the above?" N ||
            brew uninstall --cask "${PURGE_CASKS[@]}"
    }

    lk_remove_missing LOGIN_ITEMS
    lk_mapfile ADD_LOGIN_ITEMS <(comm -13 \
        <("$LK_BASE/lib/macos/login-items-list.js" | tail -n+2 |
            cut -f2 | sort -u) \
        <(lk_echo_array LOGIN_ITEMS | sort -u))
    [ ${#ADD_LOGIN_ITEMS[@]} -eq 0 ] || {
        lk_echo_array ADD_LOGIN_ITEMS |
            lk_console_list "Adding to Login Items:" app apps
        "$LK_BASE/lib/macos/login-items-add.js" "${ADD_LOGIN_ITEMS[@]}"
    }

    lk_console_success "Provisioning complete"

    exit "$EXIT_STATUS"
}

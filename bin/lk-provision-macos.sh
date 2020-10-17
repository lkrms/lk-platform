#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2034,SC2207

LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(
    sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
)}"
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}
export LK_BASE=${LK_BASE:-/opt/${LK_PATH_PREFIX}platform}

set -euo pipefail
lk_die() { s=$? && echo "${0##*/}: $1" >&2 && (return $s) && false || exit; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[ "$(uname -s)" = Darwin ] || lk_die "not running on macOS"

function exit_trap() {
    local LOG_PATH
    if lk_log_close &&
        LOG_PATH=$(lk_log_create_file) &&
        [ "$LOG_PATH" != "$LK_LOG_FILE" ]; then
        lk_console_log "Moving:" "$LK_LOG_FILE -> $LOG_PATH"
        cat "$LK_LOG_FILE" >>"$LOG_PATH" &&
            rm "$LK_LOG_FILE" ||
            lk_console_warning0 \
                "Error moving provisioning log entries to" "$LOG_PATH"
    fi
}

{
    export SUDO_PROMPT="[sudo] password for %p: "

    S="[[:blank:]]"

    SCRIPT_DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$SCRIPT_DIR"

    export LK_PACKAGES_FILE=${1:-}
    if [ -n "$LK_PACKAGES_FILE" ]; then
        if [ -f "$LK_PACKAGES_FILE" ]; then
            . "$LK_PACKAGES_FILE"
        else
            case "$LK_PACKAGES_FILE" in
            $LK_BASE/*/*)
                CONTRIB_PACKAGES_FILE=${LK_PACKAGES_FILE:${#LK_BASE}}
                ;;
            /*/*)
                CONTRIB_PACKAGES_FILE=${LK_PACKAGES_FILE:1}
                ;;
            */*)
                CONTRIB_PACKAGES_FILE=$LK_PACKAGES_FILE
                ;;
            *)
                lk_die "$1: file not found"
                ;;
            esac
            LK_PACKAGES_FILE=$LK_BASE/$CONTRIB_PACKAGES_FILE
        fi
    fi

    if [ -f "$LK_BASE/lib/bash/include/core.sh" ]; then
        . "$LK_BASE/lib/bash/include/core.sh"
        lk_include provision macos
        SUDOERS=$(cat "$LK_BASE/share/sudoers.d/default")
        ${CONTRIB_PACKAGES_FILE:+. "$LK_BASE/$CONTRIB_PACKAGES_FILE"}
    else
        echo "Downloading dependencies to: $SCRIPT_DIR" >&2
        for FILE_PATH in \
            ${CONTRIB_PACKAGES_FILE:+"/$CONTRIB_PACKAGES_FILE"} \
            /lib/bash/include/core.sh \
            /lib/bash/include/provision.sh \
            /lib/bash/include/macos.sh \
            /share/sudoers.d/default; do
            FILE=$SCRIPT_DIR/${FILE_PATH##*/}
            URL=https://raw.githubusercontent.com/lkrms/lk-platform/$LK_PLATFORM_BRANCH$FILE_PATH
            curl --retry 8 --fail --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download from GitHub: $URL"
            }
            [ "${FILE: -3}" != .sh ] ||
                . "$FILE"
        done
        SUDOERS=$(cat "$SCRIPT_DIR/default")
    fi

    LK_BACKUP_SUFFIX=-$(lk_timestamp).bak

    LK_LOG_FILE_MODE=0600 \
        lk_log_output ~/"${LK_PATH_PREFIX}install.log"
    trap exit_trap EXIT

    lk_console_log "Provisioning macOS"

    LK_DEFAULTS_DIR=~/.${LK_PATH_PREFIX}defaults/00000000000000
    if [ ! -e "$LK_DEFAULTS_DIR" ]; then
        lk_console_item "Dumping user defaults to domain files in" \
            ~/".${LK_PATH_PREFIX}defaults"
        lk_macos_defaults_dump
        lk_macos_defaults_dump -currentHost
    fi

    # This doubles as an early Full Disk Access check/reminder
    STATUS=$(sudo systemsetup -getremotelogin)
    if [[ ! "$STATUS" =~ ${S}On$ ]]; then
        lk_console_message "Enabling Remote Login (SSH)"
        lk_console_detail "Running:" "systemsetup -setremotelogin on"
        sudo systemsetup -setremotelogin on
    fi

    STATUS=$(sudo systemsetup -getcomputersleep)
    if [[ ! "$STATUS" =~ ${S}Never$ ]]; then
        lk_console_message "Disabling computer sleep"
        lk_console_detail "Running:" "systemsetup -setcomputersleep off"
        sudo systemsetup -setcomputersleep off
    fi

    lk_sudo_offer_nopasswd || true

    scutil --get HostName >/dev/null 2>&1 ||
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
        sudo install -m 0440 /dev/null "$FILE"
    LK_SUDO=1 lk_maybe_replace "$FILE" "$SUDOERS"

    if ! USER_UMASK=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist Umask 2>/dev/null) ||
        [ "$USER_UMASK" -ne 2 ]; then
        lk_console_message "Setting default umask"
        lk_console_detail "Running:" "launchctl config user umask 002"
        sudo launchctl config user umask 002 >/dev/null
    fi
    umask 002

    if ! USER_PATH=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist \
        PathEnvironmentVariable 2>/dev/null) ||
        [[ ! "$USER_PATH" =~ (:|^)/usr/local/bin(:|$) ]]; then
        USER_PATH=/usr/local/bin:${USER_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
        lk_console_message "Setting default PATH"
        lk_console_detail "Running:" "launchctl config user path $USER_PATH"
        sudo launchctl config user path "$USER_PATH" >/dev/null
    fi

    # disable sleep when charging
    sudo pmset -c sleep 0

    # always restart on power loss
    sudo pmset -a autorestart 1

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
        lk_console_item "Installing lk-platform to:" "$LK_BASE"
        sudo install -d -m 2775 -o "$USER" -g admin "$LK_BASE"
        lk_keep_trying lk_tty caffeinate -i \
            git clone -b "$LK_PLATFORM_BRANCH" \
            https://github.com/lkrms/lk-platform.git "$LK_BASE"
        lk_keep_original /etc/default/lk-platform
        [ -e /etc/default ] ||
            sudo install -d -m 0755 -g wheel /etc/default
        sudo install -m 0664 -g admin /dev/null /etc/default/lk-platform
        lk_get_shell_var \
            LK_BASE \
            LK_PATH_PREFIX \
            LK_PATH_PREFIX_ALPHA \
            LK_PLATFORM_BRANCH \
            LK_PACKAGES_FILE |
            sudo tee /etc/default/lk-platform >/dev/null
        lk_console_detail_file /etc/default/lk-platform
    fi

    [ -n "$LK_PACKAGES_FILE" ] ||
        [ ! -f /etc/default/lk-platform ] || . /etc/default/lk-platform
    [ -z "$LK_PACKAGES_FILE" ] || . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/macos/packages.sh"

    function lk_brew_check_taps() {
        local TAP
        TAP=($(comm -13 \
            <(brew tap | sort | uniq) \
            <(lk_echo_array HOMEBREW_TAPS | sort | uniq)))
        [ ${#TAP[@]} -eq 0 ] || {
            for TAP in "${TAP[@]}"; do
                lk_console_detail "Tapping" "$TAP"
                lk_keep_trying lk_tty caffeinate -i brew tap --quiet "$TAP" ||
                    return
            done
        }
    }

    function lk_brew_formulae() {
        brew list --formulae --full-name
    }

    function lk_brew_casks() {
        brew list --casks --full-name
    }

    NEW_HOMEBREW=0
    if ! lk_command_exists brew; then
        lk_console_message "Installing Homebrew"
        FILE=$SCRIPT_DIR/homebrew-install.sh
        URL=https://raw.githubusercontent.com/Homebrew/install/master/install.sh
        if [ ! -e "$FILE" ]; then
            curl --retry 8 --fail --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download: $URL"
            }
        fi
        CI=1 lk_keep_trying lk_tty caffeinate -i bash "$FILE" ||
            lk_die "Homebrew installer failed"
        eval "$(. "$LK_BASE/lib/bash/env.sh")"
        lk_command_exists brew || lk_die "command not found: brew"
        lk_console_item "Found Homebrew at:" "$(brew --prefix)"
        lk_brew_check_taps
        NEW_HOMEBREW=1
    else
        lk_console_item "Found Homebrew at:" "$(brew --prefix)"
        eval "$(. "$LK_BASE/lib/bash/env.sh")"
        lk_brew_check_taps
        lk_console_detail "Updating formulae"
        lk_keep_trying lk_tty caffeinate -i brew update --quiet
    fi

    INSTALL=(
        coreutils  # GNU utilities
        diffutils  #
        findutils  #
        gawk       #
        gnu-getopt #
        grep       #
        inetutils  #
        netcat     #
        gnu-sed    #
        gnu-tar    #
        wget       #
        jq         # for parsing `brew info` output
        mas        # for managing Mac App Store apps
        newt       # for `whiptail`
        python-yq  # for plist parsing with `xq`
    )
    INSTALL=($(comm -13 \
        <(lk_brew_formulae | sort | uniq) \
        <(lk_echo_array INSTALL | sort | uniq)))
    [ ${#INSTALL[@]} -eq 0 ] || {
        lk_console_message "Installing lk-platform dependencies"
        lk_keep_trying lk_tty caffeinate -i brew install "${INSTALL[@]}"
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
        lk_maybe_add_newline ~/.bash_profile
        echo "[ ! -f ~/.bashrc ] || . ~/.bashrc" >>~/.bash_profile
    fi

    [ -z "$LK_PACKAGES_FILE" ] ||
        LK_PACKAGES_FILE=$(realpath "$LK_PACKAGES_FILE")
    "$LK_BASE/bin/lk-platform-configure-system.sh" --no-log

    lk_console_message "Checking Homebrew packages"
    UPGRADE_FORMULAE=()
    UPGRADE_CASKS=()
    lk_is_true "$NEW_HOMEBREW" || {
        OUTDATED=$(brew outdated --json=v2)
        UPGRADE_FORMULAE=($(jq -r ".formulae[].name" <<<"$OUTDATED"))
        [ ${#UPGRADE_FORMULAE[@]} -eq 0 ] || {
            jq <<<"$OUTDATED" -r "\
.formulae[] |
    .name + \" (\" + (.installed_versions | join(\" \")) + \" -> \" +
        .current_version + \")\"" |
                lk_console_detail_list "$(
                    lk_maybe_plural ${#UPGRADE_FORMULAE[@]} Update Updates
                ) available:" formula formulae
            lk_confirm "OK to upgrade outdated formulae?" Y ||
                UPGRADE_FORMULAE=()
        }

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
    }

    # Resolve formulae to their full names, e.g. python -> python@3.8
    [ ${#HOMEBREW_FORMULAE[@]} -eq 0 ] || {
        HOMEBREW_FORMULAE_JSON=$(lk_keep_trying caffeinate -i \
            brew info --json=v1 "${HOMEBREW_FORMULAE[@]}") &&
            HOMEBREW_FORMULAE=(
                $(jq -r .[].full_name <<<"$HOMEBREW_FORMULAE_JSON")
            )
    }

    INSTALL_FORMULAE=($(comm -13 \
        <(lk_brew_formulae | sort | uniq) \
        <(lk_echo_array HOMEBREW_FORMULAE | sort | uniq)))
    if [ ${#INSTALL_FORMULAE[@]} -gt 0 ]; then
        FORMULAE=()
        for FORMULA in "${INSTALL_FORMULAE[@]}"; do
            FORMULA_DESC="$(jq <<<"$HOMEBREW_FORMULAE_JSON" -r \
                --arg formula "$FORMULA" "\
.[] | select(.full_name == \$formula) |
    \"\\(.full_name)@\\(.versions.stable): \\(
        if .desc != null then \": \" + .desc else \"\" end
    )\"")"
            FORMULAE+=(
                "$FORMULA"
                "$FORMULA_DESC"
            )
        done
        INSTALL_FORMULAE=($(lk_log_bypass lk_console_checklist \
            "Installing new formulae" \
            "Selected Homebrew formulae will be installed:" \
            "${FORMULAE[@]}")) && [ ${#INSTALL_FORMULAE[@]} -gt 0 ] ||
            INSTALL_FORMULAE=()
    fi

    INSTALL_CASKS=($(comm -13 \
        <(lk_brew_casks | sort | uniq) \
        <(lk_echo_array HOMEBREW_CASKS |
            sort | uniq)))
    if [ ${#INSTALL_CASKS[@]} -gt 0 ]; then
        HOMEBREW_CASKS_JSON=$(lk_keep_trying caffeinate -i \
            brew cask info --json=v1 "${INSTALL_CASKS[@]}")
        CASKS=()
        for CASK in "${INSTALL_CASKS[@]}"; do
            CASK_DESC="$(jq <<<"$HOMEBREW_CASKS_JSON" -r \
                --arg cask "${CASK##*/}" "\
.[] | select(.token == \$cask) |
    \"\\(.name[0]//.token) \\(.version)\\(
        if .desc != null then \": \" + .desc else \"\" end
    )\"")"
            CASKS+=(
                "$CASK"
                "$CASK_DESC"
            )
        done
        INSTALL_CASKS=($(lk_log_bypass lk_console_checklist \
            "Installing new casks" \
            "Selected Homebrew casks will be installed:" \
            "${CASKS[@]}")) && [ ${#INSTALL_CASKS[@]} -gt 0 ] ||
            INSTALL_CASKS=()
    fi

    INSTALL_APPS=()
    UPGRADE_APPS=()
    if [ ${#MAS_APPS[@]} -gt "0" ]; then
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

            OUTDATED=$(mas outdated)
            if UPGRADE_APPS=($(grep -Eo '^[0-9]+' <<<"$OUTDATED")); then
                sed -E "s/^[0-9]+$S*//" <<<"$OUTDATED" |
                    lk_console_detail_list "$(
                        lk_maybe_plural ${#UPGRADE_APPS[@]} Update Updates
                    ) available:" app apps
                lk_confirm "OK to upgrade outdated apps?" Y ||
                    UPGRADE_APPS=()
            fi

            INSTALL_APPS=($(comm -13 \
                <(mas list | grep -Eo '^[0-9]+' | sort | uniq) \
                <(lk_echo_array MAS_APPS | sort | uniq)))
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
                lk_console_warning0 "Unknown App ID:" "$APP_ID"
                unset "INSTALL_APPS[$i]"
            done
            if [ ${#INSTALL_APPS[@]} -gt 0 ]; then
                APP_IDS=("${INSTALL_APPS[@]}")
                if INSTALL_APPS=($(lk_log_bypass lk_console_checklist \
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

    [ ${#UPGRADE_FORMULAE[@]} -eq 0 ] || {
        lk_console_message "Upgrading formulae"
        lk_keep_trying lk_tty caffeinate -i \
            brew upgrade "${UPGRADE_FORMULAE[@]}" --formula
    }

    [ ${#UPGRADE_CASKS[@]} -eq 0 ] || {
        lk_console_message "Upgrading casks"
        lk_keep_trying lk_tty caffeinate -i \
            brew upgrade "${UPGRADE_CASKS[@]}" --cask
    }

    [ ${#INSTALL_FORMULAE[@]} -eq 0 ] || {
        lk_echo_array INSTALL_FORMULAE |
            lk_console_list "Installing new formulae:"
        lk_keep_trying lk_tty caffeinate -i \
            brew install "${INSTALL_FORMULAE[@]}"
    }

    [ ${#INSTALL_CASKS[@]} -eq 0 ] || {
        lk_echo_array INSTALL_CASKS |
            lk_console_list "Installing new casks:"
        lk_keep_trying lk_tty caffeinate -i \
            brew cask install "${INSTALL_CASKS[@]}"
    }

    [ ${#UPGRADE_APPS[@]} -eq 0 ] || {
        lk_console_message "Upgrading apps"
        lk_tty caffeinate -i \
            mas upgrade "${UPGRADE_APPS[@]}"
    }

    [ ${#INSTALL_APPS[@]} -eq 0 ] || {
        lk_echo_array APP_NAMES |
            lk_console_list "Installing new apps:"
        lk_tty caffeinate -i \
            mas install "${INSTALL_APPS[@]}"
    }

    if [ -e /Applications/Xcode.app ] &&
        ! xcodebuild -license check >/dev/null 2>&1; then
        lk_console_message "Accepting Xcode license"
        lk_console_detail "Running:" "xcodebuild -license accept"
        sudo xcodebuild -license accept
    fi

    INSTALLED_FORMULAE=($(comm -12 \
        <(lk_brew_formulae | sort | uniq) \
        <(lk_echo_array HOMEBREW_FORMULAE | sort | uniq)))
    INSTALLED_CASKS=($(comm -12 \
        <(lk_brew_casks | sort | uniq) \
        <(lk_echo_array HOMEBREW_CASKS | sort | uniq)))
    INSTALLED_CASKS_JSON=$(
        [ ${#INSTALLED_CASKS[@]} -eq 0 ] ||
            lk_keep_trying caffeinate -i \
                brew cask info --json=v1 "${INSTALLED_CASKS[@]}"
    )

    ALL_FORMULAE=($({
        lk_echo_array INSTALLED_FORMULAE &&
            { [ -z "$INSTALLED_CASKS_JSON" ] ||
                jq -r '.[].depends_on.formula[]?' \
                    <<<"$INSTALLED_CASKS_JSON"; } &&
            { [ ${#INSTALLED_FORMULAE[@]} -eq 0 ] ||
                brew deps --union --full-name \
                    "${INSTALLED_FORMULAE[@]}" 2>/dev/null; }
    } | sort | uniq))
    ALL_CASKS=($({
        lk_echo_array INSTALLED_CASKS &&
            { [ -z "$INSTALLED_CASKS_JSON" ] ||
                # TODO: recurse?
                jq -r '.[].depends_on.cask[]?' <<<"$INSTALLED_CASKS_JSON"; }
    } | sort | uniq))

    PURGE_FORMULAE=($(comm -23 \
        <(lk_brew_formulae | sort | uniq) \
        <(lk_echo_array ALL_FORMULAE)))
    [ ${#PURGE_FORMULAE[@]} -eq 0 ] || {
        lk_echo_array PURGE_FORMULAE |
            lk_console_list "Installed but no longer required:" formula formulae
        ! lk_confirm "Remove the above?" Y ||
            brew uninstall "${PURGE_FORMULAE[@]}"
    }

    PURGE_CASKS=($(comm -23 \
        <(lk_brew_casks | sort | uniq) \
        <(lk_echo_array ALL_CASKS)))
    [ ${#PURGE_CASKS[@]} -eq 0 ] || {
        lk_echo_array PURGE_CASKS |
            lk_console_list "Installed but no longer required:" cask casks
        ! lk_confirm "Remove the above?" Y ||
            brew cask uninstall "${PURGE_CASKS[@]}"
    }

    lk_console_success "Provisioning complete"

    exit
}

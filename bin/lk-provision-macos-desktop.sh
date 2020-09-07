#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2034,SC2207

export LK_BASE=${LK_BASE:-/opt/lk-platform}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PATH_PREFIX_ALPHA="${LK_PATH_PREFIX_ALPHA:-$(
    sed 's/[^a-zA-Z0-9]//g' <<<"$LK_PATH_PREFIX"
)}"
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

set -euo pipefail
lk_die() { s=$? && echo "${BASH_SOURCE[0]:+${BASH_SOURCE[0]}: }$1" >&2 && (return $s) && false || exit; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[ "$(uname -s)" = Darwin ] || lk_die "not running on macOS"

{
    export SUDO_PROMPT="[sudo] password for %p: "

    S="[[:space:]]"

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

    if [ -f "$LK_BASE/lib/bash/core.sh" ]; then
        . "$LK_BASE/lib/bash/core.sh"
        lk_include provision macos
        ${CONTRIB_PACKAGES_FILE:+. "$LK_BASE/$CONTRIB_PACKAGES_FILE"}
    else
        echo "Downloading dependencies to: $SCRIPT_DIR" >&2
        for FILE_PATH in \
            ${CONTRIB_PACKAGES_FILE:+"/$CONTRIB_PACKAGES_FILE"} \
            /lib/bash/core.sh \
            /lib/bash/provision.sh \
            /lib/bash/macos.sh; do
            FILE=$SCRIPT_DIR/${FILE_PATH##*/}
            URL=https://raw.githubusercontent.com/lkrms/lk-platform/$LK_PLATFORM_BRANCH$FILE_PATH
            curl --fail --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download from GitHub: $URL"
            }
            . "$FILE"
        done
    fi

    LK_BACKUP_SUFFIX=-$(lk_timestamp).bak

    LK_LOG_FILE_MODE=0600 \
        lk_log_output ~/"${LK_PATH_PREFIX}install.log"

    lk_console_message "Provisioning macOS"

    lk_sudo_offer_nopasswd || true

    scutil --get HostName >/dev/null 2>/dev/null ||
        [ -z "${LK_NODE_HOSTNAME:=$(lk_console_read "Hostname for this system? ")}" ] ||
        lk_macos_set_hostname "$LK_NODE_HOSTNAME"

    CURRENT_SHELL=$(dscl . -read ~/ UserShell | sed 's/^UserShell: //')
    if [ "$CURRENT_SHELL" != /bin/bash ]; then
        lk_console_item "Setting default shell for user '$USER' to:" /bin/bash
        sudo chsh -s /bin/bash "$USER"
    fi

    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}defaults
    if ! sudo test -e "$FILE"; then
        lk_console_message "Configuring sudo"
        sudo install -m 0440 /dev/null "$FILE"
        cat <<EOF | sudo tee "$FILE" >/dev/null
Defaults umask = 0022
Defaults umask_override
EOF
        LK_SUDO=1 lk_console_detail_file "$FILE"
    fi

    if ! USER_UMASK=$(defaults read \
        /var/db/com.apple.xpc.launchd/config/user.plist Umask 2>/dev/null) ||
        [ "$USER_UMASK" -ne 2 ]; then
        lk_console_message "Setting default umask"
        lk_console_detail "Running:" "launchctl config user umask 002"
        sudo launchctl config user umask 002 >/dev/null
    fi
    umask 002

    STATUS=$(sudo systemsetup -getremotelogin)
    if [[ ! "$STATUS" =~ ${S}On$ ]]; then
        lk_console_message "Enabling Remote Login (SSH)"
        sudo systemsetup -setremotelogin on
    fi

    STATUS=$(sudo systemsetup -getcomputersleep)
    if [[ ! "$STATUS" =~ ${S}Never$ ]]; then
        lk_console_message "Disabling computer sleep"
        sudo systemsetup -setcomputersleep off
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
            lk_console_detail "Switching from command line tools to Xcode with:" \
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
        lk_tty git clone -b "$LK_PLATFORM_BRANCH" \
            https://github.com/lkrms/lk-platform.git "$LK_BASE"
        lk_keep_original /etc/default/lk-platform
        [ -e /etc/default ] ||
            sudo install -d -m 0755 -g wheel /etc/default
        sudo install -m 0664 -g admin /dev/null /etc/default/lk-platform
        printf '%s=%q\n' \
            LK_BASE "$LK_BASE" \
            LK_PATH_PREFIX "$LK_PATH_PREFIX" \
            LK_PATH_PREFIX_ALPHA "$LK_PATH_PREFIX_ALPHA" \
            LK_PLATFORM_BRANCH "$LK_PLATFORM_BRANCH" \
            LK_PACKAGES_FILE "$LK_PACKAGES_FILE" |
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
        [ "${#TAP[@]}" -eq 0 ] || {
            for TAP in "${TAP[@]}"; do
                lk_console_detail "Tapping" "$TAP"
                lk_tty brew tap --quiet "$TAP" || return
            done
        }
    }

    NEW_HOMEBREW=0
    if ! lk_command_exists brew; then
        lk_console_message "Installing Homebrew"
        FILE=$SCRIPT_DIR/homebrew-install.sh
        URL=https://raw.githubusercontent.com/Homebrew/install/master/install.sh
        if [ ! -e "$FILE" ]; then
            curl --fail --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download: $URL"
            }
        fi
        CI=1 lk_tty bash "$FILE" || lk_die "Homebrew installer failed"
        eval "$(. "$LK_BASE/lib/bash/env.sh")"
        lk_command_exists brew || lk_die "brew: command not found"
        lk_console_item "Found Homebrew at:" "$(brew --prefix)"
        lk_brew_check_taps
        INSTALL=(
            # for lk_install_gnu_commands
            coreutils
            findutils
            gawk
            grep
            inetutils
            netcat
            gnu-sed
            gnu-tar
            wget

            # for `brew info` parsing
            jq
        )
        lk_console_detail "Installing lk-platform dependencies"
        lk_tty brew install "${INSTALL[@]}"
        NEW_HOMEBREW=1
    else
        lk_console_item "Found Homebrew at:" "$(brew --prefix)"
        eval "$(. "$LK_BASE/lib/bash/env.sh")"
        lk_brew_check_taps
        lk_console_detail "Updating formulae"
        lk_tty brew update --quiet
    fi

    # source ~/.bashrc in ~/.bash_profile, creating both files if necessary
    [ -f ~/.bashrc ] ||
        echo "# ~/.bashrc for interactive bash shells" >~/.bashrc
    [ -f ~/.bash_profile ] ||
        echo "# ~/.bash_profile for bash login shells" >~/.bash_profile
    if ! grep -q "\.bashrc" ~/.bash_profile; then
        lk_maybe_add_newline ~/.bash_profile
        echo "[ ! -f ~/.bashrc ] || . ~/.bashrc" >>~/.bash_profile
    fi

    [ -z "$LK_PACKAGES_FILE" ] || LK_PACKAGES_FILE=$(realpath "$LK_PACKAGES_FILE")
    "$LK_BASE/bin/lk-platform-install.sh" --no-log

    lk_console_message "Checking Homebrew packages"
    UPGRADE_FORMULAE=()
    UPGRADE_CASKS=()
    lk_is_true "$NEW_HOMEBREW" || {
        OUTDATED=$(brew outdated --json=v2)
        UPGRADE_FORMULAE=($(jq -r ".formulae[].name" <<<"$OUTDATED"))
        [ "${#UPGRADE_FORMULAE[@]}" -eq 0 ] || {
            jq <<<"$OUTDATED" -r "\
.formulae[] | \
.name + \" (\" + (.installed_versions | join(\" \")) + \" -> \" \
+ .current_version + \")\"" |
                lk_console_detail_list "$(
                    lk_maybe_plural "${#UPGRADE_FORMULAE[@]}" Update Updates
                ) available:" formula formulae
            lk_no_input || lk_confirm "OK to upgrade outdated formulae?" Y ||
                UPGRADE_FORMULAE=()
        }

        UPGRADE_CASKS=($(jq -r ".casks[].name" <<<"$OUTDATED"))
        [ "${#UPGRADE_CASKS[@]}" -eq 0 ] || {
            jq <<<"$OUTDATED" -r "\
.casks[] | \
.name + \" (\" + .installed_versions + \" -> \" + .current_version + \")\"" |
                lk_console_detail_list "$(
                    lk_maybe_plural "${#UPGRADE_CASKS[@]}" Update Updates
                ) available:" cask casks
            lk_no_input || lk_confirm "OK to upgrade outdated casks?" Y ||
                UPGRADE_CASKS=()
        }
    }

    [ "${#UPGRADE_FORMULAE[@]}" -eq 0 ] || {
        lk_console_message "Upgrading formulae"
        lk_tty brew upgrade "${UPGRADE_FORMULAE[@]}" --formula
    }

    [ "${#UPGRADE_CASKS[@]}" -eq 0 ] || {
        lk_console_message "Upgrading casks"
        lk_tty brew upgrade "${UPGRADE_CASKS[@]}" --cask
    }

    [ "${#HOMEBREW_FORMULAE[@]}" -eq 0 ] ||
        HOMEBREW_FORMULAE=($(
            brew info --json=v1 "${HOMEBREW_FORMULAE[@]}" |
                jq -r .[].full_name
        ))

    INSTALL_FORMULAE=($(comm -13 \
        <(brew list --formulae --full-name | sort | uniq) \
        <(lk_echo_array HOMEBREW_FORMULAE |
            sort | uniq)))
    [ "${#INSTALL_FORMULAE[@]}" -eq 0 ] || {
        lk_echo_array INSTALL_FORMULAE |
            lk_console_list "Installing new formulae:"
        lk_tty brew install "${INSTALL_FORMULAE[@]}"
    }

    if ! brew list --formulae --full-name | grep -Fx bash >/dev/null; then
        lk_console_message "Installing Bash keg-only"
        brew install bash &&
            brew unlink bash
    fi

    INSTALL_CASKS=($(comm -13 \
        <(brew list --casks --full-name | sort | uniq) \
        <(lk_echo_array HOMEBREW_CASKS |
            sort | uniq)))
    [ "${#INSTALL_CASKS[@]}" -eq 0 ] || {
        lk_echo_array INSTALL_CASKS |
            lk_console_list "Installing new casks:"
        lk_tty brew cask install "${INSTALL_CASKS[@]}"
    }

    # TODO:
    # - mas account
    # - mas upgrade

    INSTALL_APPS=($(comm -13 \
        <(mas list | grep -Eo '^([0-9])+' | sort | uniq) \
        <(lk_echo_array MAS_APPS | sort | uniq)))
    [ "${#INSTALL_APPS[@]}" -eq 0 ] || {
        # TODO: output names rather than IDs
        lk_echo_array INSTALL_APPS |
            lk_console_list "Installing new apps:"
        lk_tty mas install "${INSTALL_APPS[@]}"
    }

    lk_console_message "Provisioning complete"

    exit
}

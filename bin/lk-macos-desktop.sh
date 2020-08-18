#!/bin/bash
# shellcheck disable=SC1090,SC2034

export LK_BASE=${LK_BASE:-/opt/lk-platform}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

set -euo pipefail
lk_die() { s=$? && echo "${BASH_SOURCE[0]:+${BASH_SOURCE[0]}: }$1" >&2 && false || exit $s; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[ "$(uname -s)" = Darwin ] || lk_die "not running on macOS"

export SUDO_PROMPT="[sudo] password for %u: "

LOG_FILE=/var/log/${LK_PATH_PREFIX}install.log
[ -e "$LOG_FILE" ] ||
    sudo install -m 0640 -o "$USER" -g admin /dev/null "$LOG_FILE"
exec 6>&1 7>&2
exec > >(tee -a "$LOG_FILE") 2>&1

if [ -f "$LK_BASE/lib/bash/core.sh" ]; then
    . "$LK_BASE/lib/bash/core.sh"
    . "$LK_BASE/lib/bash/macos.sh"
    . "$LK_BASE/lib/macos/packages.sh"
else
    SCRIPT_DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$SCRIPT_DIR"
    for FILE_PATH in /lib/bash/core.sh /lib/bash/macos.sh /lib/macos/packages.sh; do
        FILE=$SCRIPT_DIR/${FILE_PATH##*/}
        URL=https://raw.githubusercontent.com/lkrms/lk-platform/$LK_PLATFORM_BRANCH$FILE_PATH
        if [ ! -e "$FILE" ]; then
            curl --fail --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download from GitHub: $URL"
            }
        fi
        . "$FILE"
    done
fi

LK_BACKUP_SUFFIX=-$(lk_timestamp).bak

FILE=/etc/sudoers.d/${LK_PATH_PREFIX}defaults
if ! sudo test -e "$FILE"; then
    lk_console_message "Configuring sudo"
    sudo install -m 0440 /dev/null "$FILE"
    cat <<EOF | sudo tee "$FILE" >/dev/null
Defaults umask = 0022
Defaults umask_override
EOF
    LK_SUDO=1 lk_console_file "$FILE"
fi

if ! USER_UMASK=$(defaults read \
    /var/db/com.apple.xpc.launchd/config/user.plist Umask 2>/dev/null) ||
    [ "$USER_UMASK" -ne 2 ]; then
    lk_console_message "Setting default umask"
    lk_console_detail "Running:" "launchctl config user umask 002"
    sudo launchctl config user umask 002 >/dev/null
fi
umask 002

lk_macos_install_command_line_tools ||
    lk_die "unable to install command line tools"

# If Xcode and the standalone Command Line Tools package are both installed,
# switch to Xcode or commands like opendiff won't work
if [ -e /Applications/Xcode.app ]; then
    lk_console_message "Checking Xcode configuration"
    TOOLS_PATH=$(lk_macos_command_line_tools_path)
    if [[ "$TOOLS_PATH" != /Applications/Xcode.app* ]]; then
        lk_console_detail "Switching from command line tools to Xcode with:" \
            "xcode-select --switch /Applications/Xcode.app"
        sudo xcode-select --switch /Applications/Xcode.app
        OLD_TOOLS_PATH=$TOOLS_PATH
        TOOLS_PATH=$(lk_macos_command_line_tools_path)
        lk_console_detail "Development tools directory:" \
            "$OLD_TOOLS_PATH -> $LK_BOLD$TOOLS_PATH$LK_RESET"
    fi
fi

if [ ! -e "$LK_BASE" ]; then
    lk_console_item "Installing lk-platform to:" "$LK_BASE"
    sudo install -d -m 2775 -o "$USER" -g admin "$LK_BASE"
    git clone -b "$LK_PLATFORM_BRANCH" \
        https://github.com/lkrms/lk-platform.git "$LK_BASE"
    lk_keep_original /etc/default/lk-platform
    [ -e /etc/default ] ||
        sudo install -d -m 0755 -g wheel /etc/default
    sudo install -m 0664 -g admin /dev/null /etc/default/lk-platform
    printf '%s=%q\n' \
        LK_BASE "$LK_BASE" \
        LK_PATH_PREFIX "$LK_PATH_PREFIX" \
        LK_PLATFORM_BRANCH "$LK_PLATFORM_BRANCH" |
        sudo tee /etc/default/lk-platform >/dev/null
    lk_console_file /etc/default/lk-platform
fi

DIR=$HOME/.homebrew
if [ ! -e "$DIR" ]; then
    lk_console_item "Installing Homebrew to:" "$DIR"
    git clone https://github.com/Homebrew/brew.git "$DIR"
fi

eval "$(. "$LK_BASE/lib/bash/env.sh")"

lk_console_message "Updating Homebrew"
brew update

# TODO:
# - install GNU essentials
# - create ~/.bashrc, ~/.profile
# - "$LK_BASE/bin/lk-platform-install.sh"

lk_console_message "Provisioning complete" "$LK_GREEN"

#!/bin/bash
# shellcheck disable=SC1090

LK_BASE=${LK_BASE:-/opt/lk-platform}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

set -euo pipefail
lk_die() { s=$? && echo "${BASH_SOURCE[0]:+${BASH_SOURCE[0]}: }$1" >&2 && false || exit $s; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[ "$(uname -s)" = Darwin ] || lk_die "not running on macOS"

LOG_FILE="/var/log/${LK_PATH_PREFIX}install.log"
[ -e "$LOG_FILE" ] ||
    sudo install -m 0640 -o "$USER" -g admin /dev/null "$LOG_FILE"
exec 6>&1 7>&2
exec > >(tee -a "$LOG_FILE") 2>&1

if [ -f "$LK_BASE/lib/bash/core.sh" ]; then
    . "$LK_BASE/lib/bash/core.sh"
    . "$LK_BASE/lib/macos/packages.sh"
else
    SCRIPT_DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$SCRIPT_DIR"
    for FILE_PATH in /lib/bash/core.sh /lib/macos/packages.sh; do
        FILE=$SCRIPT_DIR/${FILE_PATH##*/}
        URL=https://raw.githubusercontent.com/lkrms/lk-platform/$LK_PLATFORM_BRANCH$FILE_PATH
        if [ ! -e "$FILE" ]; then
            curl --output "$FILE" "$URL" || {
                rm -f "$FILE"
                lk_die "unable to download from GitHub: $URL"
            }
        fi
        . "$FILE"
    done
fi

FILE="/etc/sudoers.d/${LK_PATH_PREFIX}defaults"
if ! sudo test -e "$FILE"; then
    lk_console_message "Configuring sudo"
    sudo install -m 0440 /dev/null "$FILE"
    cat <<EOF | sudo tee "$FILE" >/dev/null
Defaults umask = 0022
Defaults umask_override
EOF
fi

if ! USER_UMASK=$(defaults read \
    /var/db/com.apple.xpc.launchd/config/user.plist Umask 2>/dev/null) ||
    [ "$USER_UMASK" -ne 2 ]; then
    lk_console_message "Setting default umask"
    sudo launchctl config user umask 002
fi
umask 002

lk_console_message "Checking command line tools"
while ! TOOLS_PATH=$(xcode-select --print-path); do
    lk_console_detail "Starting the Command Line Tools installer"
    sudo xcode-select --install
    lk_pause "After the installer finishes, press return to continue . . . "
done
lk_console_detail "Active command line tools directory:" "$TOOLS_PATH"
# If Xcode and the standalone Command Line Tools package are both installed,
# switch to Xcode or commands like opendiff won't work
if [ -e /Applications/Xcode.app ] &&
    [[ "$TOOLS_PATH" != /Applications/Xcode.app* ]]; then
    lk_console_detail "Switching to Xcode's command line tools"
    sudo xcode-select --switch /Applications/Xcode.app
    TOOLS_PATH=$(xcode-select --print-path)
    lk_console_detail "New command line tools directory:" "$TOOLS_PATH"
fi

if [ ! -e "$LK_BASE" ]; then
    lk_console_item "Installing lk-platform to:" "$LK_BASE"
    sudo install -d -m 2775 -o "$USER" -g admin "$LK_BASE"
    git clone -b "$LK_PLATFORM_BRANCH" \
        "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
    printf '%s=%q\n' \
        LK_BASE "$LK_BASE" \
        LK_PATH_PREFIX "$LK_PATH_PREFIX" \
        LK_PLATFORM_BRANCH "$LK_PLATFORM_BRANCH" |
        sudo tee "/etc/default/lk-platform" >/dev/null
fi

# TODO:
# - install Homebrew
# - install GNU essentials
# - "$LK_BASE/bin/lk-platform-install.sh"

lk_console_message "Provisioning complete" "$LK_GREEN"

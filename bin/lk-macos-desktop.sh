#!/bin/bash
# shellcheck disable=SC1090,SC2034,SC2207

export LK_BASE=${LK_BASE:-/opt/lk-platform}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()

# terminal-based
HOMEBREW_FORMULAE+=(
    # utilities
    exiftool
    imagemagick
    python-yq
    unison

    # networking
    openconnect
    vpn-slice

    # network monitoring
    iftop # shows network traffic by service and host
    nload # shows bandwidth by interface

    # system
    #acme.sh
)

# desktop
HOMEBREW_TAPS+=(
    federico-terzi/espanso
)

HOMEBREW_FORMULAE+=(
    #federico-terzi/espanso/espanso

    # PDF
    ghostscript
    mupdf-tools
    pandoc
    poppler
    pstoedit

    # multimedia - video
    youtube-dl
)

HOMEBREW_CASKS+=(
    caprine
    chromium
    firefox
    imageoptim
    keepassxc
    keepingyouawake
    libreoffice
    microsoft-teams
    nextcloud
    pencil
    scribus
    skype
    spotify
    stretchly
    the-unarchiver
    transmission
    typora

    # PDF
    basictex

    # photography
    adobe-dng-converter

    # multimedia - video
    handbrake
    #makemkv
    #mkvtoolnix
    subler
    vlc

    # system
    displaycal
    geekbench
    hex-fiend
    lingon-x

    # non-free
    acorn
    microsoft-office
)

# development
HOMEBREW_TAPS+=(
    adoptopenjdk/openjdk
    #mongodb/brew
)

HOMEBREW_FORMULAE+=(
    # email
    msmtp  # smtp client
    s-nail # mail and mailx commands

    #
    git-filter-repo

    #
    node
    yarn

    #
    composer #
    gcc@7    # Db2 module build dependency
    php

    #
    python

    #
    mariadb
    #mongodb/brew/mongodb-community

    #
    shellcheck
    shfmt

    # platforms
    awscli
)

HOMEBREW_CASKS+=(
    android-studio
    dbeaver-community
    sequel-pro
    sourcetree
    sublime-merge
    sublime-text
    vscodium

    #
    adoptopenjdk11
    meld
)

# VMs and containers
HOMEBREW_CASKS+=(
    #virtualbox
    #virtualbox-extension-pack
)

# hardware-related
HOMEBREW_CASKS+=(
    sonos
)

set -euo pipefail
lk_die() { s=$? && echo "${BASH_SOURCE[0]:+${BASH_SOURCE[0]}: }$1" >&2 && false || exit $s; }

[ "$EUID" -ne 0 ] || lk_die "cannot run as root"
[ "$(uname -s)" = Darwin ] || lk_die "not running on macOS"

export SUDO_PROMPT="[sudo] password for %p: "

if [ -f "$LK_BASE/lib/bash/core.sh" ]; then
    . "$LK_BASE/lib/bash/core.sh"
    lk_include provision macos
    . "$LK_BASE/lib/macos/packages.sh"
else
    SCRIPT_DIR=/tmp/${LK_PATH_PREFIX}install
    mkdir -p "$SCRIPT_DIR"
    echo "Downloading dependencies to: $SCRIPT_DIR" >&2
    for FILE_PATH in \
        /lib/bash/core.sh \
        /lib/bash/provision.sh \
        /lib/bash/macos.sh \
        /lib/macos/packages.sh; do
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

LK_LOG_FILE_MODE=0600 \
    lk_log_output ~/"${LK_PATH_PREFIX}install.log"

lk_console_message "Provisioning macOS"

lk_sudo_offer_nopasswd || true

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

lk_macos_install_command_line_tools ||
    lk_die "unable to install command line tools"

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
    lk_console_detail_file /etc/default/lk-platform
fi

function lk_brew_check_taps() {
    local TAP
    TAP=($(comm -13 \
        <(brew tap | sort | uniq) \
        <(lk_echo_array ${HOMEBREW_TAPS[@]+"${HOMEBREW_TAPS[@]}"} | sort | uniq)))
    [ "${#TAP[@]}" -eq "0" ] || {
        for TAP in "${TAP[@]}"; do
            lk_console_detail "Tapping" "$TAP"
            brew tap --quiet "$TAP" >&6 2>&7 || return
        done
    }
}

DIR=$HOME/.homebrew
if [ ! -e "$DIR" ]; then
    lk_console_item "Installing Homebrew to:" "$DIR"
    git clone https://github.com/Homebrew/brew.git "$DIR"
    eval "$(. "$LK_BASE/lib/bash/env.sh")"
    lk_console_detail "Updating formulae"
    brew update --quiet >&6 2>&7
    lk_brew_check_taps
    INSTALL=(
        coreutils
        findutils
        gawk
        grep
        inetutils
        netcat
        gnu-sed
        gnu-tar
        wget
    )
    lk_echo_array "${INSTALL[@]}" |
        lk_console_detail_list "Installing lk-platform dependencies:"
    brew install "${INSTALL[@]}" >&6 2>&7
else
    lk_console_item "Checking Homebrew installation at:" "$DIR"
    eval "$(. "$LK_BASE/lib/bash/env.sh")"
    lk_brew_check_taps
    lk_console_detail "Updating formulae"
    brew update --quiet >&6 2>&7
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

"$LK_BASE/bin/lk-platform-install.sh"

INSTALL_FORMULAE=($(comm -13 \
    <(brew list --formulae --full-name | sort | uniq) \
    <(lk_echo_array ${HOMEBREW_FORMULAE[@]+"${HOMEBREW_FORMULAE[@]}"} |
        sort | uniq)))
[ "${#INSTALL_FORMULAE[@]}" -eq "0" ] || {
    lk_echo_array "${INSTALL_FORMULAE[@]}" |
        lk_console_list "Installing new formulae:"
    brew install "${INSTALL_FORMULAE[@]}" >&6 2>&7
}

INSTALL_CASKS=($(comm -13 \
    <(brew list --casks --full-name | sort | uniq) \
    <(lk_echo_array ${HOMEBREW_CASKS[@]+"${HOMEBREW_CASKS[@]}"} |
        sort | uniq)))
[ "${#INSTALL_CASKS[@]}" -eq "0" ] || {
    lk_echo_array "${INSTALL_CASKS[@]}" |
        lk_console_list "Installing new casks:"
    brew cask install "${INSTALL_CASKS[@]}" >&6 2>&7
}

lk_console_message "Provisioning complete"

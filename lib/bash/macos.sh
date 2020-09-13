#!/bin/bash
# shellcheck disable=SC2207

function lk_macos_version() {
    local VERSION
    VERSION=$(sw_vers -productVersion) || return
    [[ ! $VERSION =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?$ ]] ||
        VERSION=${BASH_REMATCH[1]}
    echo "$VERSION"
}

function lk_macos_set_hostname() {
    sudo scutil --set ComputerName "$1" &&
        sudo scutil --set HostName "$1" &&
        sudo scutil --set LocalHostName "$1" &&
        sudo defaults write \
            /Library/Preferences/SystemConfiguration/com.apple.smb.server \
            NetBIOSName "$1"
}

function lk_macos_command_line_tools_path() {
    xcode-select --print-path 2>/dev/null
}

function lk_macos_command_line_tools_installed() {
    lk_macos_command_line_tools_path >/dev/null
}

function lk_macos_install_command_line_tools() {
    local ITEM_NAME S="[[:space:]]" \
        TRIGGER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    ! lk_macos_command_line_tools_installed || return 0
    lk_console_message "Installing command line tools"
    lk_console_detail "Searching for the latest Command Line Tools for Xcode"
    touch "$TRIGGER" &&
        ITEM_NAME=$(lk_keep_trying caffeinate -i softwareupdate --list |
            grep -E "^$S*\*.*Command Line Tools" |
            grep -Eiv "\W(beta|seed)\W" |
            sed -E "s/^$S*\*$S*(Label:$S*)?//" |
            sort --version-sort |
            tail -n1) ||
        lk_warn "unable to determine item name for Command Line Tools" ||
        return
    lk_console_detail "Installing Command Line Tools with:" \
        "softwareupdate --install \"$ITEM_NAME\""
    lk_keep_trying lk_elevate caffeinate -i \
        softwareupdate --install "$ITEM_NAME" >/dev/null || return
    lk_macos_command_line_tools_installed || return
    rm -f "$TRIGGER" || true
}

# lk_macos_kb_add_shortcut DOMAIN MENU_TITLE SHORTCUT
#   Add a keyboard shortcut to the NSUserKeyEquivalents dictionary for DOMAIN.
#
# Modifier keys:
#   ^ = Ctrl
#   ~ = Alt
#   $ = Shift
#   @ = Command
function lk_macos_kb_add_shortcut() {
    defaults write \
        "$1" NSUserKeyEquivalents -dict-add "$2" "$3"
    defaults write \
        "$HOME/Library/Preferences/$1.plist" NSUserKeyEquivalents -dict-add "$2" "$3"
}

function lk_macos_kb_reset_shortcuts() {
    defaults delete "$1" NSUserKeyEquivalents
}

function lk_macos_unmount() {
    local EXIT_STATUS=0 MOUNT_POINT
    for MOUNT_POINT in "$@"; do
        hdiutil unmount "$MOUNT_POINT" || EXIT_STATUS=$?
    done
    return "$EXIT_STATUS"
}

function lk_macos_install_pkg() {
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_detail "Installing:" "${1##*/}"
    lk_elevate installer -allowUntrusted -pkg "$1" -target / || return
}

function lk_macos_install_dmg() {
    local IFS MOUNT_ROOT MOUNT_POINTS EXIT_STATUS=0
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_detail "Attaching:" "${1##*/}"
    MOUNT_ROOT=$(lk_mktemp_dir) &&
        IFS=$'\n' &&
        MOUNT_POINTS=($(hdiutil attach -mountroot "$MOUNT_ROOT" "$1" |
            cut -sf3 | sed '/^[[:space:]]*$/d')) &&
        [ "${#MOUNT_POINTS[@]}" -gt 0 ] || return
    INSTALL=($(
        unset IFS
        find "${MOUNT_POINTS[@]}" -iname "*.pkg"
    )) || EXIT_STATUS=$?
    unset IFS
    [ "$EXIT_STATUS" -ne 0 ] ||
        [ "${#INSTALL[@]}" -eq 1 ] ||
        lk_warn "nothing to install" || EXIT_STATUS=$?
    [ "$EXIT_STATUS" -ne 0 ] ||
        lk_macos_install_pkg "${INSTALL[0]}" || EXIT_STATUS=$?
    lk_macos_unmount "${MOUNT_POINTS[@]}" >/dev/null || EXIT_STATUS=$?
    return "$EXIT_STATUS"
}

function lk_macos_install() {
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    case "$1" in
    *.pkg)
        lk_macos_install_pkg "$1"
        ;;
    *.dmg)
        lk_macos_install_dmg "$1"
        ;;
    *)
        lk_warn "unknown file type: $1"
        false
        ;;
    esac
}

# lk_macos_maybe_install_pkg_url PKGID PKG_URL [PKG_NAME]
function lk_macos_maybe_install_pkg_url() {
    local PKGID=$1 PKG_URL=$2 PKG_NAME=${3:-$1}
    pkgutil --pkgs | grep -Fx "$PKGID" >/dev/null || (
        lk_console_item "Installing package:" "$PKG_NAME"
        lk_console_detail "Downloading:" "$PKG_URL"
        DIR=$(lk_mktemp_dir) &&
            cd "$DIR" &&
            FILE=$(lk_download "$PKG_URL") &&
            lk_macos_install "$FILE" &&
            lk_console_message "Package installed successfully" "$LK_GREEN" || exit
    )
}

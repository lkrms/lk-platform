#!/bin/bash

function lk_macos_version() {
    local VERSION
    VERSION=$(sw_vers -productVersion) || return
    [[ ! $VERSION =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?$ ]] ||
        VERSION=${BASH_REMATCH[1]}
    echo "$VERSION"
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
        ITEM_NAME=$(softwareupdate --list |
            grep -E "^$S*\*.*Command Line Tools" |
            grep -Eiv "\W(beta|seed)\W" |
            sed -E "s/^$S*\*$S*(Label:$S*)?//" |
            sort --version-sort |
            tail -n1) ||
        lk_warn "unable to determine item name for Command Line Tools" ||
        return
    lk_console_detail "Installing Command Line Tools with:" \
        "softwareupdate --install \"$ITEM_NAME\""
    lk_elevate softwareupdate --install "$ITEM_NAME" >/dev/null || return
    lk_macos_command_line_tools_installed || return
    rm -f "$TRIGGER" || true
}

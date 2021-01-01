#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
LOGIN_ITEMS=()

# won't be uninstalled if present
HOMEBREW_KEEP_FORMULAE=()

HOMEBREW_KEEP_CASKS=(
    zoom
)

# terminal-based
HOMEBREW_FORMULAE+=(
    # utilities
    exiftool
    imagemagick
    unison

    # networking
    openconnect
    vpn-slice
)

# desktop
HOMEBREW_TAPS+=(
    federico-terzi/espanso
)

HOMEBREW_FORMULAE+=(
    federico-terzi/espanso/espanso

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
    chromium
    firefox
    flycut
    icanhazshortcut
    imageoptim
    keepassxc
    keepingyouawake
    libreoffice
    messenger
    nextcloud
    skype
    spotify
    the-unarchiver
    transmission
    typora

    # PDF
    basictex

    # multimedia - video
    vlc

    # system
    geekbench
    lingon-x
)

MAS_APPS+=(
    409183694 # Keynote
    409203825 # Numbers
    409201541 # Pages

    #
    526298438 # Lightshot Screenshot
    441258766 # Magnet

    #
    1295203466 # Microsoft Remote Desktop
    1303222628 # Paprika
    1055273043 # PDF Expert

    #
    585829637 # Todoist
)

# hardware-related
HOMEBREW_CASKS+=(
    sonos
)

LOGIN_ITEMS+=(
    "/Applications/Flycut.app"
    "/Applications/Lightshot Screenshot.app"
    "/Applications/Magnet.app"
    "/Applications/Messenger.app"
    "/Applications/nextcloud.app"
    "/Applications/Skype.app"
    "/Applications/Todoist.app"
)

#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
LOGIN_ITEMS=()

# Terminal-based
HOMEBREW_FORMULAE+=(
    # Utilities
    exiftool
    imagemagick
    unison

    # Networking
    openconnect
    vpn-slice
)

# Desktop
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

    # Multimedia (video)
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

    # Multimedia (video)
    vlc

    # System
    geekbench
    #lingon-x
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

# Hardware-related
HOMEBREW_CASKS+=(
    sonos
)

LOGIN_ITEMS+=(
    "/Applications/Flycut.app"
    "/Applications/Lightshot Screenshot.app"
    "/Applications/Magnet.app"
    "/Applications/Mail.app"
    "/Applications/Messages.app"
    "/Applications/Messenger.app"
    "/Applications/nextcloud.app"
    "/Applications/Skype.app"
    "/Applications/Todoist.app"
)
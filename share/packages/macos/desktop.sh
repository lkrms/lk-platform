#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
FORCE_IBREW=()
LOGIN_ITEMS=()

HOMEBREW_TAPS+=(
    homebrew/cask-drivers
    homebrew/cask-fonts
)

# Terminal-based
HOMEBREW_FORMULAE+=(
    # Utilities
    exiftool
    imagemagick
    unison

    # Networking
    iperf3
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
    qpdf

    # Multimedia (video)
    youtube-dl
    yt-dlp
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    alt-tab
    bbedit
    chromium
    firefox
    flycut
    imageoptim
    iterm2
    keepassxc
    keepingyouawake
    messenger
    mysides
    nextcloud
    skype
    spotify
    the-unarchiver
    typora

    # PDF
    basictex

    # Multimedia (video)
    vlc

    # Non-free
    microsoft-office
)

MAS_APPS+=(
    409183694 # Keynote
    409203825 # Numbers
    409201541 # Pages

    #
    1502839586 # Hand Mirror
    526298438  # Lightshot Screenshot
    441258766  # Magnet

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

HOMEBREW_KEEP_FORMULAE+=(
    ocaml
)

HOMEBREW_KEEP_CASKS+=(
    geekbench
    google-chrome
    hammerspoon
    libreoffice
    lingon-x
    logitech-g-hub
    logitech-gaming-software
    teamviewer
    transmission
)

LOGIN_ITEMS+=(
    "/Applications/Flycut.app"
    "/Applications/Lightshot Screenshot.app"
    "/Applications/Magnet.app"
    "/Applications/Nextcloud.app"
    "/Applications/Skype.app"
)

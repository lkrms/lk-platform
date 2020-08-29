#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()

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
    caprine
    chromium
    firefox
    imageoptim
    keepassxc
    keepingyouawake
    libreoffice
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

# hardware-related
HOMEBREW_CASKS+=(
    sonos
)

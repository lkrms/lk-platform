#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
HOMEBREW_FORCE_INTEL=()

HOMEBREW_TAPS+=(
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
HOMEBREW_FORMULAE+=(
    # PDF
    ghostscript
    mupdf-tools
    pandoc
    poppler
    pstoedit
    qpdf

    # Multimedia (video)
    yt-dlp
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    alt-tab
    bbedit
    copyq
    espanso
    firefox
    flameshot
    flycut
    google-chrome
    imageoptim
    iterm2
    keepassxc
    keepingyouawake
    the-unarchiver

    # PDF
    basictex

    # Multimedia (video)
    vlc

    # Non-free
    typora
)

MAS_APPS+=(
    409201541  # Pages
    409203825  # Numbers
    409183694  # Keynote
    1295203466 # Microsoft Remote Desktop
)

HOMEBREW_KEEP_FORMULAE+=(
)

HOMEBREW_KEEP_CASKS+=(
    geekbench
    hammerspoon
    libreoffice
    lingon-x
    logitech-g-hub
    pdf-expert
    teamviewer
    transmission
)

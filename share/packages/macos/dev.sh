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

    # Network monitoring
    iftop # Shows network traffic by service and host
    nload # Shows bandwidth by interface

    # System
    #acme.sh
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

    # Photography
    adobe-dng-converter

    # Multimedia (video)
    handbrake
    #makemkv
    #mkvtoolnix
    subler
    vlc

    # System
    displaycal
    geekbench
    hex-fiend
    #lingon-x
    #shortcutdetective

    # Non-free
    acorn
    microsoft-office
)

MAS_APPS+=(
    409183694 # Keynote
    409203825 # Numbers
    409201541 # Pages

    #
    526298438 # Lightshot Screenshot
    441258766 # Magnet

    #
    420212497  # Byword
    404705039  # Graphic
    1295203466 # Microsoft Remote Desktop
    1303222628 # Paprika
    1055273043 # PDF Expert

    #
    506189836 # Harvest
    585829637 # Todoist
)

# Development
HOMEBREW_TAPS+=(
    adoptopenjdk/openjdk
    #mongodb/brew
)

HOMEBREW_FORMULAE+=(
    # Email
    msmtp  # SMTP client
    s-nail # `mail` and `mailx` commands

    #
    git-filter-repo

    #
    node
    yarn

    #
    composer #
    # gcc@7  # Db2 module build dependency
    php

    #
    python

    #
    mariadb
    #mongodb/brew/mongodb-community

    #
    shellcheck
    shfmt

    # Platforms
    awscli
)

HOMEBREW_CASKS+=(
    android-studio
    dbeaver-community
    font-jetbrains-mono
    sequel-pro
    sourcetree
    sublime-merge
    sublime-text
    vscodium

    #
    adoptopenjdk/openjdk/adoptopenjdk11
    meld
)

MAS_APPS+=(
    497799835 # Xcode
)

# VMs and containers
HOMEBREW_CASKS+=(
    virtualbox
    virtualbox-extension-pack
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
    "/Applications/Microsoft Teams.app"
    "/Applications/nextcloud.app"
    "/Applications/Skype.app"
    "/Applications/Todoist.app"
)

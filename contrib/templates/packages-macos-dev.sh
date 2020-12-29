#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()

# won't be uninstalled if present
HOMEBREW_KEEP_FORMULAE=(
    ocaml
)

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
    #lingon-x
    #shortcutdetective

    # non-free
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

# hardware-related
HOMEBREW_CASKS+=(
    sonos
)

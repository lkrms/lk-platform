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

# VMs and containers
HOMEBREW_CASKS+=(
    #virtualbox
    #virtualbox-extension-pack
)

# hardware-related
HOMEBREW_CASKS+=(
    sonos
)

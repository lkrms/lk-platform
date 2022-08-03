#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_UNLINK_FORMULAE=()
HOMEBREW_LINK_KEGS=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
HOMEBREW_FORCE_INTEL=()
LOGIN_ITEMS=()

HOMEBREW_TAPS+=(
    homebrew/cask-drivers
    homebrew/cask-fonts
    homebrew/services
)

# Terminal-based
HOMEBREW_FORMULAE+=(
    # Utilities
    csvkit
    exiftool
    imagemagick
    s3cmd
    unison

    # Networking
    iperf3
    openconnect
    vpn-slice

    # Network monitoring
    iftop # Shows network traffic by service and host
    nload # Shows bandwidth by interface

    # System
    certbot
    dosfstools
    mtools
    nmap
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
    youtube-dl
    yt-dlp
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    alt-tab
    chromium
    clockify
    copyq
    espanso
    firefox
    flameshot
    flycut
    hammerspoon
    imageoptim
    inkscape
    iterm2
    keepassxc
    keepingyouawake
    keyboard-cleaner
    libreoffice
    messenger
    microsoft-teams
    mysides
    nextcloud
    pencil
    rescuetime
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
    subler
    vlc

    # System
    displaycal
    geekbench
    hex-fiend

    # Non-free
    acorn
    microsoft-office
)

MAS_APPS+=(
    409183694 # Keynote
    409203825 # Numbers
    409201541 # Pages

    #
    417375580  # BetterSnapTool
    1502839586 # Hand Mirror

    #
    420212497  # Byword
    404705039  # Graphic
    1295203466 # Microsoft Remote Desktop
    1055273043 # PDF Expert

    #
    585829637 # Todoist
)

# Development
HOMEBREW_TAPS+=(
    adoptopenjdk/openjdk
    #lkrms/virt-manager
    #mongodb/brew
)

HOMEBREW_FORMULAE+=(
    autopep8
    cmake
    emscripten
    graphviz # Optional phpdoc dependency
    plantuml # Optional phpdoc dependency

    #
    libvirt
    qemu
    virt-manager
    #lkrms/virt-manager/virt-viewer

    # Email
    msmtp  # SMTP client
    s-nail # `mail` and `mailx` commands

    #
    git
    git-cola
    git-filter-repo

    #
    node
    nvm
    yarn

    #
    composer
    php

    #
    python
    python@3.9

    #
    perltidy

    #
    mariadb
    #mongodb/brew/mongodb-community

    #
    shellcheck
    shfmt

    #
    lua
    luarocks

    # Platforms
    awscli
    azure-cli
    gh
    linode-cli
    wp-cli
)

HOMEBREW_UNLINK_FORMULAE+=(
)

HOMEBREW_LINK_KEGS+=(
)

HOMEBREW_FORCE_INTEL+=(
    composer
    php
    php@7.4
    wp-cli
)

HOMEBREW_CASKS+=(
    android-studio
    dash
    dbeaver-community
    font-jetbrains-mono
    http-toolkit
    robo-3t
    sequel-pro
    sourcetree
    sublime-merge
    sublime-text
    visual-studio-code

    #
    adoptopenjdk/openjdk/adoptopenjdk11
    meld
)

MAS_APPS+=(
    1499215709 # Pasteboard Viewer
    497799835  # Xcode
)

# Hardware-related
HOMEBREW_CASKS+=(
    sonos
)

HOMEBREW_KEEP_FORMULAE+=(
    #
    php
    php@7.4

    #
    autoconf
    automake

    #
    rust

    #
    azure/functions/azure-functions-core-tools@4
    microsoft/mssql-release/msodbcsql17
    microsoft/mssql-release/mssql-tools

    #
    lkrms/virt-manager/libvirt

    #
    autozimu/formulas/unison-fsmonitor
    ddcctl
)

HOMEBREW_KEEP_CASKS+=(
    bbedit
    google-chrome
    key-codes
    lingon-x
    microsoft-azure-storage-explorer
    sfdx
    shortcutdetective
    studio-3t
    teamviewer

    #
    makemkv
    mkvtoolnix

    #
    virtualbox
    virtualbox-extension-pack

    #
    logitech-g-hub
    logitech-gaming-software
    monitorcontrol
)

LOGIN_ITEMS+=(
    "/Applications/Nextcloud.app"
    "/Applications/Todoist.app"
)

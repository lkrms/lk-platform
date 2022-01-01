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
    homebrew/cask-versions
    homebrew/services
    azure/functions
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
    #acme.sh
    dosfstools
    mtools
    nmap
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
    chromium
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
    scribus-dev
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
    1502839586 # Hand Mirror
    441258766  # Magnet

    #
    420212497  # Byword
    404705039  # Graphic
    1295203466 # Microsoft Remote Desktop
    1055273043 # PDF Expert

    #
    506189836 # Harvest
    585829637 # Todoist
)

# Development
HOMEBREW_TAPS+=(
    adoptopenjdk/openjdk
    lkrms/virt-manager
    #mongodb/brew
)

HOMEBREW_FORMULAE+=(
    autopep8
    cmake
    emscripten

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
    php@8.0

    #
    python

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
    azure-functions-core-tools@3
    wp-cli
)

HOMEBREW_UNLINK_FORMULAE+=(
    php
)

HOMEBREW_LINK_KEGS+=(
    php@8.0
)

HOMEBREW_FORCE_INTEL+=(
    composer
    php
    php@7.2
    php@7.3
    php@7.4
    php@8.0
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
    497799835 # Xcode
)

# Hardware-related
HOMEBREW_CASKS+=(
    sonos
)

HOMEBREW_KEEP_FORMULAE+=(
    #
    php
    php@7.2
    php@7.3
    php@7.4
    php@8.0

    #
    microsoft/mssql-release/msodbcsql17
    microsoft/mssql-release/mssql-tools

    #
    libvirt
    qemu
    lkrms/virt-manager/virt-manager

    #
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
    "/Applications/flameshot.app"
    "/Applications/Flycut.app"
    "/Applications/Hammerspoon.app"
    "/Applications/Mail.app"
    "/Applications/Messenger.app"
    "/Applications/Microsoft Teams.app"
    "/Applications/Nextcloud.app"
    "/Applications/Skype.app"
    "/Applications/Todoist.app"
    "/System/Applications/Mail.app"
)

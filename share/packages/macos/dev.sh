#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
HOMEBREW_FORCE_INTEL=()
LOGIN_ITEMS=()

HOMEBREW_TAPS+=(
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
    nmap
    openconnect
    vpn-slice

    # Network monitoring
    iftop # Shows network traffic by service and host
    nload # Shows bandwidth by interface

    # System
    certbot
    dosfstools # mkfs.vfat
    mtools     # mcopy
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
    libreoffice
    mysides
    pencil
    scribus
    stretchly
    the-unarchiver
    transmission

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
    hex-fiend

    # Non-free
    geekbench
    typora
)

MAS_APPS+=(
    409201541  # Pages
    409203825  # Numbers
    409183694  # Keynote
    1295203466 # Microsoft Remote Desktop
)

# Development
HOMEBREW_TAPS+=(
    mongodb/brew
)

HOMEBREW_FORMULAE+=(
    autopep8
    graphviz # Optional phpdoc dependency
    plantuml # Optional phpdoc dependency

    #
    libvirt
    qemu
    virt-manager

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
    php@7.4

    #
    python
    python@3.9

    #
    perltidy

    #
    mariadb
    mongodb/brew/mongodb-database-tools

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

HOMEBREW_FORCE_INTEL+=(
    composer
    php
    php@7.4
    wp-cli
)

HOMEBREW_CASKS+=(
    dbeaver-community
    docker
    font-jetbrains-mono
    http-toolkit
    robo-3t
    visual-studio-code

    #
    meld
    temurin
)

MAS_APPS+=(
    1499215709 # Pasteboard Viewer
    497799835  # Xcode
)

HOMEBREW_KEEP_FORMULAE+=(
    #
    autoconf
    automake
    cmake

    #
    rust

    #
    emscripten

    #
    azure/functions/azure-functions-core-tools@4
    microsoft/mssql-release/msodbcsql17
    microsoft/mssql-release/mssql-tools

    #
    autozimu/formulas/unison-fsmonitor
)

HOMEBREW_KEEP_CASKS+=(
    android-studio
    bbedit
    google-chrome
    key-codes
    sequel-pro
    shortcutdetective
    sourcetree
    teamviewer

    #
    microsoft-azure-storage-explorer
    sfdx

    #
    makemkv
    mkvtoolnix

    #
    logitech-g-hub
)

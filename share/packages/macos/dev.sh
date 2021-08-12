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
    homebrew/services
)

# Terminal-based
HOMEBREW_FORMULAE+=(
    # Utilities
    exiftool
    imagemagick
    s3cmd
    unison

    # Networking
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

    # Multimedia (video)
    youtube-dl
)

HOMEBREW_CASKS+=(
    alt-tab
    chromium
    firefox
    flycut
    hammerspoon
    imageoptim
    iterm2
    keepassxc
    keepingyouawake
    libreoffice
    messenger
    microsoft-teams
    mysides
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
    lkrms/virt-manager
    #mongodb/brew
)

HOMEBREW_FORMULAE+=(
    autopep8
    cmake
    emscripten
    gdb

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

    # Platforms
    awscli
)

FORCE_IBREW+=(
    php
    php@7.2
    php@7.3
    php@7.4
    lkrms/virt-manager/virt-manager
)

HOMEBREW_CASKS+=(
    android-studio
    dbeaver-community
    font-jetbrains-mono
    http-toolkit
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
    meson
    ninja
    ocaml

    #
    php
    php@7.2
    php@7.3
    php@7.4

    #
    libvirt
    qemu
    lkrms/virt-manager/virt-manager

    #
    ddcctl
)

HOMEBREW_KEEP_CASKS+=(
    cyberduck
    icanhazshortcut
    key-codes
    lingon-x
    microsoft-azure-storage-explorer
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
    "/Applications/AltTab.app"
    "/Applications/Flycut.app"
    "/Applications/Hammerspoon.app"
    "/Applications/Lightshot Screenshot.app"
    "/Applications/Magnet.app"
    "/Applications/Mail.app"
    "/Applications/Messenger.app"
    "/Applications/Microsoft Teams.app"
    "/Applications/Nextcloud.app"
    "/Applications/Skype.app"
    "/Applications/Todoist.app"
    "/System/Applications/Mail.app"
)

#!/usr/bin/env bash

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_EXCEPT=()

PAC_OFFER=(
    geekbench
    teamviewer
    zoom
)

lk_is_virtual || {
    PAC_PACKAGES+=(
        glmark2
        guvcview # Webcam utility
        linssid  # Wi-Fi scanner
    )
    AUR_PACKAGES+=(
        geekbench5
    )
    ! lk_system_has_intel_graphics || PAC_PACKAGES+=(
        clinfo
        intel-compute-runtime
        vulkan-intel
        vulkan-tools
    )
    ! lk_system_has_nvidia_graphics || PAC_PACKAGES+=(
        clinfo
        opencl-nvidia
        vulkan-tools
    )
    ! lk_system_has_amd_graphics || PAC_PACKAGES+=(
        clinfo
        libclc
        opencl-clover-mesa
        vulkan-radeon
        vulkan-tools
    )
}

AUR_PACKAGES+=(
    brother-hl5450dn
    brother-hll3230cdw
)

PAC_PACKAGES+=(
    # Shell
    shfmt

    # Utilities
    csvkit
    glances

    # Network
    iperf3
    net-tools # Optional x11vnc dependency
    networkmanager-l2tp
    networkmanager-openconnect
    samba

    # System
    plocate
)

AUR_PACKAGES+=(
    gp-saml-gui-git
    pacman-cleanup-hook
    vpn-slice
)

# Desktop
PAC_PACKAGES+=(
    chromium
    copyq
    filezilla
    firefox
    firefox-i18n-en-gb
    flameshot
    freerdp
    ghostwriter
    gimp
    gnome-font-viewer
    gucharmap
    inkscape
    keepassxc
    libreoffice-fresh
    libreoffice-fresh-en-gb
    nextcloud-client
    remmina
    screenkey
    scribus
    slop
    speech-dispatcher
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-gtk

    # For LibreOffice
    hunspell
    hunspell-en_au
    hyphen
    hyphen-en

    # PDF
    ghostscript        # PDF/PostScript processing
    mupdf-tools        # PDF manipulation
    pandoc-cli         # Text conversion (e.g. Markdown to PDF)
    poppler            # Provides pdfimages
    pstoedit           # PDF/PostScript conversion to vector formats
    qpdf               # PDF manipulation (e.g. add underlay)
    texlive-latexextra # PDF support for pandoc
    texlive-fontsextra #
    tesseract          # OCR
    tesseract-data-eng

    # Photography
    geeqie
    rapid-photo-downloader

    # Search (Recoll)
    antiword            # Word
    aspell-en           # English stemming
    catdoc              # Excel, Powerpoint
    perl-image-exiftool # EXIF metadata
    python-lxml         # Spreadsheets
    python-mutagen      # Audio metadata
    recoll
    unrtf

    # Multimedia - playback
    gst-plugins-bad

    # Multimedia - audio
    audacity
    strawberry

    # Multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    yt-dlp

    # System
    dconf-editor
    gparted
    guake
    libsecret # Provides secret-tool

    # Automation
    evtest
    sxhkd
    wmctrl
    xautomation
    xclip
    xdotool
    xprintidle
)

AUR_PACKAGES+=(
    caprine
    clockify-desktop
    emote
    espanso-x11
    highlight-pointer
    key-mon
    libreoffice-extension-languagetool
    masterpdfeditor-free
    nomacs-git
    qpdfview
    rescuetime2
    simplescreenrecorder
    spotify
    stretchly
    teams-for-linux
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
    typora

    # System
    hfsprogs

    # Automation
    devilspie2-git
    quicktile-git
)

lk_is_bootstrap ||
    AUR_PACKAGES+=(ttf-ms-win10)

# Development
PAC_PACKAGES+=(
    meld

    #
    jre17-openjdk

    #
    nodejs
    npm

    #
    php
    php-gd
    php-imagick
    php-sqlite

    #
    python
    python-dateutil
    python-pip
    python-requests
    python-virtualenv

    #
    lua
    lua-penlight
    lua-posix
)

AUR_PACKAGES+=(
    python-demjson3
)

#!/bin/bash

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    teamviewer
    zoom
)

lk_is_virtual || {
    PAC_PACKAGES+=(
        guvcview # Webcam utility
        linssid  # Wi-Fi scanner
    )
    AUR_PACKAGES+=(
        geekbench
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
        opencl-mesa
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
    mlocate
)

AUR_PACKAGES+=(
    pacman-cleanup-hook
    vpn-slice
)

# Desktop
PAC_PACKAGES+=(
    caprine
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
    nomacs
    qalculate-gtk
    qpdfview
    remmina
    scribus
    simplescreenrecorder
    speedcrunch
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-gtk

    # PDF
    ghostscript  # PDF/PostScript processing
    mupdf-tools  # PDF manipulation
    pandoc       # Text conversion (e.g. Markdown to PDF)
    poppler      # Provides pdfimages
    pstoedit     # PDF/PostScript conversion to vector formats
    qpdf         # PDF manipulation (e.g. add underlay)
    texlive-core # PDF support for pandoc

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
    clementine
    gst-plugins-bad

    # Multimedia - audio
    audacity

    # Multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mpv
    youtube-dl
    yt-dlp

    # System
    dconf-editor
    gparted
    guake
    libsecret   # Provides secret-tool
    libva-utils # Provides vainfo
    vdpauinfo

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
    emote
    espanso
    masterpdfeditor-free
    rescuetime2
    skypeforlinux-stable-bin
    spotify
    stretchly-bin
    teams
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
    typora

    # System
    hfsprogs

    # Automation
    devilspie2
    quicktile-git
)

lk_is_bootstrap ||
    AUR_PACKAGES+=(ttf-ms-win10)

# Development
PAC_PACKAGES+=(
    meld

    #
    jre11-openjdk

    #
    nodejs
    npm

    #
    php
    php-gd
    php-imagick
    php-imap
    php-intl
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
)

AUR_PACKAGES+=(
    lua-posix
    python-demjson3
)

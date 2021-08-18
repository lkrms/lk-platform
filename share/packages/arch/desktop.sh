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
    # networking
    iperf3
    networkmanager-l2tp
    networkmanager-openconnect
)

AUR_PACKAGES+=(
    pacman-cleanup-hook
    vpn-slice
)

# desktop
PAC_PACKAGES+=(
    caprine
    copyq
    filezilla
    firefox-i18n-en-gb
    flameshot
    freerdp
    ghostwriter
    gimp
    gnome-font-viewer
    gucharmap
    keepassxc
    libreoffice-fresh-en-gb
    nextcloud-client
    nomacs
    qalculate-gtk
    qpdfview
    remmina
    simplescreenrecorder
    speedcrunch
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-gtk

    # PDF
    ghostscript  # PDF/PostScript processor
    mupdf-tools  # PDF manipulation tools
    pandoc       # text conversion tool (e.g. Markdown to PDF)
    poppler      # PDF tools like pdfimages
    pstoedit     # converts PDF/PostScript to vector formats
    texlive-core # required for PDF output from pandoc

    # photography
    geeqie
    rapid-photo-downloader

    # search (Recoll)
    antiword            # Word
    aspell-en           # English stemming
    catdoc              # Excel, Powerpoint
    perl-image-exiftool # EXIF metadata
    python-lxml         # spreadsheets
    python-mutagen      # audio metadata
    recoll
    unrtf

    # multimedia - playback
    clementine
    gst-plugins-bad

    # multimedia - audio
    audacity

    # multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mpv
    youtube-dl

    # system
    dconf-editor
    gparted
    guake
    libsecret   # secret-tool
    libva-utils # vainfo
    vdpauinfo

    # automation
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
    skypeforlinux-stable-bin
    spotify
    stretchly-git
    teams
    todoist-appimage
    trimage
    ttf-apple-emoji
    typora

    # system
    hfsprogs

    # automation
    devilspie2
    quicktile-git
)

lk_is_bootstrap ||
    AUR_PACKAGES+=(ttf-ms-win10)

# development
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
    demjson
    lua-posix
)

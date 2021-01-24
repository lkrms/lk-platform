#!/bin/bash

# shellcheck disable=SC2034

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    zoom
)

lk_is_virtual || {
    PAC_PACKAGES+=(
        guvcview # Webcam utility
        linssid  # Wi-Fi scanner
    )
    ! lk_system_has_intel_graphics || PAC_PACKAGES+=(
        clinfo
        intel-compute-runtime
    )
    ! lk_system_has_nvidia_graphics || PAC_PACKAGES+=(
        clinfo
        opencl-nvidia
    )
}

AUR_PACKAGES+=(
    brother-hl5450dn
    brother-hll3230cdw
)

PAC_PACKAGES+=(
    # utilities
    unison

    # networking
    openconnect

    # monitoring
    atop
    iotop

    # network monitoring
    iftop   # shows network traffic by service and host
    nethogs # groups bandwidth by process ('nettop')
    nload   # shows bandwidth by interface

    # system
    hwinfo
    sysfsutils
)

AUR_PACKAGES+=(
    networkmanager-l2tp
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
    stretchly
    teams
    todoist-electron
    trimage
    ttf-ms-win10
    typora

    # multimedia - video
    makemkv
    video-trimmer

    # system
    hfsprogs

    # automation
    devilspie2
    quicktile-git
)

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
    shfmt

    #
    lua
    lua-penlight
)

AUR_PACKAGES+=(
    demjson
)

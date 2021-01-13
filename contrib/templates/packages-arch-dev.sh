#!/bin/bash
# shellcheck disable=SC2034,SC2207

PAC_REPOS=(
    "sublime-text|\
http://sublimetext.mirror.linacreative.com/arch/stable/\$arch|\
http://sublimetext.mirror.linacreative.com/sublimehq-pub.gpg|\
8A8F901A"
)

PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    offlineimap
    subversion
    zoom

    #
    aurutils
    vifm

    #
    azure-cli
    azure-functions-core-tools-bin
    storageexplorer

    #
    sfdx-cli

    #
    mongodb-bin
    mongodb-tools-bin

    #
    woeusb

    #
    raidar
)

lk_is_virtual || {
    PAC_PACKAGES+=(
        guvcview # Webcam utility
        linssid  # Wi-Fi scanner

        #
        ddcutil
        i2c-tools
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
    # shells
    asciinema
    dash
    ksh
    zsh

    # utilities
    cdrtools #
    cpio     # for libguestfs
    ext4magic
    unison
    wimlib

    # networking
    networkmanager-l2tp
    openconnect

    # monitoring
    atop
    iotop

    # network monitoring
    iftop   # shows network traffic by service and host
    nethogs # groups bandwidth by process ('nettop')
    nload   # shows bandwidth by interface

    # system
    acme.sh
    arch-install-scripts
    at
    base-devel
    binwalk
    cloud-utils
    cronie
    expac
    hwinfo
    mlocate
    stow
    sysfsutils
    ubuntu-keyring
)

AUR_PACKAGES+=(
    aha
    asciicast2gif
    pacman-cleanup-hook
    powershell-bin
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
    gnome-characters
    gnome-font-viewer
    gucharmap
    inkscape
    keepassxc
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
    transmission-cli
    transmission-gtk
    trash-cli

    # because there's always That One Website
    flashplugin

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
    abcde
    audacity
    python-eyed3
    sox

    # multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mkvtoolnix-cli
    mkvtoolnix-gui
    mpv
    openshot
    rtmpdump
    youtube-dl

    # system
    dconf-editor
    displaycal
    fontconfig-docs
    gparted
    guake
    libsecret   # secret-tool
    libva-utils # vainfo
    syslinux
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
    pencil
    skypeforlinux-stable-bin
    spotify
    stretchly-git
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
    autopep8
    bash-language-server
    cloc
    dbeaver
    dbeaver-plugin-sshj
    eslint
    geckodriver
    nodejs-less
    python-pylint
    qcachegrind
    sublime-merge
    sublime-text
    tidy
    ttf-font-awesome
    ttf-ionicons
    uglify-js

    # email
    msmtp     # SMTP client
    msmtp-mta # sendmail alias for msmtp
    s-nail    # mail and mailx commands

    #
    git-filter-repo
    meld

    #
    jdk11-openjdk
    jre11-openjdk

    #
    nodejs
    npm
    yarn

    #
    composer
    php
    php-gd
    php-imagick
    php-imap
    php-intl
    php-memcache
    php-memcached
    php-sqlite
    xdebug

    #
    mysql-python
    python
    python-acme # Let's Encrypt CLI
    python-dateutil
    python-pip
    python-requests
    python-virtualenv
    python2

    #
    shellcheck
    shfmt

    #
    lua
    lua-penlight

    # platforms
    aws-cli
)

AUR_PACKAGES+=(
    demjson
    robo3t-bin
    trickle
    vscodium-bin

    #
    git-cola

    # platforms
    linode-cli
    wp-cli
)

# development services
PAC_PACKAGES+=(
    apache
    mariadb
    php-fpm
)

# VMs and containers
PAC_PACKAGES+=(
    # KVM/QEMU
    dnsmasq
    ebtables
    edk2-ovmf # UEFI firmware
    libguestfs
    libvirt
    qemu
    virt-manager

    #
    docker
)

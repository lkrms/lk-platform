#!/bin/bash

PAC_REPOS=(
    "sublime-text|\
http://sublimetext.mirror/arch/stable/\$arch|\
http://sublimetext.mirror/sublimehq-pub.gpg|\
8A8F901A"
)

PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    ant
    apachedirectorystudio
    geekbench4
    offlineimap
    subversion
    zoom

    #
    displaycal
    xiccd

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
    ! lk_system_has_amd_graphics || {
        PAC_PACKAGES+=(
            clinfo
            libclc
            opencl-mesa
            vulkan-radeon
            vulkan-tools
        )
        AUR_PACKAGES+=(
            rocm-opencl-runtime
        )
    }
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
    fatresize
    partclone
    wimlib

    # networking
    networkmanager-l2tp
    networkmanager-openconnect

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
    youtube-dl

    # system
    dconf-editor
    fontconfig
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
    autopep8
    bash-language-server
    cloc
    dbeaver
    dbeaver-plugin-sshj
    eslint
    geckodriver
    python-pylint
    qcachegrind
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
    php7           # for wp-cli
    php7-gd        #
    php7-imap      #
    php7-intl      #
    php7-memcache  #
    php7-memcached #
    php7-sqlite    #
    php7-xsl       # for phpdoc-phar

    #
    mysql-python
    python
    python-acme     # Let's Encrypt CLI
    python-dateutil #
    python-magic    # for s3cmd
    python-pip
    python-requests
    python-virtualenv
    python-xmlschema
    python2

    #
    shellcheck

    #
    lua
    lua-penlight

    # platforms
    aws-cli
    python-boto
    s3cmd
)

AUR_PACKAGES+=(
    demjson
    lua-posix
    nodejs-less
    nvm
    phpdoc-phar
    robo3t-bin
    sublime-merge
    sublime-text
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
    edk2-ovmf # UEFI firmware
    iptables-nft
    libguestfs
    libvirt
    qemu
    virt-manager

    #
    docker
)

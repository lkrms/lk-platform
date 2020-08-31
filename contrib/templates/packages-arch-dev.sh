#!/bin/bash
# shellcheck disable=SC2034,SC2207

CUSTOM_REPOS=(
    "sublime-text|http://sublimetext.mirror.linacreative.com/arch/stable/\$arch|http://sublimetext.mirror.linacreative.com/sublimehq-pub.gpg|8A8F901A|"
)

PACMAN_PACKAGES=()
AUR_PACKAGES=()

# if installed, won't be marked as a dependency
PAC_KEEP=(
    aurutils

    #
    azure-cli
    sfdx-cli

    #
    mongodb-bin

    #
    woeusb
)

PAC_REMOVE=(
    # buggy and insecure
    xfce4-screensaver

    # vscodium-bin is preferred
    code
    visual-studio-code-bin
)

# hardware-related
lk_is_virtual || {
    PACMAN_PACKAGES+=(
        guvcview # webcam utility
        linssid  # wireless scanner

        # "general-purpose computing on graphics processing units" (GPGPU)
        # required to run GPU benchmarks, e.g. in Geekbench
        clinfo
        $(
            GRAPHICS_CONTROLLERS="$(lspci | grep -E 'VGA|3D')" || return 0
            ! grep -qi "Intel" <<<"$GRAPHICS_CONTROLLERS" ||
                echo "intel-compute-runtime"
            ! grep -qi "NVIDIA" <<<"$GRAPHICS_CONTROLLERS" ||
                echo "opencl-nvidia"
        )
        i2c-tools # provides i2c-dev module (required by ddcutil)
    )

    AUR_PACKAGES+=(
        ddcutil
    )
}

AUR_PACKAGES+=(
    brother-hl5450dn
    brother-hll3230cdw
)

# terminal-based
PACMAN_PACKAGES+=(
    # shells
    asciinema
    dash
    ksh
    zsh

    # utilities
    cdrtools #
    cpio     # libguestfs doesn't work without it
    unison
    wimlib
    yq

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
    acme.sh
    arch-install-scripts
    at
    $(pacman -Sgq base-devel) # TODO: add lk_pacman_group_packages function
    cloud-utils
    cronie
    expac
    hwinfo
    mlocate
    sysfsutils
)

AUR_PACKAGES+=(
    asciicast2gif
    powershell-bin
    vpn-slice
)

# desktop
PACMAN_PACKAGES+=(
    caprine
    chromium
    copyq
    filezilla
    firefox-i18n-en-gb
    flameshot
    freerdp
    ghostwriter
    gucharmap
    inkscape
    keepassxc
    libreoffice-fresh-en-gb
    nextcloud-client
    nomacs
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
    xorg-xev
)

AUR_PACKAGES+=(
    espanso
    masterpdfeditor-free
    pencil
    skypeforlinux-stable-bin
    spotify
    teams
    todoist-electron
    trimage
    ttf-ms-win10
    typora

    # multimedia - video
    makemkv

    # system
    hfsprogs

    # automation
    devilspie2
    quicktile-git
)

# development
PACMAN_PACKAGES+=(
    autopep8
    bash-language-server
    dbeaver
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
    msmtp     # smtp client
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
    python-acme # for working with Let's Encrypt
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
    trickle
    vscodium-bin

    #
    git-cola

    # platforms
    linode-cli
    wp-cli
)

# development services
PACMAN_PACKAGES+=(
    apache
    mariadb
    php-fpm
)

# VMs and containers
PACMAN_PACKAGES+=(
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

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
    expect
    linux-headers
    offlineimap
    stripe-cli
    subversion
    zoom

    #
    displaycal
    xiccd

    #
    mongodb-bin
    mongodb-tools-bin

    #
    powerpanel
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
    # shells
    asciinema
    dash
    ksh
    zsh

    # utilities
    cdrtools
    ext4magic
    fatresize
    partclone

    # networking
    iperf3
    net-tools # for x11vnc
    networkmanager-l2tp
    networkmanager-openconnect

    # system
    acme.sh
    arch-install-scripts
    at
    base-devel
    binwalk
    cloud-utils
    cronie
    expac
    mlocate
    namcap
    stow
    ubuntu-keyring
)

AUR_PACKAGES+=(
    aha
    csvkit
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
    qpdf         # e.g. --underlay
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
    yt-dlp

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
    pencil
    skypeforlinux-stable-bin
    spotify
    stretchly-git
    teams
    teamviewer
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
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

lk_is_bootstrap ||
    AUR_PACKAGES+=(ttf-ms-win10)

# development
PAC_PACKAGES+=(
    autopep8
    babel-cli
    babel-core
    bash-language-server
    cloc
    cmake
    dbeaver
    dbeaver-plugin-sshj
    dbeaver-plugin-sshj-lib
    emscripten
    eslint
    geckodriver
    gobject-introspection
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
    tig

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
    python
    python-acme     # Let's Encrypt CLI
    python-dateutil #
    python-magic    # for s3cmd
    python-mysqlclient
    python-pip
    python-requests
    python-virtualenv
    python-xmlschema
    python2

    #
    perl-tidy

    #
    ruby

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
    babel-preset-env
    demjson
    lua-posix
    nodejs-less
    nvm
    php-sqlsrv
    phpdoc-phar
    ruby-rubocop
    ruby-rubocop-performance
    ruby-rubocop-rails
    standard
    terser
    trickle

    #
    git-cola
    httptoolkit
    robo3t-bin
    sublime-merge
    sublime-text
    vscodium-bin

    # platforms
    azure-cli
    azure-functions-core-tools-bin
    linode-cli
    wp-cli

    #
    storageexplorer
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

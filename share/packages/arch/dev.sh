#!/bin/bash

PAC_REPOS=(
    'sublime-text|http://sublimetext.mirror/arch/stable/$arch|http://sublimetext.mirror/sublimehq-pub.gpg|8A8F901A'
)

PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    ant
    apachedirectorystudio
    expect
    geteltorito # ThinkPad UEFI firmware update conversion
    linux-headers
    offlineimap
    ookla-speedtest-bin
    sfdx-cli
    stretchly-bin
    stripe-cli
    subversion
    teams
    zoom

    #
    falkon # Uses qt5-webengine
    google-chrome
    microsoft-edge-stable-bin

    #
    numix-gtk-theme-git
    ttf-apple-emoji
    xfce-theme-greybird
    zuki-themes

    #
    displaycal
    xiccd

    #
    mongodb-bin
    mongodb-tools-bin

    #
    memtest86-efi
    powerpanel
    raidar
    rasdaemon
)

PAC_NO_REPLACE=(
    stretchly
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
        glmark2
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
    aha
    asciinema
    dash
    ksh
    shfmt

    # Utilities
    cdrtools
    csvkit
    ext4magic
    fatresize
    glances
    partclone
    unison

    # Network
    iperf3
    net-tools # Optional x11vnc dependency
    networkmanager-l2tp
    networkmanager-openconnect
    samba

    # System
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
    pacman-cleanup-hook
    powershell-bin
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
    remmina
    scribus
    simplescreenrecorder
    speedcrunch
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-cli
    transmission-gtk

    # For LibreOffice
    hunspell
    hunspell-en_au
    hyphen
    hyphen-en

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
    python-eyed3
    sox

    # Multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mkvtoolnix-cli
    mkvtoolnix-gui
    mpv
    openshot
    youtube-dl
    yt-dlp

    # System
    dconf-editor
    fontconfig
    gparted
    guake
    libsecret   # Provides secret-tool
    libva-utils # Provides vainfo
    syslinux
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
    clockify-desktop
    emote
    espanso
    libreoffice-extension-languagetool
    masterpdfeditor-free
    pencil
    qpdfview
    rescuetime2
    skypeforlinux-stable-bin
    spotify
    stretchly
    teams-insiders
    teamviewer
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
    typora

    # Multimedia - audio
    abcde

    # Multimedia - video
    makemkv
    video-trimmer

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
    autoconf
    autoconf-archive
    autopep8
    babel-cli
    babel-core
    bash-language-server
    cloc
    cmake
    dbeaver
    emscripten
    eslint
    geckodriver
    gobject-introspection
    gperftools
    graphviz # Optional phpdoc dependency
    imagemagick
    imagemagick-doc
    plantuml # Optional phpdoc dependency
    python-pylint
    qcachegrind
    tidy
    ttf-font-awesome
    ttf-ionicons
    uglify-js

    # Email
    msmtp     # SMTP client
    msmtp-mta # sendmail alias for msmtp
    s-nail    # Provides mail and mailx

    #
    git-filter-repo
    meld
    tig

    #
    jdk11-openjdk
    jre11-openjdk

    #
    nodejs-lts-gallium
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
    php-xsl # Optional phpdoc-phar dependency
    xdebug

    #
    php7
    php7-gd
    php7-imagick
    php7-imap
    php7-intl
    php7-memcache
    php7-memcached
    php7-sqlite
    php7-xsl # Optional phpdoc-phar dependency

    #
    python
    python-acme     # Let's Encrypt CLI
    python-dateutil #
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
    lua-posix

    # Platforms
    aws-cli
    python-boto # Optional linode-cli dependency
    s3cmd
)

AUR_PACKAGES+=(
    babel-preset-env
    nodejs-less
    nvm
    php-ibm_db2
    php-memprof
    php-sqlsrv
    phpdoc-phar
    python-demjson3
    python39 # azure-functions-core-tools-bin dependency
    rollup
    ruby-rubocop
    ruby-rubocop-performance
    ruby-rubocop-rails
    ruby-ruby-debug-ide
    standard
    terser
    trickle-git
    zeal-git

    #
    git-cola
    httptoolkit
    robo3t-bin
    sublime-merge
    sublime-text
    vscodium-bin

    #
    nodejs-generator-code
    vsce

    # Platforms
    azure-cli
    azure-functions-core-tools-bin
    linode-cli
    wp-cli

    #
    storageexplorer
)

# Development services
PAC_PACKAGES+=(
    apache
    mariadb
    php-fpm

    #
    fcgi # Provides cgi-fcgi
)

# VMs and containers
PAC_PACKAGES+=(
    # KVM/QEMU
    dnsmasq
    edk2-ovmf # UEFI firmware
    iptables-nft
    libguestfs
    libvirt
    qemu-desktop
    virt-manager

    #
    docker
)

#!/bin/bash

PAC_REPOS=(
    'sublime-text|http://sublimetext.mirror/arch/stable/$arch|http://sublimetext.mirror/sublimehq-pub.gpg|8A8F901A'
)

PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_EXCEPT=()

PAC_OFFER=(
    ant
    apachedirectorystudio
    expect
    geteltorito # ThinkPad UEFI firmware update conversion
    linux-headers
    offlineimap
    ookla-speedtest-bin
    stretchly-bin
    stripe-cli
    subversion
    zoom

    #
    falkon # Uses qt5-webengine
    google-chrome
    microsoft-edge-stable-bin

    #
    numix-gtk-theme-git
    ttf-apple-emoji
    wiki-loves-earth-wallpapers
    wiki-loves-monuments-wallpapers
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
        glmark2
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
    testssl.sh

    # System
    arch-install-scripts
    at
    base-devel
    binwalk
    certbot
    cloud-utils
    cronie
    mlocate
    namcap
    stow
    ubuntu-keyring
)

AUR_PACKAGES+=(
    asciinema-agg
    dug-git
    gp-saml-gui-git
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
    hexchat
    inkscape
    keepassxc
    libreoffice-fresh
    libreoffice-fresh-en-gb
    nextcloud-client
    remmina
    screenkey
    scribus
    slop
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
    pandoc-cli   # Text conversion (e.g. Markdown to PDF)
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
    sox

    # Multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mkvtoolnix-cli
    mkvtoolnix-gui
    openshot
    yt-dlp

    # System
    dconf-editor
    fontconfig
    gparted
    guake
    libsecret # Provides secret-tool
    syslinux

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
    highlight-pointer
    key-mon
    libreoffice-extension-languagetool
    masterpdfeditor-free
    nomacs
    pencil
    qpdfview
    rescuetime2
    simplescreenrecorder
    skypeforlinux-stable-bin
    spotify
    stretchly
    teams-for-linux
    teamviewer
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
    typora

    # Multimedia - audio
    abcde
    python-eyed3

    # Multimedia - video
    makemkv
    video-trimmer

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
    autoconf
    autoconf-archive
    bash-language-server
    cloc
    cmake
    d-feet
    dbeaver
    emscripten
    eslint
    geckodriver
    gobject-introspection
    gperftools
    graphviz # Optional phpdoc dependency
    imagemagick
    plantuml # Optional phpdoc dependency
    python-black
    python-pylint
    qcachegrind
    tidy
    ttf-font-awesome
    ttf-ionicons

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
    php-memcache
    php-memcached
    php-sodium
    php-sqlite
    php-xsl # Optional phpdoc-phar dependency
    xdebug

    #
    python
    python-acme     # Let's Encrypt CLI
    python-dateutil #
    python-mysqlclient
    python-pip
    python-requests
    python-virtualenv
    python-xmlschema

    #
    perl-tidy

    #
    ruby
    rubocop
    ruby-rubocop-performance

    #
    shellcheck

    #
    lua
    lua-penlight
    lua-posix

    # Platforms
    aws-cli
    github-cli
    python-boto # Optional linode-cli dependency
    s3cmd
)

AUR_PACKAGES+=(
    dotnet-runtime-3.1-bin # storageexplorer dependency
    mongodb50-bin          # Required for legacy 'mongo' command
    msodbcsql
    mssql-tools
    multitime
    nodejs-less
    nvm
    php-humbug-box-bin
    php-ibm_db2
    php-memprof
    php-pcov
    php-sqlsrv
    php74
    php74-bcmath
    php74-cli
    php74-curl
    php74-exif
    php74-fileinfo
    php74-gd
    php74-gettext
    php74-iconv
    php74-imagick
    php74-imap
    php74-intl
    php74-json
    php74-mbstring
    php74-memcache
    php74-memcached
    php74-mysql
    php74-phar
    php74-simplexml
    php74-soap
    php74-sodium
    php74-sqlite
    php74-tokenizer
    php74-xdebug
    php74-xsl # Optional phpdoc-phar dependency
    php74-zip
    phpdoc-phar
    pretty-php
    python-demjson3
    python-pywebview
    python39 # azure-functions-core-tools-bin dependency
    rollup
    ruby-rubocop-rails
    ruby-ruby-debug-ide
    standard
    symfony-console-autocomplete
    terser
    trickle-git
    ts-standard
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
    ovsx
    vsce

    # Platforms
    act # GitHub Action runner
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
    docker-buildx
)

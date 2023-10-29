#!/bin/bash

PAC_REPOS=(
    "sublime-text|\
http://sublimetext.mirror/arch/stable/\$arch|\
8A8F901A|\
http://sublimetext.mirror/sublimehq-pub.gpg"
)

PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_EXCEPT=()

PAC_OFFER=(
    1password
    ant
    apachedirectorystudio
    expect
    geteltorito # ThinkPad UEFI firmware update conversion
    linux-headers
    offlineimap
    ookla-speedtest-bin
    ruby-ronn-ng
    stretchly-bin
    stripe-cli
    subversion
    xfce4-dev-tools
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
    ghostscript   # PDF/PostScript processing
    mupdf-tools   # PDF manipulation
    pandoc-cli    # Text conversion (e.g. Markdown to PDF)
    poppler       # Provides pdfimages
    pstoedit      # PDF/PostScript conversion to vector formats
    qpdf          # PDF manipulation (e.g. add underlay)
    texlive-basic # PDF support for pandoc

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
    sox

    # Multimedia - video
    mkvtoolnix-cli
    mkvtoolnix-gui
    openshot

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
    clementine
    clockify-desktop
    emote
    espanso
    highlight-pointer
    key-mon
    libreoffice-extension-languagetool
    masterpdfeditor-free
    nomacs-git
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
    ffmpeg-full
    handbrake-full
    handbrake-full-cli
    makemkv
    video-trimmer
    yt-dlp-git

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
    imagemagick
    python-black
    python-pylint
    qcachegrind
    tidy
    ttf-font-awesome

    # Email
    msmtp     # SMTP client
    msmtp-mta # sendmail alias for msmtp
    s-nail    # Provides mail and mailx

    #
    git-filter-repo
    meld
    tig

    #
    jdk17-openjdk
    jre17-openjdk

    #
    nodejs
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
    xdebug

    #
    python
    python-acme     # Let's Encrypt CLI
    python-dateutil #
    python-mysqlclient
    python-pip
    python-pipenv
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
    wp-cli
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
    php74-dom
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
    php74-xmlreader
    php74-xmlwriter
    php74-zip
    php80
    php80-bcmath
    php80-cli
    php80-curl
    php80-dom
    php80-exif
    php80-fileinfo
    php80-gd
    php80-gettext
    php80-iconv
    php80-imagick
    php80-imap
    php80-intl
    php80-mbstring
    php80-memcached
    php80-mysql
    php80-phar
    php80-simplexml
    php80-soap
    php80-sodium
    php80-sqlite
    php80-tokenizer
    php80-xdebug
    php80-xmlreader
    php80-xmlwriter
    php80-zip
    php81
    php81-bcmath
    php81-cli
    php81-curl
    php81-dom
    php81-exif
    php81-fileinfo
    php81-gd
    php81-gettext
    php81-iconv
    php81-imagick
    php81-imap
    php81-intl
    php81-mbstring
    php81-mysql
    php81-phar
    php81-simplexml
    php81-soap
    php81-sodium
    php81-sqlite
    php81-tokenizer
    php81-xdebug
    php81-xmlreader
    php81-xmlwriter
    php81-zip
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

    #
    storageexplorer
)

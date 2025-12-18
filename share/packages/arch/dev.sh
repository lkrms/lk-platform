#!/usr/bin/env bash

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
    balena-etcher
    dumpet # i.e. "dump El Torito"
    expect
    geekbench
    geteltorito # ThinkPad UEFI firmware update conversion
    gtk3-demos
    imhex-bin
    linux-headers
    mockoon-bin
    mssql-server
    offlineimap
    ookla-speedtest-bin
    ruby-ronn-ng
    stretchly-bin
    stripe-cli
    subversion
    vscodium-bin
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

lk_system_is_vm || {
    PAC_PACKAGES+=(
        glmark2
        guvcview # Webcam utility
        linssid  # Wi-Fi scanner

        #
        ddcutil
        i2c-tools
    )
    AUR_PACKAGES+=(
        furmark
        geekbench5
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

    # MaxMind GeoIP2 data and tooling
    geoipupdate
    mmdblookup

    # System
    arch-install-scripts
    at
    base-devel
    binwalk
    certbot
    cloud-utils
    cronie
    namcap
    plocate
    stow
    ubuntu-keyring
)

AUR_PACKAGES+=(
    asciinema-agg
    dug-git
    gp-saml-gui-git
    mmdbinspect
    pacman-cleanup-hook
    powershell-bin
    vpn-slice
)

# Desktop
PAC_PACKAGES+=(
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
    remmina
    screenkey
    scribus
    slop
    speech-dispatcher
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-cli
    transmission-gtk
    wireshark-qt

    # For LibreOffice
    hunspell
    hunspell-en_au
    hyphen
    hyphen-en

    # PDF
    ghostscript        # PDF/PostScript processing
    mupdf-tools        # PDF manipulation
    pandoc-cli         # Text conversion (e.g. Markdown to PDF)
    poppler            # Provides pdfimages
    pstoedit           # PDF/PostScript conversion to vector formats
    qpdf               # PDF manipulation (e.g. add underlay)
    texlive-latexextra # PDF support for pandoc
    texlive-fontsextra #
    tesseract          # OCR
    tesseract-data-eng

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
    strawberry

    # Multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mkvtoolnix-cli
    mkvtoolnix-gui
    #openshot
    video-trimmer
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
    caprine
    chromium-widevine
    clockify-desktop
    emote
    espanso-x11
    gtk3-nocsd-git
    highlight-pointer
    key-mon
    libreoffice-extension-languagetool
    masterpdfeditor-free
    nomacs
    pencil
    qpdfview
    render50
    rescuetime2
    simplescreenrecorder
    spotify
    stretchly
    teams-for-linux
    #teamviewer
    todoist-appimage
    trimage
    #ttf-apple-emoji
    ttf-twemoji
    typora

    # Multimedia - audio
    abcde
    python-eyed3

    # Multimedia - video
    bento4
    makemkv

    # System
    hfsprogs

    # Automation
    devilspie2
    quicktile
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
    d-spy
    dbeaver
    emscripten
    eslint
    geckodriver
    ghex
    gobject-introspection
    gperftools
    imagemagick
    mitmproxy
    ollama
    python-black
    python-pylint
    qcachegrind
    tidy
    woff2-font-awesome
    zeal

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

    #
    nodejs
    npm
    nvm
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
    python-pywebview
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
    act # GitHub Action runner
    aws-cli
    azure-cli
    github-cli
    s3cmd
    wp-cli
)

AUR_PACKAGES+=(
    mongodb50-bin # Required for legacy 'mongo' command
    msodbcsql
    mssql-tools
    multitime
    nodejs-less
    osslsigncode
    phive
    php-ibm_db2
    php-memprof
    php-pcov
    php-sqlsrv
    {php74,php80,php81,php82,php83,php84}{,-bcmath,-cli,-ctype,-curl,-dom,-exif,-fileinfo,-gd,-gettext,-iconv,-imagick,-imap,-intl,-mbstring,-mysql,-pcntl,-phar,-posix,-simplexml,-soap,-sodium,-sqlite,-tokenizer,-xdebug,-xmlreader,-xmlwriter,-zip}
    php74-json
    php74-memcached
    php80-memcached
    #php81-memcached
    #php82-memcached
    php83-memcached
    php84-memcached
    pretty-php
    python-demjson3
    python39 # azure-functions-core-tools-bin dependency
    rehex
    rollup
    standard
    symfony-console-autocomplete
    terser
    trickle-git
    ts-standard

    #
    git-cola
    httptoolkit
    robo3t-bin
    sublime-merge
    sublime-text
    visual-studio-code-bin

    #
    nodejs-generator-code
    ovsx
    vsce

    # Platforms
    azure-functions-core-tools-bin
    linode-cli

    #
    storageexplorer
)

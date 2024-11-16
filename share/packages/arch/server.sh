#!/bin/bash

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_EXCEPT=()

PAC_OFFER=(
    # Utilities
    ccache
    expect
    geekbench
    glances
    handbrake-cli
    mkvtoolnix-cli
    offlineimap
    ookla-speedtest-bin
    pacman-cleanup-hook
    plocate
    powershell-bin
    transmission-cli

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

    # Platforms
    aws-cli
    azure-cli
    linode-cli
    s3cmd
    wp-cli

    #
    linux-headers
    r8152-dkms

    # Services
    postfix
    samba
    wide-dhcpv6
    radvd
    znc

    #
    powerpanel

    #
    brother-hl5450dn
    brother-hll3230cdw
)

lk_is_virtual || {
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
        opencl-clover-mesa
        vulkan-radeon
        vulkan-tools
    )
}

PAC_PACKAGES+=(
    # Shell
    asciinema
    dash
    ksh
    shfmt
    zsh

    # Utilities
    certbot
    cloud-utils
    fatresize
    partclone
    stow
    syslinux
    ubuntu-keyring
    unison

    # Networking
    iperf3
    ppp

    # Services
    at
    cronie
    fail2ban

    # Multimedia
    ffmpeg
    rtmpdump
    yt-dlp

    #
    nodejs
    npm
    python
    python-pip
    ruby
)

AUR_PACKAGES+=(
    sqm-scripts

    #
    python-demjson3
    ruby-erubis
)

#!/bin/bash

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    # Utilities
    expect
    geekbench
    glances
    handbrake-cli
    mlocate
    offlineimap
    ookla-speedtest-bin
    pacman-cleanup-hook
    powershell-bin
    transmission-cli

    # PDF
    ghostscript  # PDF/PostScript processing
    mupdf-tools  # PDF manipulation
    pandoc       # Text conversion (e.g. Markdown to PDF)
    poppler      # Provides pdfimages
    pstoedit     # PDF/PostScript conversion to vector formats
    qpdf         # PDF manipulation (e.g. add underlay)
    texlive-core # PDF support for pandoc

    # Platforms
    aws-cli
    azure-cli
    linode-cli
    python-boto # Optional linode-cli dependency
    s3cmd
    wp-cli

    #
    linux-headers
    r8152-dkms

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
        opencl-mesa
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
    acme.sh
    cloud-utils
    expac
    fatresize
    partclone
    stow
    syslinux
    ubuntu-keyring
    unison

    # Networking
    iperf3
    networkmanager-l2tp
    networkmanager-openconnect
    ppp

    # Services
    at
    cronie
    fail2ban

    # Multimedia
    ffmpeg
    rtmpdump
    youtube-dl
    yt-dlp

    #
    nodejs-lts-gallium
    npm
    python
    python-pip
    ruby
)

AUR_PACKAGES+=(
    # Networking
    vpn-slice

    #
    python-demjson3
    ruby-erubis
)

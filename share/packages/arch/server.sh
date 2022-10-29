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
    certbot
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
    nodejs-lts-gallium
    npm
    python
    python-pip
    ruby
)

AUR_PACKAGES+=(
    python-demjson3
    ruby-erubis
)

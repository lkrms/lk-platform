#!/bin/bash

PAC_REPOS=()
PAC_PACKAGES=()
AUR_PACKAGES=()
PAC_REJECT=()

PAC_KEEP=(
    #
    geekbench
    handbrake-cli
    mlocate
    mongodb-bin
    mongodb-tools-bin
    offlineimap
    pacman-cleanup-hook
    powershell-bin
    transmission-cli

    #
    ghostscript
    mupdf-tools
    pandoc
    poppler
    pstoedit
    texlive-core

    #
    aws-cli
    azure-cli
    linode-cli
    python-boto  # for linode-cli
    python-magic # for s3cmd
    s3cmd
    wp-cli

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

PAC_PACKAGES+=(
    # Shells
    asciinema
    dash
    ksh
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

    # Networking
    networkmanager-l2tp
    networkmanager-openconnect

    # Services
    at
    cronie

    # Multimedia
    ffmpeg
    rtmpdump
    youtube-dl

    #
    nodejs
    npm
    python
    python-pip
    ruby
)

AUR_PACKAGES+=(
    # Networking
    vpn-slice

    #
    demjson
    ruby-erubis
)

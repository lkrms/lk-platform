#!/bin/bash

HOMEBREW_TAPS=(
    homebrew/cask
    homebrew/cask-drivers
    homebrew/cask-fonts
    homebrew/cask-versions

    #
    ${HOMEBREW_TAPS[@]+"${HOMEBREW_TAPS[@]}"}
)

# prerequisites
HOMEBREW_FORMULAE=(
    # GNU packages
    coreutils
    findutils
    gawk
    grep
    inetutils
    netcat
    gnu-sed
    gnu-tar
    wget

    # basics
    bash-completion
    byobu
    glances
    htop
    jq
    lftp
    media-info
    ncdu
    nmap
    p7zip
    pv
    rsync

    #
    ${HOMEBREW_FORMULAE[@]+"${HOMEBREW_FORMULAE[@]}"}
)

HOMEBREW_CASKS=(
    iterm2

    #
    ${HOMEBREW_CASKS[@]+"${HOMEBREW_CASKS[@]}"}
)

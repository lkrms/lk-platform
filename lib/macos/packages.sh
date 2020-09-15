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
    gnu-getopt
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
    mas
    media-info
    ncdu
    newt
    nmap
    p7zip
    pv
    python-yq
    rsync

    #
    ${HOMEBREW_FORMULAE[@]+"${HOMEBREW_FORMULAE[@]}"}
)

HOMEBREW_CASKS=(
    iterm2

    #
    ${HOMEBREW_CASKS[@]+"${HOMEBREW_CASKS[@]}"}
)

MAS_APPS=(
    #409183694 # Keynote
    #409203825 # Numbers
    #409201541 # Pages

    #
    ${MAS_APPS[@]+"${MAS_APPS[@]}"}
)

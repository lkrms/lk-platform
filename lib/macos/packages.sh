#!/bin/bash

HOMEBREW_TAPS=(
    homebrew/cask
    homebrew/cask-drivers
    homebrew/cask-fonts
    homebrew/cask-versions

    #
    ${HOMEBREW_TAPS[@]+"${HOMEBREW_TAPS[@]}"}
)

# Prerequisites
HOMEBREW_FORMULAE=(
    # GNU packages
    coreutils
    diffutils
    findutils
    gawk
    gnu-getopt
    grep
    inetutils
    netcat
    gnu-sed
    gnu-tar
    wget

    # Basics
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
    dozer
    iterm2
    mysides

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

HOMEBREW_KEEP_FORMULAE=(
    ocaml

    #
    ${HOMEBREW_KEEP_FORMULAE[@]+"${HOMEBREW_KEEP_FORMULAE[@]}"}
)

HOMEBREW_KEEP_CASKS=(
    zoom

    #
    ${HOMEBREW_KEEP_CASKS[@]+"${HOMEBREW_KEEP_CASKS[@]}"}
)

LOGIN_ITEMS=(
    ${LOGIN_ITEMS[@]+"${LOGIN_ITEMS[@]}"}
)

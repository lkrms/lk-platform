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
    gnu-sed
    gnu-tar
    wget

    # Basics
    bash-completion
    byobu
    glances
    htop
    icdiff
    jq
    lftp
    media-info
    ncdu
    newt
    nmap
    p7zip
    pv
    python-yq
    rsync
    watch

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

HOMEBREW_KEEP_FORMULAE=(
    bash
    bash-completion@2
    gdb

    #
    ${HOMEBREW_KEEP_FORMULAE[@]+"${HOMEBREW_KEEP_FORMULAE[@]}"}
)

HOMEBREW_KEEP_CASKS=(
    ${HOMEBREW_KEEP_CASKS[@]+"${HOMEBREW_KEEP_CASKS[@]}"}
)

FORCE_IBREW=(
    ${FORCE_IBREW[@]+"${FORCE_IBREW[@]}"}
)

LOGIN_ITEMS=(
    ${LOGIN_ITEMS[@]+"${LOGIN_ITEMS[@]}"}
)

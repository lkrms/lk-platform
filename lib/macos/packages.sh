#!/bin/bash

HOMEBREW_TAPS=(
    homebrew/cask
    lkrms/autoupdate

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

    #
    bash-completion
    icdiff
    jq
    newt
    pv
    python-yq
    rsync
    trash

    #
    ${HOMEBREW_FORMULAE[@]+"${HOMEBREW_FORMULAE[@]}"}
)

# Basics
HOMEBREW_FORMULAE+=(
    byobu
    glances
    gnupg
    htop
    lftp
    media-info
    ncdu
    p7zip
    pstree
    watch
)

HOMEBREW_CASKS=(
    #iterm2

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

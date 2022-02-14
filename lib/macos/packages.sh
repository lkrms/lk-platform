#!/bin/bash

HOMEBREW_TAPS=(
    homebrew/cask

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
    inetutils # Provides telnet
    gnu-sed
    gnu-tar
    wget

    #
    bash-completion
    icdiff
    jc
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
    watch
    zenity
)

HOMEBREW_UNLINK_FORMULAE=(
    bash-completion

    #
    ${HOMEBREW_UNLINK_FORMULAE[@]+"${HOMEBREW_UNLINK_FORMULAE[@]}"}
)

HOMEBREW_LINK_KEGS=(
    ${HOMEBREW_LINK_KEGS[@]+"${HOMEBREW_LINK_KEGS[@]}"}
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

    #
    ${HOMEBREW_KEEP_FORMULAE[@]+"${HOMEBREW_KEEP_FORMULAE[@]}"}
)

HOMEBREW_KEEP_CASKS=(
    ${HOMEBREW_KEEP_CASKS[@]+"${HOMEBREW_KEEP_CASKS[@]}"}
)

HOMEBREW_FORCE_INTEL=(
    ${HOMEBREW_FORCE_INTEL[@]+"${HOMEBREW_FORCE_INTEL[@]}"}
)

LOGIN_ITEMS=(
    ${LOGIN_ITEMS[@]+"${LOGIN_ITEMS[@]}"}
)

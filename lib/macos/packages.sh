#!/bin/bash

HOMEBREW_TAPS=(${HOMEBREW_TAPS+"${HOMEBREW_TAPS[@]}"})
HOMEBREW_FORMULAE=(${HOMEBREW_FORMULAE+"${HOMEBREW_FORMULAE[@]}"})
HOMEBREW_CASKS=(${HOMEBREW_CASKS+"${HOMEBREW_CASKS[@]}"})
MAS_APPS=(${MAS_APPS+"${MAS_APPS[@]}"})
HOMEBREW_KEEP_FORMULAE=(${HOMEBREW_KEEP_FORMULAE+"${HOMEBREW_KEEP_FORMULAE[@]}"})
HOMEBREW_KEEP_CASKS=(${HOMEBREW_KEEP_CASKS+"${HOMEBREW_KEEP_CASKS[@]}"})
HOMEBREW_FORCE_INTEL=(${HOMEBREW_FORCE_INTEL+"${HOMEBREW_FORCE_INTEL[@]}"})
LOGIN_ITEMS=(${LOGIN_ITEMS+"${LOGIN_ITEMS[@]}"})

HOMEBREW_TAPS+=(
    homebrew/cask
)

# Prerequisites (replicated in lk-provision-macos.sh)
HOMEBREW_FORMULAE+=(
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
    bash
    bash-completion@2
    flock
    icdiff
    jq
    newt
    pv
    python-yq
    rsync
    trash
)

# Basics
HOMEBREW_FORMULAE+=(
    byobu
    glances
    gnu-time
    gnupg
    htop
    jc
    lftp
    media-info
    ncdu
    p7zip
    watch
    zenity
)

HOMEBREW_CASKS+=(
    iterm2
)

MAS_APPS+=(
    #409183694 # Keynote
    #409203825 # Numbers
    #409201541 # Pages
)

HOMEBREW_KEEP_FORMULAE+=(
)

HOMEBREW_KEEP_CASKS+=(
)

HOMEBREW_FORCE_INTEL+=(
)

LOGIN_ITEMS+=(
)

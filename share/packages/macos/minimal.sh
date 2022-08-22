#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_UNLINK_FORMULAE=()
HOMEBREW_LINK_KEGS=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
HOMEBREW_FORCE_INTEL=()
LOGIN_ITEMS=()

HOMEBREW_TAPS+=(
    homebrew/cask-fonts
)

HOMEBREW_FORMULAE+=(
    qpdf
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    copyq
    firefox
    flameshot
    flycut
    google-chrome
    iterm2
    keepassxc
    keepingyouawake
    the-unarchiver
)

HOMEBREW_KEEP_CASKS+=(
    pdf-expert
    teamviewer
)

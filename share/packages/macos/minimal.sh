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
    homebrew/cask-drivers
    homebrew/cask-fonts
)

HOMEBREW_FORMULAE+=(
    qpdf
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    firefox
    flycut
    google-chrome
    iterm2
    keepassxc
    keepingyouawake
    keyboard-cleaner
    skype
    teamviewer
    the-unarchiver

    # Non-free
    microsoft-office
)

HOMEBREW_KEEP_CASKS+=(
    pdf-expert
)

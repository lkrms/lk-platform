#!/bin/bash

HOMEBREW_TAPS=()
HOMEBREW_FORMULAE=()
HOMEBREW_CASKS=()
MAS_APPS=()
HOMEBREW_KEEP_FORMULAE=()
HOMEBREW_KEEP_CASKS=()
FORCE_IBREW=()
LOGIN_ITEMS=()

HOMEBREW_TAPS+=(
    homebrew/cask-drivers
    homebrew/cask-fonts
)

HOMEBREW_CASKS+=(
    adobe-acrobat-reader
    firefox
    flycut
    google-chrome
    iterm2
    keepassxc
    keepingyouawake
    skype
    teamviewer
    the-unarchiver

    # Non-free
    microsoft-office
)

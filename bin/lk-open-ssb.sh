#!/bin/bash

lk_bin_depth=1 . lk-bash-load.sh || exit

function __usage() {
    cat <<EOF
Open a URL in a dedicated Chromium-based site-specific browser.

Usage:
  ${0##*/} <URL> [CHROMIUM_ARG...]
EOF
}

lk_assert_not_root

HOME=${HOME:-~}

lk_is_uri "${1-}" &&
    [[ $1 =~ ^https?:\/\/([^/]+)(\/.*)?$ ]] ||
    lk_usage

SCOPE=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
SCOPE=${SCOPE//\//_}
[[ ! $SCOPE =~ (.*([^_]|^))_+$ ]] ||
    SCOPE=${BASH_REMATCH[1]}

COMMAND=$(lk_first_command \
    chromium google-chrome-stable google-chrome chrome) ||
    lk_die "Chromium not found"

lk_tty_run "$COMMAND" \
    --user-data-dir="$HOME/.config/$SCOPE" \
    --no-first-run \
    --enable-features=OverlayScrollbar \
    --app="$1" \
    "${@:2}"

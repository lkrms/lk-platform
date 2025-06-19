#!/usr/bin/env bash

lk_bin_depth=1 . lk-bash-load.sh || exit

function __usage() {
    cat <<EOF
Open a URL in a dedicated Chromium-based site-specific browser.

Usage:
  ${0##*/} [options] <URL> [CHROMIUM_ARG...]

Options:
  -e, --no-exec     Don't replace the lk-open-ssb.sh process with Chromium.
EOF
}

lk_assert_not_root

HOME=${HOME:-~}
EXEC=1

lk_getopt "e" "no-exec"
eval "set -- $LK_GETOPT"

while :; do
    OPT=$1
    shift
    case "$OPT" in
    -e | --no-exec)
        EXEC=0
        ;;
    --)
        break
        ;;
    esac
done

lk_is_uri "${1-}" &&
    [[ $1 =~ ^https?:\/\/([^/]+)(\/.*)?$ ]] ||
    lk_usage

SCOPE=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
SCOPE=${SCOPE//\//_}
[[ ! $SCOPE =~ (.*([^_]|^))_+$ ]] ||
    SCOPE=${BASH_REMATCH[1]}

if lk_is_linux; then
    REGEX="^$(lk_ere_escape "$SCOPE")\\."
    if WINDOW_ID=$(wmctrl -lpx |
        awk -v re="${REGEX//\\/\\\\}" '$4 ~ re { print $1; exit }' |
        grep .); then
        wmctrl -i -a "$WINDOW_ID" &&
            exit || true
    fi
fi

COMMAND=$(lk_first_command \
    chromium google-chrome-stable google-chrome chrome) ||
    lk_die "Chromium not found"

ARGS=()
((!EXEC)) || ARGS=(-1 exec)

lk_tty_run ${ARGS+"${ARGS[@]}"} "$COMMAND" \
    --user-data-dir="$HOME/.config/$SCOPE" \
    --no-first-run \
    --enable-features=OverlayScrollbar \
    --app="$1" \
    "${@:2}"

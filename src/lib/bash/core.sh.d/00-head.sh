#!/usr/bin/env bash

# shellcheck disable=SC2034

shopt -s extglob

[[ ${USER-} ]] || USER=$(id -un) || return

# Provide horizontal whitespace patterns known to work everywhere
LK_h=$'[ \t]'
LK_H=$'[^ \t]'

# Collect arguments passed to the current script or function
_LK_ARGV=("$@")

# lk_colour_off
#
# Assign empty strings to colour and formatting variables.
function lk_colour_off() {
    LK_BLACK=
    LK_RED=
    LK_GREEN=
    LK_YELLOW=
    LK_BLUE=
    LK_MAGENTA=
    LK_CYAN=
    LK_WHITE=
    LK_DEFAULT=
    LK_BLACK_BG=
    LK_RED_BG=
    LK_GREEN_BG=
    LK_YELLOW_BG=
    LK_BLUE_BG=
    LK_MAGENTA_BG=
    LK_CYAN_BG=
    LK_WHITE_BG=
    LK_DEFAULT_BG=
    LK_BOLD=
    LK_DIM=
    LK_BOLD_UNDIM=
    LK_DIM_UNBOLD=
    LK_UNBOLD_UNDIM=
    LK_RESET=
    LK_CLEAR_LINE=
    LK_AUTO_WRAP_OFF=
    LK_AUTO_WRAP_ON=

    _LK_COLOUR_ERROR=
    _LK_COLOUR_WARNING=
    _LK_COLOUR_NOTICE=
    _LK_COLOUR_INFO=
    _LK_COLOUR_SUCCESS=
}

# lk_colour_on
#
# Assign ANSI escape sequences to colour and formatting variables.
function lk_colour_on() {
    LK_BLACK=$'\E[30m'
    LK_RED=$'\E[31m'
    LK_GREEN=$'\E[32m'
    LK_YELLOW=$'\E[33m'
    LK_BLUE=$'\E[34m'
    LK_MAGENTA=$'\E[35m'
    LK_CYAN=$'\E[36m'
    LK_WHITE=$'\E[37m'
    LK_DEFAULT=$'\E[39m'
    LK_BLACK_BG=$'\E[40m'
    LK_RED_BG=$'\E[41m'
    LK_GREEN_BG=$'\E[42m'
    LK_YELLOW_BG=$'\E[43m'
    LK_BLUE_BG=$'\E[44m'
    LK_MAGENTA_BG=$'\E[45m'
    LK_CYAN_BG=$'\E[46m'
    LK_WHITE_BG=$'\E[47m'
    LK_DEFAULT_BG=$'\E[49m'
    LK_BOLD=$'\E[1m'
    LK_DIM=$'\E[2m'
    LK_BOLD_UNDIM=$'\E[22;1m'
    LK_DIM_UNBOLD=$'\E[22;2m'
    LK_UNBOLD_UNDIM=$'\E[22m'
    LK_RESET=$'\E[m'
    LK_CLEAR_LINE=$'\E[K'
    LK_AUTO_WRAP_OFF=$'\E[?7l'
    LK_AUTO_WRAP_ON=$'\E[?7h'

    _LK_COLOUR_ERROR=$LK_RED
    _LK_COLOUR_WARNING=$LK_YELLOW
    _LK_COLOUR_NOTICE=$LK_CYAN
    _LK_COLOUR_INFO=$LK_YELLOW
    _LK_COLOUR_SUCCESS=$LK_GREEN
}

# From https://no-color.org/: "Command-line software which adds ANSI color to
# its output by default should check for a NO_COLOR environment variable that,
# when present and not an empty string (regardless of its value), prevents the
# addition of ANSI color."
if [[ ${LK_NO_COLOUR-} ]] || [[ ${NO_COLOR-} ]]; then
    lk_colour_off
else
    lk_colour_on
fi

#### Reviewed: 2025-11-06

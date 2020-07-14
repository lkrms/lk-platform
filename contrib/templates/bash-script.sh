#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015,SC2034

# Adapt the following for scripts that depend on lk-platform's library of Bash
# functions.

set -euo pipefail

lk_die() { echo "${_FILE:+$_FILE: }$1" >&2 && exit 1; }

_FILE="${BASH_SOURCE[0]}" && [ ! -L "$_FILE" ] &&
    _DIR="$(cd "${_FILE%/*}" && pwd -P)" ||
    lk_die "unable to resolve path to script"

# If _DIR is not required, replace the command above with:
#_FILE="${BASH_SOURCE[0]}"

[ -d "${LK_BASE:-}" ] || { [ -f "/etc/default/lk-platform" ] &&
    . "/etc/default/lk-platform" && [ -d "${LK_BASE:-}" ]; } ||
    lk_die "LK_BASE not set"

include= . "$LK_BASE/lib/bash/common.sh"

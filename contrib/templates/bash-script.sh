#!/bin/bash
# shellcheck disable=SC1007,SC1090,SC2015,SC2034

# Adapt the following for scripts that depend on lk-platform's library of Bash
# functions.

set -euo pipefail

_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && false || exit $s; }

# Remove if _DIR is not required
[ ! -L "$_FILE" ] && _DIR="$(cd "${_FILE%/*}" && pwd -P)" ||
    lk_die "unable to resolve path to script"

# More robust alternative to the above (don't use both)
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "realpath: command not found"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} ||
    lk_die "unable to resolve path to script"

[ -d "${LK_BASE:-}" ] || { [ -f "/etc/default/lk-platform" ] &&
    . "/etc/default/lk-platform" && [ -d "${LK_BASE:-}" ]; } ||
    lk_die "LK_BASE not set"

include= . "$LK_BASE/lib/bash/common.sh"

#!/usr/bin/env bash

# Adapt the following for scripts that depend on lk-platform's library of Bash
# functions.

set -euo pipefail
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }

##
# Remove if _DIR is not required
[ "${_FILE%/*}" != "$_FILE" ] || _FILE=./$_FILE
[ ! -L "$_FILE" ] &&
    _DIR="$(cd "${_FILE%/*}" && pwd -P)" ||
    lk_die "unable to resolve path to script"
#
##

##
# More robust alternative to the above (don't use both)
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} ||
    lk_die "unable to resolve path to script"
#
##

[ -d "${LK_BASE-}" ] || { [ -f "/etc/default/lk-platform" ] &&
    . "/etc/default/lk-platform" && [ -d "${LK_BASE-}" ]; } ||
    lk_die "LK_BASE not set"

. "$LK_BASE/lib/bash/common.sh"

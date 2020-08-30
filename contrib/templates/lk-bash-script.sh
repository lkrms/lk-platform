#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2034

# To use this as a template for lk-platform scripts:
#   1. Choose Option 1 or Option 2 below (recommended reading:
#      https://mywiki.wooledge.org/BashFAQ/028)
#   2. Set _DEPTH to the number of directories between LK_BASE and the script
#
# Alternatively, use:
#   depth=DEPTH [include=LIBRARY...] . lk-bash-load.sh || exit

##
# Option 1:
#   - Only uses builtins, but fails if BASH_SOURCE[0] or its parents are
#     symlinks (LK_BASE and its parents may be symlinks)
#   - Recommended for scenarios where coreutils may not be installed
#
# Notes:
#   - Line 3 returns false with "BASH_SOURCE[0]: unbound variable" if the script
#     isn't running from a source file
#   - Line 5 ensures "${_FILE%/*}" doesn't expand to "$_FILE" if BASH_SOURCE[0]
#     has no directory component
#   - The command substitution in lines 6-9 returns false if BASH_SOURCE[0] or
#     its parents are symbolic links
#
set -euo pipefail
_DEPTH=2
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && false || exit $s; }
[ "${_FILE%/*}" != "$_FILE" ] || _FILE=./$_FILE
LK_BASE=$(i=0 && F=$_FILE && while [ $((i++)) -le "$_DEPTH" ]; do
    [ "$F" != / ] && [ ! -L "$F" ] &&
        cd "${F%/*}" && F=$PWD || exit
done && pwd -P) || lk_die "symlinks in path are not supported"
[ -d "$LK_BASE/lib/bash" ] || lk_die "unable to locate LK_BASE"
export LK_BASE
#
##

##
# Option 2:
#   - Fails unless `realpath` or `python` are available, but has robust support
#     for symlinks
#   - Recommended unless there's a reason not to rely on GNU coreutils
#
# Notes:
#   - As above, line 3 returns false if the script isn't running from a source
#     file
#   - Line 9 uses _DIR to locate LK_BASE by adding one "/.." per directory
#     specified by _DEPTH
#
set -euo pipefail
_DEPTH=2
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && false || exit $s; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "realpath: command not found"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval "printf '/..%.s' {1..$_DEPTH}")") &&
    [ "$LK_BASE" != / ] && [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE
#
##

include='' . "$LK_BASE/lib/bash/common.sh"

PARAM=
PARAM1=
PARAM2=
FLAG=0
VALUE="0"
SETTING="auto"

USAGE="\
Usage:
  ${0##*/} [OPTION...] PARAM
  ${0##*/} [OPTION...] PARAM1 PARAM2

Provide a boilerplate for Bash scripts that parse options with getopt.

Options:
  -f, --flag            set a flag
  -v, --value VALUE     set a value (default: $VALUE)
  -s, --setting[=SETTING]
                        enable a setting and provide an optional value
                        (default: $SETTING)"

OPTS="$(
    gnu_getopt --options "fv:s::" \
        --longoptions "flag,value:,setting::" \
        --name "${0##*/}" \
        -- "$@"
)" || lk_usage
eval "set -- $OPTS"

while :; do
    OPT="$1"
    shift
    case "$OPT" in
    -f | --flag)
        FLAG=1
        ;;
    -v | --value)
        VALUE="$1"
        ;;&
    -s | --setting)
        SETTING="${1:-$SETTING}"
        ;;&
    --)
        break
        ;;
    *)
        shift
        ;;
    esac
done

case "$#" in
1)
    PARAM="$1"
    ;;
2)
    PARAM1="$1"
    PARAM2="$2"
    ;;
*)
    lk_usage
    ;;
esac

declare -p \
    FLAG \
    VALUE \
    SETTING \
    PARAM \
    PARAM1 \
    PARAM2

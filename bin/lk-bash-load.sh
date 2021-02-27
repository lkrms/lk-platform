#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2128

# Scenario 1: bootstrapping lk-platform scripts
#
# If a platform script can safely assume lk-bash-load.sh will be found in PATH,
# the following can be used to set LK_BASE and load Bash libraries, where DEPTH
# is the number of directories between LK_BASE and the script:
#
#     lk_bin_depth=DEPTH [include=LIBRARY...] . lk-bash-load.sh || exit
#
# If lk_bin_depth is set, LK_BASE will be determined from the invoking script's
# pathname, regardless of lk-bash-load.sh's location.
#
# Scenario 2: sourcing lk-platform as a dependency in other Bash scripts
#
# Assuming lk-platform is installed and lk-bash-load.sh can be found in PATH
# whenever the script is invoked (via symlink if needed), this is a convenient
# method for using lk-platform's Bash functions elsewhere:
#
#     [include=LIBRARY...] . lk-bash-load.sh || exit
#

set -euo pipefail
lk_die() { s=$? && echo "$BASH_SOURCE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"

function _lk_bash_load() {
    local _DEPTH=${lk_bin_depth:-} _FILE _DIR
    if [ -n "$_DEPTH" ]; then
        [ -n "${BASH_SOURCE[2]:-}" ] ||
            lk_die "not sourced from a shell script"
        _FILE=${BASH_SOURCE[2]}
    else
        _DEPTH=1
        _FILE=${BASH_SOURCE[0]}
    fi
    _FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
        LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
        [ -d "$LK_BASE/lib/bash" ] ||
        lk_die "unable to locate LK_BASE"
    export LK_BASE
}

export -n BASH_XTRACEFD SHELLOPTS
[ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)

_lk_bash_load &&
    unset -f _lk_bash_load &&
    . "$LK_BASE/lib/bash/common.sh"

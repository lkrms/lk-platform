#!/bin/bash
# shellcheck disable=SC1090,SC2030,SC2031

# If a script can safely assume that lk-bash-load.sh will be found in PATH, use
# the following to set LK_BASE and load Bash libraries, where DEPTH is the
# number of directories between LK_BASE and the script:
#
#   depth=DEPTH [include=LIBRARY...] . lk-bash-load.sh || exit
#
# The value of LK_BASE is always based on the invoking script's pathname, so
# lk-bash-load.sh itself can be installed anywhere. It should not be given
# execute permissions.

set -euo pipefail

function lk_bash_load() {
    local SH
    SH=$(
        lk_die() { s=$? && echo "lk-bash-load.sh: $1" >&2 && false || exit $s; }
        [ -n "${BASH_SOURCE[2]:-}" ] ||
            lk_die "not sourced from a shell script"
        FILE=${BASH_SOURCE[2]}
        [ -n "${depth:-}" ] ||
            lk_die "depth: variable not set"
        if ! type -P realpath >/dev/null; then
            if type -P python >/dev/null; then
                function realpath() {
                    python -c \
                        "import os,sys;print(os.path.realpath(sys.argv[1]))" \
                        "$1"
                }
            else
                lk_die "realpath: command not found"
            fi
        fi
        FILE=$(realpath "$FILE") &&
            DIR=${FILE%/*} &&
            LK_BASE=$(realpath "$DIR$(
                [ "$depth" -lt 1 ] ||
                    eval "printf '/..%.s' {1..$depth}"
            )") &&
            [ "$LK_BASE" != / ] &&
            [ -f "$LK_BASE/bin/lk-bash-load.sh" ] ||
            lk_die "unable to locate LK_BASE"
        printf 'export LK_BASE=%q' "$LK_BASE"
    ) || return
    eval "$SH"
    . "$LK_BASE/lib/bash/common.sh"
}

lk_bash_load

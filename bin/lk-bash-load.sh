#!/bin/bash

# shellcheck disable=SC1090,SC2030,SC2031

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

function lk_bash_load() {
    local SH
    SH=$(
        lk_die() { s=$? && echo "lk-bash-load.sh: $1" >&2 &&
            (return $s) && false || exit; }
        VARS=()
        if [ -n "${lk_bin_depth:-}" ]; then
            [ -n "${BASH_SOURCE[2]:-}" ] ||
                lk_die "not sourced from a shell script"
            FILE=${BASH_SOURCE[2]}
        else
            [ -n "${BASH_SOURCE[2]:-}" ] ||
                VARS+=(LK_NO_SOURCE_FILE 1)
            lk_bin_depth=1
            FILE=${BASH_SOURCE[0]}
        fi
        if [ -z "${LK_BASE:-}" ]; then
            if ! type -P realpath >/dev/null; then
                if type -P python >/dev/null; then
                    function realpath() {
                        python -c \
                            "import os,sys;print(os.path.realpath(sys.argv[1]))" \
                            "$1"
                    }
                else
                    lk_die "command not found: realpath"
                fi
            fi
            FILE=$(realpath "$FILE") &&
                DIR=${FILE%/*} &&
                LK_BASE=$(realpath "$DIR$(
                    [ "$lk_bin_depth" -lt 1 ] ||
                        eval "printf '/..%.s' {1..$lk_bin_depth}"
                )") &&
                [ "$LK_BASE" != / ] &&
                [ -f "$LK_BASE/bin/lk-bash-load.sh" ] ||
                lk_die "unable to locate LK_BASE"
        fi
        VARS+=(LK_BASE "$LK_BASE")
        printf '%s=%q\n' "${VARS[@]}"
        echo "export LK_BASE"
    ) || return
    eval "$SH"
}

_LK_ENV=${_LK_ENV:-$(declare -x)}

lk_bash_load &&
    . "$LK_BASE/lib/bash/common.sh"

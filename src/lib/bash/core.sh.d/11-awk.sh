#!/bin/bash

# lk_awk_load VAR SCRIPT
#
# Locate an awk script, creating it if necessary, and assign its path to VAR.
#
# At build time, calls to `lk_awk_load` serve as script insertion points and
# must therefore appear first in a self-contained line of code.
#
# This is acceptable, for example:
#
#     lk_awk_load FILE sh-sanitise-quoted-pathname || return
#
# But these are not:
#
#     lk_awk_load FILE sh-sanitise-quoted-pathname ||
#         return
#
#     [[ -z ${PATHS-} ]] ||
#         { lk_awk_load FILE sh-sanitise-quoted-pathname; }
#
# <LK_BASE>/lib/awk/<SCRIPT>.awk must exist at build time.
function lk_awk_load() {
    local _IN=0
    [[ $1 != -i ]] || { _IN=1 && shift; }
    unset -v "$1" || lk_warn "invalid variable: $1" || return
    local _FILE=${LK_BASE+$LK_BASE/lib/awk/$2.awk}
    [[ ! -f $_FILE ]] || {
        # Avoid SIGPIPE
        ((!_IN)) || cat >/dev/null
        eval "$1=\$_FILE"
        return
    }
    ((_IN)) || lk_warn "file not found: $_FILE" || return
    lk_mktemp_with "$1" cat
}

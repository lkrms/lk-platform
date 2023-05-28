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
    _lk_script_load "$1" "${LK_BASE+$LK_BASE/lib/awk/$2.awk}" ${3+"$3"}
}

# lk_perl_load VAR SCRIPT
#
# Equivalent to lk_awk_load, but for Perl scripts.
#
# <LK_BASE>/lib/perl/<SCRIPT>.pl must exist at build time.
function lk_perl_load() {
    _lk_script_load "$1" "${LK_BASE+$LK_BASE/lib/perl/$2.pl}" ${3+"$3"}
}

# _lk_script_load VAR SCRIPT_PATH [-]
function _lk_script_load() {
    unset -v "$1" || lk_err "invalid variable: $1" || return
    [[ ! -f $2 ]] || {
        # Avoid SIGPIPE
        [[ -z ${3-} ]] || cat >/dev/null
        eval "$1=\$2"
        return
    }
    [[ -n ${3-} ]] || lk_err "file not found: $2" || return
    lk_mktemp_with "$1" cat
}

#!/bin/bash

# _lk_log_install_file FILE
#
# If the parent directory of FILE doesn't exist, create it with mode 01777,
# using root privileges if necessary. Then, if FILE doesn't exist or isn't
# writable, create it or change its permissions and ownership as needed.
function _lk_log_install_file() {
    if [[ -f $1 ]] && [[ -w $1 ]]; then
        return
    fi
    local GID
    if [[ ! -e $1 ]]; then
        local DIR=${1%"${1##*/}"}
        [[ -d ${DIR:=$PWD} ]] ||
            lk_elevate -f install -d -m 01777 "$DIR" || return
        GID=$(id -g) &&
            lk_elevate -f install -m 00600 -o "$EUID" -g "$GID" /dev/null "$1"
    else
        lk_elevate -f chmod 00600 "$1" || return
        [[ -w $1 ]] ||
            { GID=$(id -g) &&
                lk_elevate chown "$EUID:$GID" "$1"; }
    fi
}

# lk_log_migrate_legacy FILE
function lk_log_migrate_legacy() {
    local OUT_FILE=${1%.log}.out
    [[ -f $1 ]] && [[ -f $OUT_FILE ]] || return 0
    sed -E 's/^(\.\.|!!)//' "$OUT_FILE" >"$1" &&
        touch -r "$OUT_FILE" "$1" &&
        rm -f "$OUT_FILE"
}

# lk_log
#
# For each line of input, add a microsecond-resolution timestamp and remove
# characters before any carriage returns that aren't part of the line ending.
function lk_log() {
    local PL DELETE=
    lk_perl_load PL log || return
    [[ $PL != "${LK_MKTEMP_WITH_LAST-}" ]] || DELETE=1
    exec perl "$PL" ${DELETE:+--self-delete}
}

#!/bin/bash

# _lk_log_install_file FILE
#
# If the parent directory of FILE doesn't exist, use root privileges to create
# it with file mode 01777. Then, if FILE doesn't exist or isn't writable, create
# it or change its permissions and ownership as needed.
function _lk_log_install_file() {
    if [[ ! -f $1 ]] || [[ ! -w $1 ]]; then
        if [[ ! -e $1 ]]; then
            local DIR=${1%"${1##*/}"} GID
            [[ -d ${DIR:=$PWD} ]] ||
                lk_elevate install -d -m 01777 "$DIR" || return
            GID=$(id -g) &&
                lk_elevate -f \
                    install -m 00600 -o "$UID" -g "$GID" /dev/null "$1"
        else
            lk_elevate -f chmod 00600 "$1" || return
            [ -w "$1" ] ||
                lk_elevate chown "$UID" "$1"
        fi
    fi
}

# lk_log
#
# For each line of input, add a microsecond-resolution timestamp and remove
# characters before any carriage returns that aren't part of the line ending.
function lk_log() {
    local PL
    lk_perl_load PL log || return
    exec perl -p "$PL"
}

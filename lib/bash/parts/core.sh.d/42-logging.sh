#!/bin/bash

function _lk_log_install_file() {
    local GID
    if [ ! -w "$1" ]; then
        if [ ! -e "$1" ]; then
            local LOG_DIR=${1%${1##*/}}
            [ -d "${LOG_DIR:=$PWD}" ] ||
                install -d -m 00755 "$LOG_DIR" 2>/dev/null ||
                sudo install -d -m 01777 "$LOG_DIR" || return
            install -m 00600 /dev/null "$1" 2>/dev/null ||
                { GID=$(id -g) &&
                    sudo install -m 00600 -o "$UID" -g "$GID" /dev/null "$1"; }
        else
            chmod 00600 "$1" 2>/dev/null ||
                sudo chmod 0600 "$1" || return
            [ -w "$1" ] ||
                sudo chown "$UID" "$1"
        fi
    fi
}

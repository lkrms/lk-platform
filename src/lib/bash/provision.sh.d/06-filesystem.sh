#!/usr/bin/env bash

# lk_symlink_bin TARGET [ALIAS]
#
# Add a symbolic link to TARGET from /usr/local/bin if writable, ~/.local/bin
# otherwise.
#
# TARGET may be an absolute path, or a command to find in PATH. ALIAS defaults
# to the basename of TARGET. It may also be an absolute path.
function lk_symlink_bin() {
    (($#)) || lk_bad_args || return
    set -- "$1" "${2:-${1##*/}}"
    local TARGET=$1 ALIAS=${2##*/} BIN=${2%/*} LN V= STATUS
    [[ $2 == /* ]] ||
        { BIN=${LK_BIN_DIR:-/usr/local/bin} &&
            { [[ -w $BIN ]] || lk_will_elevate; }; } ||
        BIN=~/.local/bin
    LN=$BIN/$ALIAS
    if [[ $1 == /* ]]; then
        [[ -f $1 ]] || lk_v -r 2 lk_warn "file not found: $1" || return
    else
        local _PATH=:$PATH:
        # Don't search in BIN if the target and symlink have the same basename
        [[ ${1##*/} != "$ALIAS" ]] || _PATH=${_PATH//":$BIN:"/:}
        # Don't search in ~ unless BIN is in ~
        [[ ${BIN#~} != "$BIN" ]] || _PATH=$(sed -E \
            "s/:$(lk_sed_escape ~)(\\/[^:]*)?:/:/g" <<<"$_PATH") || return
        TARGET=$(PATH=${_PATH:1:${#_PATH}-2} type -P "$1") ||
            lk_v -r 2 lk_warn "command not found: $1" || return
    fi
    lk_symlink "$TARGET" "$LN" &&
        return || STATUS=$?
    lk_is_v 2 || unset V
    [[ ! -L $LN ]] || [[ -f $LN ]] ||
        lk_sudo rm -f${V+v} -- "$LN" || true
    return "$STATUS"
}

#### Reviewed: 2022-10-30

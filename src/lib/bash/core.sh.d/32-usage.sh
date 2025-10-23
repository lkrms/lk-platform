#!/usr/bin/env bash

# _lk_usage_format <CALLER>
function _lk_usage_format() {
    set -- "$(lk_sed_escape "${1-}")" \
        "$(lk_sed_escape_replace "$LK_BOLD")" \
        "$(lk_sed_escape_replace "$LK_RESET")"
    sed -E "
# Print the command name in bold
s/^($LK_h*([uU]sage:|[oO]r:)?$LK_h+(sudo )?)($1)($LK_h|\$)/\1$2\4$3\5/
# Print all-caps headings in bold
s/^[A-Z0-9][A-Z0-9 ]*\$/$2&$3/
# Remove leading backslashes
s/^\\\\(.)/\\1/"
}

# _lk_usage <CALLER> [USAGE]
function _lk_usage() {
    if [[ -n ${2+1} ]]; then
        echo "$2"
    elif [[ $(type -t __usage) == "function" ]]; then
        __usage
    elif [[ -n ${1:+1} ]] &&
        [[ $(type -t "_$1_usage") =~ ^(function|file)$ ]]; then
        "_$1_usage" "$1"
    else
        echo "${LK_USAGE:-$1: invalid arguments}"
    fi
}

# _lk_version <CALLER>
function _lk_version() {
    if [[ $(type -t __version) == "function" ]]; then
        __version
    elif [[ -n ${1:+1} ]] &&
        [[ $(type -t "_$1_version") =~ ^(function|file)$ ]]; then
        "_$1_version" "$1"
    elif [[ -n ${LK_VERSION:+1} ]]; then
        echo "$LK_VERSION"
    else
        false || lk_err "no version defined: ${1-}"
    fi
}

# lk_usage [-e <ERROR_MESSAGE>]... [USAGE]
#
# Print a usage message and exit non-zero with the most recent exit status or 1.
# If running interactively, return non-zero instead of exiting. If -e is set,
# print "<CALLER>: <ERROR_MESSAGE>" as an error before the usage message.
#
# The usage message is taken from one of the following:
# 1. USAGE parameter
# 2. output of `__usage` (if `__usage` is a function)
# 3. output of `_<CALLER>_usage <CALLER>` (if `_<CALLER>_usage` is a function or
#    disk file)
# 4. LK_USAGE variable (deprecated)
function lk_usage() {
    local STATUS=$? CALLER
    ((STATUS)) || STATUS=1
    CALLER=$(lk_caller_name) || CALLER=bash
    while [ "${1-}" = -e ]; do
        lk_tty_error "$LK_BOLD$CALLER$LK_RESET: $2"
        shift 2
    done
    _lk_usage "$CALLER" "$@" |
        _lk_usage_format "$CALLER" >&"${_LK_FD-2}" || true
    if [[ $- != *i* ]]; then
        exit "$STATUS"
    else
        return "$STATUS"
    fi
}

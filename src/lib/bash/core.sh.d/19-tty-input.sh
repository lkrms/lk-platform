#!/bin/bash

function _lk_tty_prompt() {
    unset IFS
    PREFIX=" :: "
    PROMPT=${_PROMPT[*]}
    _lk_tty_format_readline -b PREFIX "${_LK_TTY_COLOUR-$_LK_COLOUR}" _LK_TTY_PREFIX_COLOUR
    _lk_tty_format_readline -b PROMPT "" _LK_TTY_MESSAGE_COLOUR
    echo "$PREFIX$PROMPT "
}

function lk_tty_pause() {
    local REPLY
    read -rsp "${1:-Press return to continue . . . }"
    lk_tty_print
}

# lk_tty_read PROMPT NAME [DEFAULT [READ_ARG...]]
function lk_tty_read() {
    [ $# -ge 2 ] || lk_usage "\
Usage: $FUNCNAME PROMPT NAME [DEFAULT [READ_ARG...]]" || return
    local IFS
    unset IFS
    if lk_no_input && [ -n "${3:+1}" ]; then
        eval "$2=\$3"
    else
        local _PROMPT=("$1")
        [ -z "${3:+1}" ] || _PROMPT+=("[$3]")
        IFS= read -rep "$(_lk_tty_prompt)" "${@:4}" "$2" 2>&"${_LK_FD-2}" || return
        [ -n "${!2}" ] || eval "$2=\${3-}"
    fi
}

# lk_tty_read_silent PROMPT NAME [READ_ARG...]
function lk_tty_read_silent() {
    local IFS
    unset IFS
    lk_tty_read "${@:1:2}" "" -s "${@:3}"
    lk_tty_print
}

# lk_tty_read_password LABEL NAME
function lk_tty_read_password() {
    local _PASSWORD
    [ $# -eq 2 ] || lk_usage "Usage: $FUNCNAME LABEL NAME" || return
    while :; do
        lk_tty_read_silent \
            "Password for $LK_BOLD$1$LK_RESET:" "$2" || return
        [ -n "${!2}" ] ||
            lk_warn "password cannot be empty" || continue
        lk_tty_read_silent \
            "Password for $LK_BOLD$1$LK_RESET (again):" _PASSWORD || return
        [ "$_PASSWORD" = "${!2}" ] ||
            lk_warn "passwords do not match" || continue
        break
    done
}

# lk_tty_yn PROMPT [DEFAULT [READ_ARG...]]
function lk_tty_yn() {
    [ $# -ge 1 ] || lk_usage "\
Usage: $FUNCNAME PROMPT [DEFAULT [READ_ARG...]]" || return
    local YES="[yY]([eE][sS])?" NO="[nN][oO]?"
    if lk_no_input && [[ ${2-} =~ ^($YES|$NO)$ ]]; then
        [[ $2 =~ ^$YES$ ]]
    else
        local IFS _PROMPT=("$1") DEFAULT= PROMPT REPLY
        unset IFS
        if [[ ${2-} =~ ^$YES$ ]]; then
            _PROMPT+=("[Y/n]")
            DEFAULT=Y
        elif [[ ${2-} =~ ^$NO$ ]]; then
            _PROMPT+=("[y/N]")
            DEFAULT=N
        else
            _PROMPT+=("[y/n]")
        fi
        PROMPT=$(_lk_tty_prompt)
        while :; do
            IFS= read -rep "$PROMPT" "${@:3}" REPLY 2>&"${_LK_FD-2}" || return
            [ -n "$REPLY" ] || REPLY=$DEFAULT
            [[ ! $REPLY =~ ^$YES$ ]] || return 0
            [[ ! $REPLY =~ ^$NO$ ]] || return 1
        done
    fi
}

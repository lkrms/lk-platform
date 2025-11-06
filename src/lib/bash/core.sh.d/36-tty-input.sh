#!/usr/bin/env bash

# _lk_tty_format_readline [-b] VAR [COLOUR COLOUR_VAR]
function _lk_tty_format_readline() {
    _LK_TTY_B=$'\x01' _LK_TTY_E=$'\x02' _lk_tty_format "$@"
}

function _lk_tty_prompt() {
    PREFIX=" :: "
    PROMPT=${_PROMPT[*]}
    _lk_tty_format_readline -b PREFIX "${_LK_TTY_COLOUR-$_LK_COLOUR}" _LK_TTY_PREFIX_COLOUR
    _lk_tty_format_readline -b PROMPT "" _LK_TTY_MESSAGE_COLOUR
    echo "$PREFIX$PROMPT "
}

# lk_tty_pause [MESSAGE [READ_ARG...]]
function lk_tty_pause() {
    local IFS=$' \t\n' REPLY
    read -rsp "${1:-Press return to continue . . . }" "${@:2}" REPLY 2>&"${_LK_FD-2}"
    lk_tty_print
}

# lk_tty_read [-NOTE] PROMPT NAME [DEFAULT [READ_ARG...]]
function lk_tty_read() {
    local IFS=$' \t\n' _NOTE
    [[ ${1-} != -* ]] || { _NOTE=${1#-} && shift; }
    (($# > 1)) && unset -v "$2" || lk_bad_args || return
    ! lk_no_input || [[ -z ${3:+1} ]] || {
        eval "$2=\$3"
        return
    }
    local _PROMPT=("$1")
    [[ -z ${_NOTE:+1} ]] || _PROMPT+=("$LK_DIM($_NOTE)$LK_UNBOLD_UNDIM")
    [[ -z ${3:+1} ]] || _PROMPT+=("[$3]")
    IFS= read -rep "$(_lk_tty_prompt)" "${@:4}" "$2" 2>&"${_LK_FD-2}" || return
    [[ -n ${!2:+1} ]] || eval "$2=\${3-}"
}

# lk_tty_read_silent [-NOTE] PROMPT NAME [READ_ARG...]
function lk_tty_read_silent() {
    local IFS=$' \t\n' _NOTE
    [[ ${1-} != -* ]] || { _NOTE=${1#-} && shift; }
    (($# > 1)) && unset -v "$2" || lk_bad_args || return
    lk_tty_read ${_NOTE:+"-$_NOTE"} "${@:1:2}" "" -s "${@:3}"
    lk_tty_print
}

# lk_tty_read_password LABEL NAME
function lk_tty_read_password() {
    (($# == 2)) || lk_bad_args || return
    local _PASSWORD
    while :; do
        lk_tty_read_silent \
            "Password for $LK_BOLD$1$LK_RESET:" "$2" || return
        [[ -n ${!2:+1} ]] ||
            lk_warn "password cannot be empty" || continue
        lk_tty_read_silent \
            "Password for $LK_BOLD$1$LK_RESET (again):" _PASSWORD || return
        [[ -z ${!2#"$_PASSWORD"} ]] ||
            lk_warn "passwords do not match" || continue
        break
    done
}

# lk_tty_yn [-NOTE] PROMPT [DEFAULT [READ_ARG...]]
function lk_tty_yn() {
    local IFS=$' \t\n' NOTE
    [[ ${1-} != -* ]] || { NOTE=${1#-} && shift; }
    (($#)) || lk_bad_args || return
    local _Y="[yY]([eE][sS])?" _N="[nN][oO]?"
    ! lk_no_input || [[ ! ${2-} =~ ^($_Y|$_N)$ ]] || {
        [[ $2 =~ ^$_Y$ ]]
        return
    }
    local _PROMPT=("$1") DEFAULT PROMPT REPLY
    [[ -z ${NOTE:+1} ]] || _PROMPT+=("$LK_DIM($NOTE)$LK_UNBOLD_UNDIM")
    if [[ ${2-} =~ ^$_Y$ ]]; then
        _PROMPT+=("[Y/n]")
        DEFAULT=Y
    elif [[ ${2-} =~ ^$_N$ ]]; then
        _PROMPT+=("[y/N]")
        DEFAULT=N
    else
        _PROMPT+=("[y/n]")
    fi
    PROMPT=$(_lk_tty_prompt)
    while :; do
        IFS= read -rep "$PROMPT" "${@:3}" REPLY 2>&"${_LK_FD-2}" || return
        [[ -n ${REPLY:+1} ]] || REPLY=${DEFAULT-}
        [[ ! $REPLY =~ ^$_Y$ ]] || return 0
        [[ ! $REPLY =~ ^$_N$ ]] || return 1
    done
}

# lk_tty_ynav [-NOTE] ANSWER_NAME PROMPT [DEFAULT [READ_ARG...]]
function lk_tty_ynav() {
    local IFS=$' \t\n' NOTE
    [[ ${1-} != -* ]] || { NOTE=${1#-} && shift; }
    (($# > 1)) || lk_bad_args || return
    local _Y="[yY]([eE][sS])?" _N="[nN][oO]?" \
        _A="[aA]([lL][wW][aA][yY][sS])?" _V="([vV]|[nN][eE][vV][eE][rR])" \
        FILE=${XDG_CONFIG_HOME:-~/.config}/lk-platform/answers ANSWER DEFAULT
    ANSWER=$([[ ! -e $FILE ]] ||
        awk -F= -v "answer=$(lk_lower $1)" -v "regex=^($_Y|$_N|$_A|$_V)\$" \
            'tolower($1)==answer&&$2~regex{print$2;exit}' "$FILE") || ANSWER=
    DEFAULT=${ANSWER:-${3-}}
    [[ -z $ANSWER ]] &&
        { ! lk_no_input || [[ ! $DEFAULT =~ ^($_Y|$_N|$_A|$_V)$ ]]; } || {
        [[ $DEFAULT =~ ^($_Y|$_A)$ ]]
        return
    }
    local _PROMPT=("$2") PROMPT REPLY
    [[ -z ${NOTE:+1} ]] || _PROMPT+=("$LK_DIM($NOTE)$LK_UNBOLD_UNDIM")
    if [[ $DEFAULT =~ ^$_Y$ ]]; then
        _PROMPT+=("[Y/n/a/v]")
        DEFAULT=Y
    elif [[ $DEFAULT =~ ^$_N$ ]]; then
        _PROMPT+=("[y/N/a/v]")
        DEFAULT=N
    elif [[ $DEFAULT =~ ^$_A$ ]]; then
        _PROMPT+=("[y/n/A/v]")
        DEFAULT=A
    elif [[ $DEFAULT =~ ^$_V$ ]]; then
        _PROMPT+=("[y/n/a/V]")
        DEFAULT=V
    else
        _PROMPT+=("[y/n/a/v]")
    fi
    PROMPT=$(_lk_tty_prompt)
    while :; do
        IFS= read -rep "$PROMPT" "${@:4}" REPLY 2>&"${_LK_FD-2}" || return
        [[ -n ${REPLY:+1} ]] || REPLY=${DEFAULT-}
        [[ ! $REPLY =~ ^$_Y$ ]] || return 0
        [[ ! $REPLY =~ ^$_N$ ]] || return 1
        [[ ! $REPLY =~ ^$_A$ ]] || { REPLY=Y && break; }
        [[ ! $REPLY =~ ^$_V$ ]] || { REPLY=N && break; }
    done
    { [[ -d ${FILE%/*} ]] || install -d "${FILE%/*}"; } &&
        { [[ -e $FILE ]] || touch "$FILE"; } &&
        (lk_mktemp_with ANSWERS \
            awk -F= -v "answer=$(lk_lower $1)" -v "reply=$REPLY" -v OFS== \
            'tolower($1)==answer{next}{print}END{print answer,reply;exit}' "$FILE" &&
            cp "$ANSWERS" "$FILE") || true
    [[ $REPLY == Y ]]
}

#### Reviewed: 2022-09-16

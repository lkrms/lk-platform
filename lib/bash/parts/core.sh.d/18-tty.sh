#!/bin/bash

# _lk_tty_format [-b] VAR [COLOUR COLOUR_VAR]
function _lk_tty_format() {
    local _BOLD _STRING _COLOUR_SET _COLOUR _B=${_LK_TTY_B-} _E=${_LK_TTY_E-}
    unset _BOLD
    [ "${1-}" != -b ] || { _BOLD=1 && shift; }
    [ $# -gt 0 ] &&
        _STRING=${!1-} &&
        _COLOUR_SET=${3:+${!3+1}} || return
    if [ -n "$_COLOUR_SET" ]; then
        _COLOUR=${!3}
    else
        _COLOUR=${2-}
        [ -z "${_BOLD:+$LK_BOLD}" ] ||
            [[ $_COLOUR$_STRING == *$LK_BOLD* ]] ||
            _COLOUR+=$LK_BOLD
    fi
    [ -z "${_STRING:+${_COLOUR:+$LK_RESET}}" ] || {
        _STRING=$_B$_COLOUR$_E${_STRING//"$LK_RESET"/$_B$LK_RESET$_COLOUR$_E}$_B$LK_RESET$_E
        eval "$1=\$_STRING"
    }
}

# _lk_tty_format_readline [-b] VAR [COLOUR COLOUR_VAR]
function _lk_tty_format_readline() {
    _LK_TTY_B=$'\x01' _LK_TTY_E=$'\x02' \
        _lk_tty_format "$@"
}

# lk_tty_path [PATH...]
#
# For each PATH or input line, replace $HOME with ~ and remove $PWD.
function lk_tty_path() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_tty_path
    else
        while IFS= read -r _PATH; do
            __PATH=$_PATH
            [ "$_PATH" = "${_PATH#~}" ] || __PATH="~${_PATH#~}"
            [ "$PWD" = / ] || [ "$PWD" = "$_PATH" ] ||
                [ "$_PATH" = "${_PATH#$PWD/}" ] || __PATH=${_PATH#$PWD/}
            printf '%s\n' "$__PATH"
        done
    fi
}

function lk_tty_columns() {
    local _COLUMNS
    _COLUMNS=${_LK_TTY_COLUMNS:-${COLUMNS:-${TERM:+$(TERM=$TERM tput cols)}}} ||
        _COLUMNS=
    echo "${_COLUMNS:-120}"
}

function lk_tty_length() {
    lk_strip_non_printing "$1" | awk 'NR == 1 { print length() }'
}

# lk_tty_print [MESSAGE [MESSAGE2 [COLOUR]]]
#
# Write each message to the file descriptor set in _LK_FD or to the standard
# error output. Print a prefix in bold with colour, then MESSAGE in bold unless
# it already contains bold formatting, then MESSAGE2 in colour. If COLOUR is
# specified, override the default prefix and MESSAGE2 colour.
#
# Output can be customised by setting the following variables:
# - _LK_TTY_PREFIX: message prefix (default: "==> ")
# - _LK_TTY_ONE_LINE: if enabled and MESSAGE has no newlines, the first line of
#   MESSAGE2 will be printed on the same line as MESSAGE, and any subsequent
#   lines will be aligned with the first (values: 0 or 1; default: 0)
# - _LK_TTY_INDENT: MESSAGE2 indent (default: based on prefix length and message
#   line counts)
# - _LK_TTY_COLOUR: default colour for prefix and MESSAGE2 (default: $LK_CYAN)
# - _LK_TTY_PREFIX_COLOUR: override prefix colour
# - _LK_TTY_MESSAGE_COLOUR: override MESSAGE colour
# - _LK_TTY_COLOUR2: override MESSAGE2 colour
function lk_tty_print() {
    [ $# -gt 0 ] || {
        echo >&"${_LK_FD-2}"
        return
    }
    local MESSAGE=${1-} MESSAGE2=${2-} COLOUR=${3-$_LK_TTY_COLOUR} IFS SPACES \
        PREFIX=${_LK_TTY_PREFIX-==> } NEWLINE=0 NEWLINE2=0 SEP=$'\n' INDENT=0
    unset IFS
    [[ $MESSAGE != *$'\n'* ]] || {
        SPACES=$'\n'$(printf "%${#PREFIX}s")
        MESSAGE=${MESSAGE//$'\n'/$SPACES}
        NEWLINE=1
        # _LK_TTY_ONE_LINE only makes sense when MESSAGE prints on one line
        local _LK_TTY_ONE_LINE=0
    }
    [ -z "${MESSAGE2:+1}" ] || {
        [[ $MESSAGE2 != *$'\n'* ]] || NEWLINE2=1
        MESSAGE2=${MESSAGE2#$'\n'}
        case "${_LK_TTY_ONE_LINE-0}$NEWLINE$NEWLINE2" in
        *00 | 1??)
            # If MESSAGE and MESSAGE2 are one-liners or _LK_TTY_ONE_LINE is set,
            # print both messages on the same line with a space between them
            SEP=" "
            ! ((NEWLINE2)) || INDENT=$(lk_tty_length "$MESSAGE.")
            ;;
        *01)
            # If MESSAGE2 spans multiple lines, align it to the left of MESSAGE
            INDENT=$((${#PREFIX} - 2))
            ;;
        *)
            # Align MESSAGE2 to the right of MESSAGE if both span multiple
            # lines or MESSAGE2 is a one-liner
            INDENT=$((${#PREFIX} + 2))
            ;;
        esac
        INDENT=${_LK_TTY_INDENT:-$INDENT}
        SPACES=$'\n'$(printf "%$((INDENT > 0 ? INDENT : 0))s")
        MESSAGE2=$SEP$MESSAGE2
        MESSAGE2=${MESSAGE2//$'\n'/$SPACES}
    }
    _lk_tty_format -b PREFIX "$COLOUR" _LK_TTY_PREFIX_COLOUR
    _lk_tty_format -b MESSAGE "" _LK_TTY_MESSAGE_COLOUR
    [ -z "${MESSAGE2:+1}" ] ||
        _lk_tty_format MESSAGE2 "$COLOUR" _LK_TTY_COLOUR2
    echo "$PREFIX$MESSAGE$MESSAGE2" >&"${_LK_FD-2}"
}

# lk_tty_detail MESSAGE [MESSAGE2 [COLOUR]]
function lk_tty_detail() {
    _LK_TTY_PREFIX=${_LK_TTY_PREFIX-   -> } \
        _LK_TTY_COLOUR=$LK_YELLOW \
        _LK_TTY_MESSAGE_COLOUR=${_LK_TTY_MESSAGE_COLOUR-} \
        lk_tty_print "$@"
}

# - lk_tty_list [- [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
# - lk_tty_list [ARRAY [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
function lk_tty_list() {
    local _ARRAY=${1:--} _MESSAGE=${2-List:} _SINGLE _PLURAL _COLOUR \
        _PREFIX=${_LK_TTY_PREFIX-==> } _ITEMS _INDENT _LIST
    [ $# -ge 2 ] || {
        _SINGLE=item
        _PLURAL=items
    }
    _COLOUR=${3-$_LK_TTY_COLOUR}
    [ $# -le 3 ] || {
        _SINGLE=${3-}
        _PLURAL=${4-}
        _COLOUR=${5-$_LK_TTY_COLOUR}
    }
    if [ "$_ARRAY" = - ]; then
        [ ! -t 0 ] && lk_mapfile _ITEMS ||
            lk_warn "no input" || return
    else
        _ARRAY="${_ARRAY}[@]"
        _ITEMS=(${!_ARRAY+"${!_ARRAY}"}) || return
    fi
    if [[ $_MESSAGE != *$'\n'* ]]; then
        _INDENT=$((${#_PREFIX} - 2))
    else
        _INDENT=$((${#_PREFIX} + 2))
    fi
    _INDENT=${_LK_TTY_INDENT:-$_INDENT}
    _LIST=$([ -z "${_ITEMS+1}" ] ||
        printf '%s\n' "${_ITEMS[@]}")
    ! lk_command_exists column expand ||
        _LIST=$(COLUMNS=$(($(lk_tty_columns) - _INDENT)) column <<<"$_LIST" |
            expand) || return
    echo "$(
        _LK_FD=1
        _LK_TTY_PREFIX=$_PREFIX \
            lk_tty_print "$_MESSAGE" $'\n'"$_LIST" "$_COLOUR"
        [ -z "${_SINGLE:+${_PLURAL:+1}}" ] ||
            _LK_TTY_PREFIX=$(printf "%$((_INDENT > 0 ? _INDENT : 0))s") \
                lk_tty_detail "($(lk_plural -v _ITEMS "$_SINGLE" "$_PLURAL"))"
    )" >&"${_LK_FD-2}"
}

#### Reviewed: 2021-10-04

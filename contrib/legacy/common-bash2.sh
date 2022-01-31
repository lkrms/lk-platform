#!/bin/bash

function lk_realpath() {
    local FILE=$1 i=0 COMPONENT LN RESOLVED=
    [ -e "$FILE" ] || return
    [ "${FILE:0:1}" = / ] || FILE=${PWD%/}/$FILE
    while [ -n "$FILE" ]; do
        ((i++)) || {
            # 1. Replace "/./" with "/"
            # 2. Replace subsequent "/"s with one "/"
            # 3. Remove trailing "/"
            FILE=$(sed \
                -e 's/\/\.\//\//g' \
                -e 's/\/\+/\//g' \
                -e 's/\/$//' <<<"$FILE") || return
            FILE=${FILE:1}
        }
        COMPONENT=${FILE%%/*}
        [ "$COMPONENT" != "$FILE" ] ||
            FILE=
        FILE=${FILE#*/}
        case "$COMPONENT" in
        '' | .)
            continue
            ;;
        ..)
            RESOLVED=${RESOLVED%/*}
            continue
            ;;
        esac
        RESOLVED=$RESOLVED/$COMPONENT
        [ ! -L "$RESOLVED" ] || {
            LN=$(readlink "$RESOLVED") || return
            [ "${LN:0:1}" = / ] || LN=${RESOLVED%/*}/$LN
            FILE=$LN${FILE:+/$FILE}
            RESOLVED=
            i=0
        }
    done
    echo "$RESOLVED"
}

function lk_in_array() {
    eval "printf '%s\n' \${$2+\"\${$2[@]}\"}" |
        # On some legacy systems, `grep -F` fails with "conflicting matchers
        # specified"
        fgrep -x -- "$1" >/dev/null
}

function lk_log() {
    perl -pe '$| = 1;
BEGIN {
    use POSIX qw{strftime};
    use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );
s/.*\r(.)/\1/;'
}

function lk_plural() {
    local VALUE=
    [ "${1-}" != -v ] || { VALUE="$2 " && shift; }
    [ "$1" -eq 1 ] && echo "$VALUE$2" || echo "$VALUE$3"
}

function lk_echo_args() {
    [ $# -eq 0 ] || printf '%s\n' "$@"
}

function lk_echo_array() {
    eval "lk_echo_args \${$1[@]+\"\${$1[@]}\"}"
}

function lk_tty_print() {
    local MESSAGE2=
    [ -z "${2:+1}" ] ||
        MESSAGE2=$LK_RESET${_LK_TTY_COLOUR2-${_LK_TTY_COLOUR-$LK_CYAN}}$(
            [[ $2 != *$'\n'* ]] &&
                echo " $2" ||
                echo $'\n'"${2#$'\n'}"
        )
    echo "\
$LK_BOLD${_LK_TTY_COLOUR-$LK_CYAN}${_LK_TTY_PREFIX-==> }\
$LK_RESET${_LK_TTY_MESSAGE_COLOUR-$LK_BOLD}\
$(sed "1b
s/^/${_LK_TTY_SPACES-  }/" <<<"$1$MESSAGE2")$LK_RESET" >&2
}

function lk_tty_detail() {
    local _LK_TTY_PREFIX=" -> " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR=$LK_YELLOW _LK_TTY_MESSAGE_COLOUR=
    lk_tty_print "$1" "${2-}"
}

function lk_tty_list_detail() {
    lk_tty_detail \
        "$1" "$(COLUMNS=${COLUMNS+$((COLUMNS - 4))} column | expand)"
}

function lk_tty_log() {
    local _LK_TTY_PREFIX=" :: " _LK_TTY_SPACES="    " \
        _LK_TTY_COLOUR2=${_LK_TTY_COLOUR2-$LK_BOLD}
    lk_tty_print "${_LK_TTY_COLOUR-$LK_CYAN}$1" "${2-}"
}

function lk_tty_success() {
    _LK_TTY_COLOUR=$LK_GREEN lk_tty_log "$@"
}

function lk_tty_warning() {
    local EXIT_STATUS=$?
    _LK_TTY_COLOUR=$LK_YELLOW lk_tty_log "$@"
    return "$EXIT_STATUS"
}

function lk_tty_error() {
    local EXIT_STATUS=$?
    _LK_TTY_COLOUR=$LK_RED lk_tty_log "$@"
    return "$EXIT_STATUS"
}

function lk_mapfile() {
    local _LINE
    eval "$1=()"
    while IFS= read -r _LINE || [ -n "$_LINE" ]; do
        eval "$1[\${#$1[@]}]=\$_LINE"
    done <"$2"
}

LK_BOLD=$'\E[1m'
LK_RED=$'\E[31m'
LK_GREEN=$'\E[32m'
LK_YELLOW=$'\E[33m'
LK_CYAN=$'\E[36m'
LK_RESET=$'\E[m'

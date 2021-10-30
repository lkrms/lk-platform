#!/bin/bash

# _lk_tty_format [-b] VAR [COLOUR COLOUR_VAR]
#
# If COLOUR_VAR is not unset, use its value to set the default appearance of
# text in VAR. Otherwise, use COLOUR as the default, adding bold if -b is set
# unless $LK_BOLD already appears in COLOUR or the text.
function _lk_tty_format() {
    local _BOLD= _STRING _COLOUR_SET _COLOUR _B=${_LK_TTY_B-} _E=${_LK_TTY_E-}
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
    local HOME=${HOME:-~}
    _lk_stream_args 6 awk -v "home=$HOME" -v "pwd=$PWD" '
home && index($0, home) == 1 {
    $0 = "~" substr($0, length(home) + 1) }
pwd != "/" && pwd != $0 && index($0, pwd "/") == 1 {
    $0 = substr($0, length(pwd) + 2) }
{ print }' "$@"
}

function lk_tty_columns() {
    local _COLUMNS
    _COLUMNS=${_LK_COLUMNS:-${COLUMNS:-${TERM:+$(TERM=$TERM tput cols)}}} ||
        _COLUMNS=
    echo "${_COLUMNS:-120}"
}

function lk_tty_length() {
    lk_strip_non_printing "$1" | awk 'NR == 1 { print length() }'
}

function _lk_tty_margin_apply() {
    local _COLUMNS
    # Avoid recursion when `stty columns` triggers SIGWINCH
    [ "$FUNCNAME" = "${FUNCNAME[1]-}" ] ||
        # Skip initial adjustment if it's already been applied
        [ "$_RESIZED-$2" = 1-start ] ||
        { { [ "$2" != resize ] || _RESIZED=1; } &&
            _COLUMNS=$(stty size <"$_TTY" |
                awk -v "margin=$1" '{print $2 - margin}') &&
            stty columns "$_COLUMNS" <"$_TTY"; }
}

function _lk_tty_margin_clear() {
    _lk_tty_margin_apply "-$1" end
}

function _lk_tty_margin_add() {
    local _R=$'\r'
    if ((_MARGIN > 0)); then
        _SPACES=$(printf "%${_MARGIN}s")
        "$@" \
            > >(LC_ALL=C sed -Eu "s/(^|($_R)(.))/\2$_SPACES\3/") \
            2> >(LC_ALL=C sed -Eu "s/(^|($_R)(.))/\2$_SPACES\3/" >&2)
    else
        "$@"
    fi
}

# lk_tty_add_margin MARGIN [lk_faketty] COMMAND [ARG...]
#
# Run COMMAND and add MARGIN spaces before each line of output, trapping
# SIGWINCH and using stty to adjust the reported terminal size.
function lk_tty_add_margin() { (
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    [ $# -gt 1 ] && ((_MARGIN = $1)) ||
        lk_err "invalid arguments" || eval "$_lk_x_return"
    shift
    ((_MARGIN > 0)) && _TTY=$(lk_get_tty) || {
        _lk_tty_margin_add "$@"
        eval "$_lk_x_return"
    }
    _RESIZED=
    _CLEAR_SH="trap - SIGWINCH; _lk_tty_margin_clear $_MARGIN"
    _SIGNAL=$(kill -L SIGWINCH) &&
        trap "_lk_tty_margin_apply $_MARGIN resize" SIGWINCH &&
        _lk_tty_margin_apply "$_MARGIN" start &&
        trap "$_CLEAR_SH" EXIT || eval "$_lk_x_return"
    # Run the command in the background because only the foreground process
    # receives SIGWINCH, but remain interactive by redirecting terminal input to
    # the background process
    _INPUT=/dev/tty
    [ "$_TTY" = /dev/tty ] && [ -t 0 ] || _INPUT=/dev/stdin
    _lk_tty_margin_add "$@" <"$_INPUT" &
    # Pass Ctrl+C to the background process
    trap "kill -SIGINT $! 2>/dev/null || true" SIGINT
    # Kill the background process if the foreground process is killed
    trap "kill $! 2>/dev/null || true; $_CLEAR_SH" EXIT
    while :; do
        STATUS=0
        wait || STATUS=$?
        # Continue if interrupted by SIGWINCH
        [ "$STATUS" -eq $((128 + _SIGNAL)) ] || break
    done
    (exit "$STATUS")
    eval "$_lk_x_return"
); }

# lk_tty_group [[-n] MESSAGE [MESSAGE2 [COLOUR]]]
function lk_tty_group() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local NEST=
    [ "${1-}" != -n ] || { NEST=1 && shift; }
    _LK_TTY_GROUP=$((${_LK_TTY_GROUP:--1} + 1))
    [ -n "${_LK_TTY_NEST+1}" ] || _LK_TTY_NEST=()
    unset "_LK_TTY_NEST[_LK_TTY_GROUP]"
    [ $# -eq 0 ] || {
        lk_tty_print "$@"
        _LK_TTY_NEST[_LK_TTY_GROUP]=$NEST
    }
    eval "$_lk_x_return"
}

# lk_tty_group_end [COUNT]
function lk_tty_group_end() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_TTY_GROUP=$((${_LK_TTY_GROUP:-0} - ${1:-1}))
    ((_LK_TTY_GROUP > -1)) || unset _LK_TTY_GROUP _LK_TTY_NEST
    eval "$_lk_x_return"
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
# - _LK_COLOUR: default colour of prefix and MESSAGE2 (default: LK_CYAN)
# - _LK_ALT_COLOUR: default colour of prefix and MESSAGE2 for nested messages
#   and output from lk_tty_detail, lk_tty_list_detail, etc. (default: LK_YELLOW)
# - _LK_TTY_COLOUR: override prefix and MESSAGE2 colour
# - _LK_TTY_PREFIX_COLOUR: override prefix colour (supersedes _LK_TTY_COLOUR)
# - _LK_TTY_MESSAGE_COLOUR: override MESSAGE colour
# - _LK_TTY_COLOUR2: override MESSAGE2 colour (supersedes _LK_TTY_COLOUR)
function lk_tty_print() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    # Print a blank line and return if nothing was passed
    [ $# -gt 0 ] || {
        echo >&"${_LK_FD-2}"
        eval "$_lk_x_return"
    }
    # If nested grouping is active and lk_tty_print isn't already in its own
    # call stack, bump lk_tty_print -> lk_tty_detail and lk_tty_detail ->
    # _lk_tty_detail2
    [ -z "${_LK_TTY_GROUP-}" ] ||
        [ -z "${_LK_TTY_NEST[_LK_TTY_GROUP]-}" ] ||
        [ "${FUNCNAME[2]-}" = "$FUNCNAME" ] || {
        local FUNC
        case "${FUNCNAME[1]-}" in
        _lk_tty_detail2) ;;
        lk_tty_*detail) FUNC=_lk_tty_detail2 ;;
        *) FUNC=lk_tty_detail ;;
        esac
        [ -z "${FUNC-}" ] || {
            "$FUNC" "$@"
            eval "$_lk_x_return"
        }
    }
    local MESSAGE=${1-} MESSAGE2=${2-} \
        COLOUR=${3-${_LK_TTY_COLOUR-$_LK_COLOUR}} \
        PREFIX=${_LK_TTY_PREFIX-${_LK_TTY_PREFIX1-==> }} \
        IFS MARGIN SPACES NEWLINE=0 NEWLINE2=0 SEP=$'\n' INDENT=0
    unset IFS
    MARGIN=$(printf "%$((${_LK_TTY_GROUP:-0} * 4))s")
    [[ $MESSAGE != *$'\n'* ]] || {
        SPACES=$'\n'$(printf "%${#PREFIX}s")
        MESSAGE=${MESSAGE//$'\n'/$SPACES$MARGIN}
        NEWLINE=1
        # _LK_TTY_ONE_LINE only makes sense when MESSAGE prints on one line
        local _LK_TTY_ONE_LINE=0
    }
    [ -z "${MESSAGE2:+1}" ] || {
        [[ $MESSAGE2 != *$'\n'* ]] || NEWLINE2=1
        MESSAGE2=${MESSAGE2#$'\n'}
        case "${_LK_TTY_ONE_LINE-0}${MESSAGE:+2}$NEWLINE$NEWLINE2" in
        *00 | 1* | ???)
            # If MESSAGE and MESSAGE2 are one-liners, _LK_TTY_ONE_LINE is set,
            # or MESSAGE is empty, print both messages on the same line with a
            # space between them and align MESSAGE2 with itself
            SEP=" "
            ((!NEWLINE2)) || { [ -z "${MESSAGE:+1}" ] &&
                INDENT=${#PREFIX} ||
                INDENT=$((${#PREFIX} + $(lk_tty_length "$MESSAGE."))); }
            ;;
        *01)
            # If MESSAGE2 spans multiple lines, align it to the left of MESSAGE
            INDENT=$((${#PREFIX} - 2))
            ;;
        *)
            # Align MESSAGE2 to the right of MESSAGE if both span multiple lines
            # or MESSAGE2 is a one-liner
            INDENT=$((${#PREFIX} + 2))
            ;;
        esac
        INDENT=${_LK_TTY_INDENT:-$INDENT}
        SPACES=$'\n'$(printf "%$((INDENT > 0 ? INDENT : 0))s")
        MESSAGE2=${MESSAGE:+$SEP}$MESSAGE2
        MESSAGE2=${MESSAGE2//$'\n'/$SPACES$MARGIN}
    }
    _lk_tty_format -b PREFIX "$COLOUR" _LK_TTY_PREFIX_COLOUR
    _lk_tty_format -b MESSAGE "" _LK_TTY_MESSAGE_COLOUR
    [ -z "${MESSAGE2:+1}" ] ||
        _lk_tty_format MESSAGE2 "$COLOUR" _LK_TTY_COLOUR2
    echo "$MARGIN$PREFIX$MESSAGE$MESSAGE2" >&"${_LK_FD-2}"
    eval "$_lk_x_return"
}

# lk_tty_detail MESSAGE [MESSAGE2 [COLOUR]]
function lk_tty_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local _LK_TTY_COLOUR_ORIG=${_LK_COLOUR-}
    _LK_TTY_PREFIX1=${_LK_TTY_PREFIX2- -> } \
        _LK_COLOUR=${_LK_ALT_COLOUR-} \
        _LK_TTY_MESSAGE_COLOUR=${_LK_TTY_MESSAGE_COLOUR-} \
        lk_tty_print "$@"
    eval "$_lk_x_return"
}

function _lk_tty_detail2() {
    _LK_TTY_PREFIX1=${_LK_TTY_PREFIX3-  - } \
        _LK_COLOUR=${_LK_TTY_COLOUR_ORIG-$_LK_COLOUR} \
        _LK_TTY_MESSAGE_COLOUR=${_LK_TTY_MESSAGE_COLOUR-} \
        lk_tty_print "$@"
}

# - lk_tty_list [- [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
# - lk_tty_list [ARRAY [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
function lk_tty_list() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local _ARRAY=${1:--} _MESSAGE=${2-List:} _SINGLE _PLURAL _COLOUR \
        _PREFIX=${_LK_TTY_PREFIX-${_LK_TTY_PREFIX1-==> }} \
        _ITEMS _INDENT _COLUMNS _LIST
    [ $# -ge 2 ] || {
        _SINGLE=item
        _PLURAL=items
    }
    _COLOUR=3
    [ $# -le 3 ] || {
        _SINGLE=${3-}
        _PLURAL=${4-}
        _COLOUR=5
    }
    if [ "$_ARRAY" = - ]; then
        [ ! -t 0 ] && lk_mapfile _ITEMS ||
            lk_err "no input" || eval "$_lk_x_return"
    else
        _ARRAY="${_ARRAY}[@]"
        _ITEMS=(${!_ARRAY+"${!_ARRAY}"}) || eval "$_lk_x_return"
    fi
    if [[ $_MESSAGE != *$'\n'* ]]; then
        _INDENT=$((${#_PREFIX} - 2))
    else
        _INDENT=$((${#_PREFIX} + 2))
    fi
    _INDENT=${_LK_TTY_INDENT:-$_INDENT}
    _COLUMNS=$(($(lk_tty_columns) - _INDENT - ${_LK_TTY_GROUP:-0} * 4))
    _LIST=$([ -z "${_ITEMS+1}" ] ||
        printf '%s\n' "${_ITEMS[@]}")
    ! lk_command_exists column expand ||
        _LIST=$(COLUMNS=$((_COLUMNS > 0 ? _COLUMNS : 0)) \
            column <<<"$_LIST" | expand) || eval "$_lk_x_return"
    echo "$(
        _LK_FD=1
        ${_LK_TTY_COMMAND:-lk_tty_print} \
            "$_MESSAGE" $'\n'"$_LIST" ${!_COLOUR+"${!_COLOUR}"}
        [ -z "${_SINGLE:+${_PLURAL:+1}}" ] ||
            _LK_TTY_PREFIX=$(printf "%$((_INDENT > 0 ? _INDENT : 0))s") \
                lk_tty_detail "($(lk_plural -v _ITEMS "$_SINGLE" "$_PLURAL"))"
    )" >&"${_LK_FD-2}"
    eval "$_lk_x_return"
}

# - lk_tty_list_detail [- [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
# - lk_tty_list_detail [ARRAY [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
function lk_tty_list_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_list "$@"
    eval "$_lk_x_return"
}

# lk_tty_dump OUTPUT MESSAGE1 MESSAGE2 COLOUR OUTPUT_COLOUR COMMAND [ARG...]
#
# Print OUTPUT between MESSAGE1 and MESSAGE2. If OUTPUT is empty or "-", then:
# - if COMMAND is specified, run COMMAND and stream its output; or
# - if no COMMAND is specified, stream from standard input.
#
# Because all arguments are optional, COLOUR arguments are ignored if empty. Use
# _LK_TTY_COLOUR and _LK_TTY_OUTPUT_COLOUR to specify an empty colour for COLOUR
# and OUTPUT_COLOUR respectively.
function lk_tty_dump() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local _MESSAGE1=${2-} _MESSAGE2=${3-} _INDENT _CMD \
        _COLOUR=${_LK_TTY_OUTPUT_COLOUR-${_LK_TTY_MESSAGE_COLOUR-${5-}}}
    unset LK_TTY_DUMP_STATUS
    _lk_tty_format -b _MESSAGE1
    _lk_tty_format -b _MESSAGE2
    _INDENT=$((${_LK_TTY_INDENT:-0} + ${_LK_TTY_GROUP:-0} * 4))
    ((_INDENT > 0)) && _CMD=(lk_tty_add_margin "$_INDENT") || unset _CMD
    _LK_TTY_PREFIX1=${_LK_TTY_PREFIX1->>> } \
        _LK_TTY_PREFIX2=${_LK_TTY_PREFIX2- >> } \
        _LK_TTY_PREFIX3=${_LK_TTY_PREFIX3-  > } \
        ${_LK_TTY_COMMAND:-lk_tty_print} "" "$_MESSAGE1" ${4:+"$4"}
    {
        [ -z "${_COLOUR:+1}" ] || printf '%s' "$_COLOUR"
        case "$#-${1+${#1}${1:0:1}}" in
        [6-9]-1- | [6-9]-0 | [1-9][0-9]*-1- | [1-9][0-9]*-0)
            (unset IFS && shift 5 && ${_CMD+"${_CMD[@]}"} "$@") ||
                LK_TTY_DUMP_STATUS=$?
            ;;
        0- | *-1- | *-0)
            if [ -t 0 ]; then
                lk_err "input is a terminal"
                false
            else
                ${_CMD+"${_CMD[@]}"} cat
            fi
            ;;
        *)
            ${_CMD+"${_CMD[@]}"} cat <<<"${1%$'\n'}"
            ;;
        esac || eval "$_lk_x_return"
        printf '%s' "$LK_RESET"
    } >&"${_LK_FD-2}"
    _LK_TTY_PREFIX1=${_LK_TTY_SUFFIX1-<<< } \
        _LK_TTY_PREFIX2=${_LK_TTY_SUFFIX2- << } \
        _LK_TTY_PREFIX3=${_LK_TTY_SUFFIX3-  < } \
        ${_LK_TTY_COMMAND:-lk_tty_print} "" "$_MESSAGE2" ${4:+"$4"}
    eval "$_lk_x_return"
}

# lk_tty_dump_detail [OPTIONS]
#
# See lk_tty_dump for details.
function lk_tty_dump_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_dump "$@"
    eval "$_lk_x_return"
}

# lk_tty_file FILE [COLOUR [FILE_COLOUR]]
function lk_tty_file() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    [ -n "${1-}" ] && lk_sudo -f test -r "${1-}" ||
        lk_err "file not found: ${1-}" || eval "$_lk_x_return"
    local IFS MESSAGE2
    unset IFS
    ! lk_verbose || { MESSAGE2=$(lk_sudo -f ls -ld "$1") &&
        MESSAGE2=${MESSAGE2/"$1"/$LK_BOLD$1$LK_RESET}; } || eval "$_lk_x_return"
    lk_sudo -f cat "$1" | lk_tty_dump - "$1" "${MESSAGE2-}" "${@:2}"
    eval "$_lk_x_return"
}

# lk_tty_file_detail FILE [COLOUR [FILE_COLOUR]]
function lk_tty_file_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_file "$@"
    eval "$_lk_x_return"
}

# - lk_tty_run [-SHIFT]                         COMMAND [ARG...]
# - lk_tty_run [-ARG=[REPLACE][:ARG=...]]       COMMAND [ARG...]
# - lk_tty_run [-SHIFT:ARG=[REPLACE][:ARG=...]] COMMAND [ARG...]
#
# Print COMMAND and run it after making optional changes to the printed version,
# where SHIFT is the number of arguments to remove (starting with COMMAND) and
# ARG is the 1-based argument to remove or REPLACE (starting with COMMAND or the
# first argument not removed by SHIFT).
function lk_tty_run() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local IFS SHIFT= TRANSFORM= CMD i REGEX='([0-9]+)=([^:]*)'
    unset IFS
    [[ ${1-} != -* ]] ||
        { [[ $1 =~ ^-(([0-9]+)(:($REGEX(:$REGEX)*))?|($REGEX(:$REGEX)*))$ ]] &&
            SHIFT=${BASH_REMATCH[2]} &&
            TRANSFORM=${BASH_REMATCH[4]:-${BASH_REMATCH[1]}} &&
            shift; } || lk_err "invalid arguments" || eval "$_lk_x_return"
    CMD=("$@")
    [ -z "$SHIFT" ] || shift "$SHIFT"
    while [[ $TRANSFORM =~ ^$REGEX:?(.*) ]]; do
        i=${BASH_REMATCH[1]}
        [[ -z "${BASH_REMATCH[2]}" ]] &&
            set -- "${@:1:i-1}" "${@:i+1}" ||
            set -- "${@:1:i-1}" "${BASH_REMATCH[2]}" "${@:i+1}"
        TRANSFORM=${BASH_REMATCH[3]}
    done
    while :; do
        case "${1-}" in
        lk_elevate)
            shift
            lk_root || set -- sudo "$@"
            break
            ;;
        lk_sudo | lk_maybe_sudo)
            shift
            ! lk_will_sudo || set -- sudo "$@"
            break
            ;;
        -*)
            shift
            continue
            ;;
        esac
        break
    done
    ${_LK_TTY_COMMAND:-lk_tty_print} "Running:" "$(lk_quote_args "$@")"
    "${CMD[@]}"
    eval "$_lk_x_return"
}

# lk_tty_run_detail [OPTIONS] COMMAND [ARG...]
#
# See lk_tty_run for details.
function lk_tty_run_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_run "$@"
    eval "$_lk_x_return"
}

# - lk_tty_pairs [-d DELIM] [COLOUR [--] [KEY VALUE...]]
# - lk_tty_pairs [-d DELIM] -- [KEY VALUE...]
#
# Print the key and value pair from each line of input such that values are
# left-aligned. Use -d to specify the line delimiter (default: $'\n'), and IFS
# to specify word delimiters (default: $'\t' if DELIM is not specified). Ignore
# input if KEY VALUE pairs are given as arguments or the "--" option is used.
#
# Only the first character of DELIM is used. If IFS is empty or unset, the
# default value is used. Characters in DELIM and IFS must not appear in any KEY
# or VALUE.
function lk_tty_pairs() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local IFS=${IFS:-$'\t'} LF COLOUR ARGS= TEMP LEN KEY VALUE
    unset LF COLOUR
    [ "${1-}" != -d ] || { LF=${2::1} && shift 2; }
    [ "${1-}" = -- ] || [ $# -eq 0 ] || { COLOUR=$1 && shift; }
    [ "${1-}" != -- ] || { ARGS=1 && shift; }
    [ -n "${LF+1}" ] || { LF=$'\n' && IFS=$'\t'; }
    # Check for an even number of arguments remaining and that LF does not
    # appear in IFS, then remove duplicates in IFS and rearrange it for the
    # regex bracket expression below
    (($# % 2 == 0)) && { [ -z "$LF" ] ||
        { [ -n "$LF" ] && [[ $IFS != *$LF* ]]; }; } &&
        IFS=$(LF=${LF:-\\0} && printf "%s${LF//%/%%}" "$IFS" |
            awk -v "RS=$LF" '
{ FS = ORS = RS
  gsub(/./, "&" RS)
  for (i = 1; i < NF; i++) {
    if ($i == "-") { last = "-" }
    else if ($i == "]") { first = "]" }
    else { middle = middle $i } }
  print first middle last }') ||
        lk_err "invalid arguments" || eval "$_lk_x_return"
    if [ $# -gt 0 ]; then
        local SEP=${IFS::1}
        lk_mktemp_with TEMP printf "%s${SEP//%/%%}%s\n" "$@"
    elif [ -z "$ARGS" ]; then
        lk_mktemp_with TEMP cat
    else
        true
        eval "$_lk_x_return"
    fi || eval "$_lk_x_return"
    # Align the length of the longest KEY to the nearest tab
    LEN=$(awk -F"[$IFS]+" -v "RS=${LF:-\\0}" -v m=2 '
    { if ((l = length($1)) > m) m = l }
END { g = (m + 2) % 4; print (g ? m + 4 - g : m) + 1 }' "$TEMP") ||
        eval "$_lk_x_return"
    while read -r -d "$LF" KEY VALUE; do
        _LK_TTY_ONE_LINE=1 ${_LK_TTY_COMMAND:-lk_tty_print} \
            "$(printf "%-${LEN}s" "$KEY:")" "$VALUE" ${COLOUR+"$COLOUR"}
    done <"$TEMP"
    eval "$_lk_x_return"
}

# - lk_tty_pairs_detail [-d DELIM] [COLOUR [--] [KEY VALUE...]]
# - lk_tty_pairs_detail [-d DELIM] -- [KEY VALUE...]
#
# See lk_tty_pairs for details.
function lk_tty_pairs_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_pairs "$@"
    eval "$_lk_x_return"
}

# lk_tty_diff [-L LABEL1 [-L LABEL2]] [FILE1] FILE2 [MESSAGE]
#
# Compare FILE1 and FILE2 using diff. If FILE1 or FILE2 is empty or "-", read it
# from input. If FILE2 is the only argument, use FILE2.orig as FILE1 if it
# exists and has a size greater than zero, otherwise call lk_tty_file FILE2.
function lk_tty_diff() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    local LABEL1 LABEL2
    [ "${1-}" != -L ] || { LABEL1=$2 && shift 2; }
    [ "${1-}" != -L ] || { LABEL2=$2 && shift 2; }
    [ $# -gt 0 ] || lk_err "invalid arguments" || eval "$_lk_x_return"
    [ $# -gt 1 ] ||
        if lk_sudo -f test -s "$1.orig"; then
            set -- "$1.orig" "$@"
        else
            lk_tty_file "$1"
            eval "$_lk_x_return"
        fi
    local FILE1=${1:--} FILE2=${2:--} MESSAGE=${3-}
    [ "$FILE1:$FILE2" != -:- ] ||
        lk_err "FILE1 and FILE2 cannot both be read from input" ||
        eval "$_lk_x_return"
    [[ :${#FILE1}${FILE1:0:1}:${#FILE2}${FILE2:0:1}: != *:1-:* ]] ||
        [ ! -t 0 ] ||
        lk_err "input is a terminal" || eval "$_lk_x_return"
    [ "$FILE1" != - ] || { FILE1=/dev/stdin && LABEL1="${LABEL1:-<input>}"; }
    [ "$FILE2" != - ] || { FILE2=/dev/stdin && LABEL2="${LABEL2:-<input>}"; }
    lk_tty_dump - \
        "${MESSAGE:-${LABEL1:-$FILE1}$LK_BOLD -> ${LABEL2:-$FILE2}$LK_RESET}" \
        "" "" "" lk_diff "$FILE1" "$FILE2"
    eval "$_lk_x_return"
}

function lk_tty_diff_detail() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _LK_STACK_DEPTH=1 _LK_TTY_COMMAND=lk_tty_detail lk_tty_diff "$@"
    eval "$_lk_x_return"
}

function _lk_tty_log() {
    local STATUS=$? IFS=' '
    [ "${1-}" = -r ] && shift || STATUS=0
    local _LK_TTY_PREFIX=${_LK_TTY_PREFIX-$1} _LK_TTY_MESSAGE_COLOUR=$2 \
        MESSAGE2=${4-} _LK_TTY_COLOUR2=${_LK_TTY_COLOUR2-}
    [ -z "${MESSAGE2:+1}" ] || _lk_tty_format -b MESSAGE2
    lk_tty_print "${3-}" "$MESSAGE2${5+ ${*:5}}" "$2"
    return "$STATUS"
}

# lk_tty_success [-r] MESSAGE [MESSAGE2...]
function lk_tty_success() {
    _lk_tty_log " ^^ " "$_LK_SUCCESS_COLOUR" "$@"
}

# lk_tty_log [-r] MESSAGE [MESSAGE2...]
function lk_tty_log() {
    _lk_tty_log " :: " "${_LK_TTY_COLOUR-$_LK_COLOUR}" "$@"
}

# lk_tty_warning [-r] MESSAGE [MESSAGE2...]
function lk_tty_warning() {
    _lk_tty_log "  ! " "$_LK_WARNING_COLOUR" "$@"
}

# lk_tty_error [-r] MESSAGE [MESSAGE2...]
function lk_tty_error() {
    _lk_tty_log " !! " "$_LK_ERROR_COLOUR" "$@"
}

#### Reviewed: 2021-10-30

#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2016,SC2034,SC2046,SC2086,SC2120,SC2207

USER=${USER:-$(id -un)} &&
    HOME=${HOME:-$(eval "echo ~$USER")} || return

function lk_command_exists() {
    type -P "$1" >/dev/null
}

function lk_is_macos() {
    [[ $OSTYPE == darwin* ]]
}

function lk_is_linux() {
    [[ $OSTYPE == linux-gnu ]]
}

function lk_is_arch() {
    return "${_LK_IS_ARCH:=$(lk_is_linux &&
        [ -f /etc/arch-release ] &&
        echo 0 || echo 1)}"
}

function lk_is_ubuntu() {
    return "${_LK_IS_UBUNTU:=$(lk_is_linux &&
        [ -r /etc/os-release ] && . /etc/os-release && [ "$NAME" = Ubuntu ] &&
        echo 0 || echo 1)}"
}

function lk_ubuntu_at_least() {
    local VERSION
    lk_is_ubuntu &&
        VERSION=$(. /etc/os-release && echo "$VERSION_ID") &&
        lk_version_at_least "$VERSION" "$1"
}

function lk_is_wsl() {
    return "${_LK_IS_WSL:=$(lk_is_linux &&
        grep -qi microsoft /proc/version >/dev/null 2>&1 &&
        echo 0 || echo 1)}"
}

function lk_is_desktop() {
    return "${_LK_IS_DESKTOP:=$({ lk_is_macos || lk_command_exists X; } &&
        echo 0 || echo 1)}"
}

function lk_is_server() {
    ! lk_is_desktop
}

function lk_is_virtual() {
    return "${_LK_IS_VIRTUAL:=$(lk_is_linux &&
        grep -Eq "^flags$S*:.*${S}hypervisor($S|$)" /proc/cpuinfo &&
        echo 0 || echo 1)}"
}

function lk_is_qemu() {
    return "${_LK_IS_QEMU:=$(lk_is_virtual &&
        shopt -s nullglob &&
        FILES=(/sys/devices/virtual/dmi/id/*_vendor) &&
        [ ${#FILES[@]} -gt 0 ] && grep -iq qemu "${FILES[@]}" &&
        echo 0 || echo 1)}"
}

_LK_GNU_COMMANDS=(
    awk chgrp chmod chown cp date df diff du find getopt grep ln mktemp nc
    realpath sed sort stat tar xargs
)

function _lk_gnu_command() {
    local COMMAND PREFIX=
    ! lk_is_macos || {
        PREFIX=g
        COMMAND=${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)} ||
            COMMAND=/usr/local
    }
    case "$1" in
    diff)
        ! lk_is_macos &&
            COMMAND=$1 ||
            COMMAND=$COMMAND/bin/$1
        ;;
    awk)
        COMMAND=gawk
        ;;
    nc)
        COMMAND=netcat
        ;;
    getopt)
        ! lk_is_macos &&
            COMMAND=getopt ||
            COMMAND=$COMMAND/opt/gnu-getopt/bin/getopt
        ;;
    *)
        COMMAND=$PREFIX$1
        ;;
    esac
    echo "$COMMAND"
}

function _lk_gnu_define() {
    local COMMAND
    for COMMAND in "${_LK_GNU_COMMANDS[@]}"; do
        eval "function gnu_$COMMAND() { $(_lk_gnu_command "$COMMAND") \"\$@\"; }"
    done
}

# Define wrapper functions (e.g. `gnu_find`) to invoke the GNU version of
# certain commands (e.g. `gfind`) on systems where standard utilities are not
# compatible with their GNU counterparts (notably BSD/macOS)
_lk_gnu_define
unset -f _lk_gnu_define

function lk_include() {
    local i FILE
    for i in "$@"; do
        ! lk_in_array "$i" _LK_INCLUDES || continue
        FILE=${LK_INST:-$LK_BASE}/lib/bash/include/$i.sh
        [ -r "$FILE" ] || lk_warn "$FILE: file not found" || return
        . "$FILE" || return
        _LK_INCLUDES+=("$i")
    done
}

function lk_is_script_running() {
    [ "${BASH_SOURCE[*]+${BASH_SOURCE[*]: -1:1}}" = "$0" ]
}

# lk_myself [-f] [STACK_DEPTH]
#
# If running from a source file and -f is not set, output the basename of the
# running script, otherwise print the name of the function at STACK_DEPTH in the
# call stack, where stack depth 0 (the default) represents the invoking
# function, stack depth 1 represents the invoking function's caller, and so on.
#
# Returns the most recent command's exit status to facilitate typical lk_usage
# scenarios.
function lk_myself() {
    local EXIT_STATUS=$? FUNC
    [ "${1:-}" != -f ] || {
        FUNC=1
        shift
    }
    if ! lk_is_true FUNC && lk_is_script_running; then
        echo "${0##*/}"
    else
        echo "${FUNCNAME[$((1 + ${1:-0}))]:-${0##*/}}"
    fi
    return "$EXIT_STATUS"
}

function _lk_caller() {
    local CONTEXT REGEX='^([0-9]+) ([^ ]+) (.*)$' SOURCE FUNC LINE \
        VERBOSE DIM=${LK_DIM:-$LK_GREY} CALLER=()
    if CONTEXT=${1:-$(caller 1)} &&
        [[ $CONTEXT =~ $REGEX ]]; then
        SOURCE=${BASH_REMATCH[3]}
        FUNC=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    fi
    ! lk_verbose || VERBOSE=1
    # If the caller isn't in the running script (or no script is running), start
    # with the shell/script name
    if [ "${SOURCE:=}" != "$0" ] || [ "$SOURCE" = main ]; then
        CALLER=("$LK_BOLD${0##*/}$LK_RESET")
    fi
    # Always include source filename (and line number if being verbose)
    if [ -n "$SOURCE" ] && [ "$SOURCE" != main ]; then
        CALLER+=("$(
            if [ "$SOURCE" = "$0" ]; then
                echo "$LK_BOLD${0##*/}$LK_RESET"
            else
                SOURCE=${SOURCE//~/"~"}
                echo "$SOURCE"
            fi
        )${VERBOSE:+$DIM:$LINE$LK_RESET}")
    fi
    ! lk_is_true LK_DEBUG ||
        [ -z "${FUNC:-}" ] ||
        [ "$FUNC" = main ] ||
        CALLER+=("$FUNC$DIM()$LK_RESET")
    lk_implode "$DIM->$LK_RESET" CALLER
}

# lk_warn [MESSAGE]
#
# Output "<context>: MESSAGE" as a warning and return the most recent command's
# exit status.
function lk_warn() {
    local EXIT_STATUS=$?
    lk_console_warning "$(_lk_caller): ${1:-execution failed}"
    return "$EXIT_STATUS"
}

function _lk_usage_format() {
    local CMD BOLD RESET
    CMD=$(lk_escape_ere "$(lk_myself 2)")
    BOLD=$(lk_escape_ere_replace "$LK_BOLD")
    RESET=$(lk_escape_ere_replace "$LK_RESET")
    sed -E \
        -e "s/^($S*(([uU]sage|[oO]r):$S+)?)($CMD)($S|\$)/\1$BOLD\4$RESET\5/" \
        -e "s/^\w.*:\$/$BOLD&$RESET/" <<<"$1"
}

function lk_usage() {
    local EXIT_STATUS=$? MESSAGE=${1:-${LK_USAGE:-}}
    [ -z "$MESSAGE" ] || MESSAGE=$(_lk_usage_format "$MESSAGE")
    LK_TTY_NO_FOLD=1 \
        lk_console_log "${MESSAGE:-$(_lk_caller): invalid arguments}"
    return "$EXIT_STATUS"
}

function _lk_mktemp() {
    local TMPDIR=${TMPDIR:-/tmp}
    mktemp "$@" -- "${TMPDIR%/}/$(lk_myself 2).XXXXXXXXXX"
}

function lk_mktemp_file() {
    _lk_mktemp
}

function lk_mktemp_dir() {
    _lk_mktemp -d
}

function lk_mktemp_fifo() {
    local FIFO_PATH
    FIFO_PATH=$(lk_mktemp_dir)/fifo &&
        mkfifo "$FIFO_PATH" &&
        echo "$FIFO_PATH"
}

function lk_command_first_existing() {
    local COMMAND
    while [ $# -gt 0 ]; do
        eval "COMMAND=($1)"
        if type -P "${COMMAND[0]}" >/dev/null; then
            echo "$1"
            return 0
        fi
        shift
    done
    false
}

function lk_regex_implode() {
    [ $# -gt 0 ] || return 0
    if [ $# -gt 1 ]; then
        printf '(%s)' "$(lk_implode_args "|" "$@")"
    else
        printf '%s' "$1"
    fi
}

function _lk_var_prefix() {
    [[ "${FUNCNAME[2]:-}" =~ ^(source|main)?$ ]] || printf 'local '
}

function _lk_get_regex() {
    printf 'local %s=%q\n' "$1" "$2"
    printf 'REGEX_VARS[$((i++))]=%s\n' "$1"
}

# lk_get_regex [REGEX_NAME...]
#
# Output Bash-compatible variable assignments for all available regular
# expressions or for each REGEX_NAME.
function lk_get_regex() {
    local _O _H _P _S _U _A _Q _F _1 _2 _4 _6 \
        SH REGEX_VARS=() i=0 REGEX EXIT_STATUS=0

    SH=$(_lk_get_regex DOMAIN_PART_REGEX "[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?") && eval "$SH"
    SH=$(_lk_get_regex DOMAIN_NAME_REGEX "($DOMAIN_PART_REGEX(\\.|\$)){2,}") && eval "$SH"
    SH=$(_lk_get_regex EMAIL_ADDRESS_REGEX "[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~]([-a-zA-Z0-9.!#\$%&'*+/=?^_\`{|}~]{,62}[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~])?@$DOMAIN_NAME_REGEX") && eval "$SH"

    _O="(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])"
    SH=$(_lk_get_regex IPV4_REGEX "($_O\\.){3}$_O") && eval "$SH"
    SH=$(_lk_get_regex IPV4_OPT_PREFIX_REGEX "$IPV4_REGEX(/(3[0-2]|[12][0-9]|[1-9]))?") && eval "$SH"

    _H="[0-9a-fA-F]{1,4}"
    _P="/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])"
    SH=$(_lk_get_regex IPV6_REGEX "(($_H:){7}(:|$_H)|($_H:){6}(:|:$_H)|($_H:){5}(:|(:$_H){1,2})|($_H:){4}(:|(:$_H){1,3})|($_H:){3}(:|(:$_H){1,4})|($_H:){2}(:|(:$_H){1,5})|$_H:(:|(:$_H){1,6})|:(:|(:$_H){1,7}))") && eval "$SH"
    SH=$(_lk_get_regex IPV6_OPT_PREFIX_REGEX "$IPV6_REGEX($_P)?") && eval "$SH"

    SH=$(_lk_get_regex IP_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX)") && eval "$SH"
    SH=$(_lk_get_regex HOST_REGEX "($IPV4_REGEX|$IPV6_REGEX|$DOMAIN_PART_REGEX|$DOMAIN_NAME_REGEX)") && eval "$SH"
    SH=$(_lk_get_regex HOST_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX|$DOMAIN_PART_REGEX|$DOMAIN_NAME_REGEX)") && eval "$SH"

    # https://en.wikipedia.org/wiki/Uniform_Resource_Identifier
    _S="[a-zA-Z][-a-zA-Z0-9+.]*"                               # scheme
    _U="[-a-zA-Z0-9._~%!\$&'()*+,;=]+"                         # username
    _P="[-a-zA-Z0-9._~%!\$&'()*+,;=]*"                         # password
    _H="([-a-zA-Z0-9._~%!\$&'()*+,;=]+|\\[([0-9a-fA-F:]+)\\])" # host
    _O="[0-9]+"                                                # port
    _A="[-a-zA-Z0-9._~%!\$&'()*+,;=:@/]+"                      # path
    _Q="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]+"                     # query
    _F="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]*"                     # fragment
    SH=$(_lk_get_regex URI_REGEX "(($_S):)?(//(($_U)(:($_P))?@)?$_H(:($_O))?)?($_A)?(\\?($_Q))?(#($_F))?") && eval "$SH"
    SH=$(_lk_get_regex URI_REGEX_REQ_SCHEME_HOST "(($_S):)(//(($_U)(:($_P))?@)?$_H(:($_O))?)($_A)?(\\?($_Q))?(#($_F))?") && eval "$SH"

    SH=$(_lk_get_regex LINUX_USERNAME_REGEX "[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\\\$)") && eval "$SH"
    SH=$(_lk_get_regex MYSQL_USERNAME_REGEX "[a-zA-Z0-9_]+") && eval "$SH"

    # https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source
    SH=$(_lk_get_regex DPKG_SOURCE_REGEX "[a-z0-9][-a-z0-9+.]+") && eval "$SH"

    SH=$(_lk_get_regex PHP_SETTING_NAME_REGEX "[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z_][a-zA-Z0-9_]*)*") && eval "$SH"
    SH=$(_lk_get_regex PHP_SETTING_REGEX "$PHP_SETTING_NAME_REGEX=.+") && eval "$SH"

    SH=$(_lk_get_regex READLINE_NON_PRINTING_REGEX $'\x01[^\x02]*\x02') && eval "$SH"
    SH=$(_lk_get_regex CONTROL_SEQUENCE_REGEX $'\x1b\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]') && eval "$SH"
    SH=$(_lk_get_regex ESCAPE_SEQUENCE_REGEX $'\x1b[\x20-\x2f]*[\x30-\x7e]') && eval "$SH"
    SH=$(_lk_get_regex NON_PRINTING_REGEX $'(\x01[^\x02]*\x02|\x1b(\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]|[\x20-\x2f]*[\x30-\x5a\\\x5c-\x7e]))') && eval "$SH"

    # *_FILTER_REGEX expressions are:
    # 1. anchored
    # 2. not intended for validation
    SH=$(_lk_get_regex IPV4_PRIVATE_FILTER_REGEX "^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|127\\.)") && eval "$SH"

    _1="[0-9]"
    _2="$_1$_1"
    _4="$_2$_2"
    _6="$_2$_2$_2"
    SH=$(_lk_get_regex BACKUP_TIMESTAMP_FINDUTILS_REGEX "$_4-$_2-$_2-$_6") && eval "$SH"

    [ $# -gt 0 ] || set -- "${REGEX_VARS[@]}"
    for REGEX in "$@"; do
        _lk_var_prefix
        printf "%s=%q\n" "$REGEX" "${!REGEX}" || EXIT_STATUS=$?
    done
    return "$EXIT_STATUS"
}

# lk_bash_at_least MAJOR [MINOR]
function lk_bash_at_least() {
    [ "${BASH_VERSINFO[0]}" -eq "$1" ] &&
        [ "${BASH_VERSINFO[1]}" -ge "${2:-0}" ] ||
        [ "${BASH_VERSINFO[0]}" -gt "$1" ]
}

if lk_bash_at_least 4 2; then
    function lk_date() {
        # Take advantage of printf support for strftime in Bash 4.2+
        printf "%($1)T\n" -1
    }
else
    function lk_date() {
        date +"$1"
    }
fi

# lk_date_log
#
# Output the current time in a format suitable for log files.
function lk_date_log() {
    lk_date "%Y-%m-%d %H:%M:%S %z"
}

function lk_date_ymdhms() {
    lk_date "%Y%m%d%H%M%S"
}

function lk_date_ymd() {
    lk_date "%Y%m%d"
}

function lk_timestamp() {
    lk_date "%s"
}

if lk_bash_at_least 4 1; then
    function lk_pause() {
        local REPLY
        # A homage to MS-DOS
        read -rs -N 1 \
            -p "$(lk_readline_format "${1:-Press any key to continue . . . }")"
        lk_console_blank
    }
else
    function lk_pause() {
        local REPLY
        read -rs \
            -p "$(lk_readline_format "${1:-Press return to continue . . . }")"
        lk_console_blank
    }
fi

function lk_is_root() {
    [ "$EUID" -eq 0 ]
}

# lk_is_true VAR
#
# Return true if the value of variable VAR is one of the following "truthy"
# values (case-insensitive).
# - 1
# - True
# - Y
# - Yes
# - On
function lk_is_true() {
    [[ ${!1:-} =~ ^(1|[tT][rR][uU][eE]|[yY]([eE][sS])?|[oO][nN])$ ]]
}

# lk_is_false VAR
#
# Return true if the value of variable VAR is one of the following "falsy"
# values (case-insensitive).
# - 0
# - False
# - N
# - No
# - Off
function lk_is_false() {
    [[ ${!1:-} =~ ^(0|[fF][aA][lL][sS][eE]|[nN][oO]?|[oO][fF][fF])$ ]]
}

# lk_escape STRING [ESCAPE_CHAR...]
#
# Escape STRING by inserting a backslash before each occurrence of each
# ESCAPE_CHAR.
function lk_escape() {
    local STRING=$1 ESCAPE=${LK_ESCAPE:-\\} SPECIAL SEARCH i=0
    SPECIAL=("$ESCAPE" "${@:2}")
    for SEARCH in "${SPECIAL[@]}"; do
        # Ensure ESCAPE itself is only escaped once
        ! ((i++)) || [ "$SEARCH" != "$ESCAPE" ] || continue
        STRING=${STRING//"$SEARCH"/$ESCAPE$SEARCH}
    done
    echo "$STRING"
}

function lk_get_shell_var() {
    local _LK_ESCAPED
    while [ $# -gt 0 ]; do
        if [ -n "${!1:-}" ]; then
            _LK_ESCAPED=$(lk_escape "${!1}." '$' '`' "\\" '"')
            printf '%s="%s"\n' "$1" "${_LK_ESCAPED%.}"
        else
            printf '%s=\n' "$1"
        fi
        shift
    done
}

function lk_escape_ere() {
    lk_escape "$1" '$' '(' ')' '*' '+' '.' '/' '?' '[' "\\" ']' '^' '{' '|' '}'
}

function lk_escape_ere_replace() {
    lk_escape "$1" '&' '/' "\\"
}

# lk_curl_config [--]ARG[=PARAM]...
#
# Output each ARG=PARAM pair formatted for use with `curl --config`.
function lk_curl_config() {
    local PARAM
    while [ $# -gt 0 ]; do
        [[ $1 =~ ^([^=]+)(=(.*))?$ ]] ||
            lk_warn "invalid argument: $1" || return
        if [ -z "${BASH_REMATCH[2]}" ]; then
            printf -- '--%s\n' "${1#--}"
        else
            PARAM=$(lk_escape "${BASH_REMATCH[3]}" "\\" '"')
            PARAM=${PARAM//$'\t'/\\t}
            PARAM=${PARAM//$'\n'/\\n}
            PARAM=${PARAM//$'\r'/\\r}
            PARAM=${PARAM//$'\v'/\\v}
            printf -- '--%s "%s"\n' "${BASH_REMATCH[1]#--}" "$PARAM"
        fi
        shift
    done
}

# lk_regex_case_insensitive STRING
#
# Replace each alphabetic character in STRING with a bracket expression that
# matches its lower- and upper-case equivalents.
#
# Example:
#
#     $ lk_regex_case_insensitive True
#     [tT][rR][uU][eE]
function lk_regex_case_insensitive() {
    local i l LOWER UPPER REGEX=
    for i in $(seq 0 $((${#1} - 1))); do
        l=${1:$i:1}
        [[ ! $l =~ [[:alpha:]] ]] || {
            LOWER=$(lk_lower "$l")
            UPPER=$(lk_upper "$l")
            [ "$LOWER" = "$UPPER" ] || {
                REGEX="${REGEX}[$LOWER$UPPER]"
                continue
            }
        }
        REGEX=$REGEX$l
    done
    echo "$REGEX"
}

# lk_regex_expand_whitespace STRING
#
# Replace each unquoted sequence of one or more whitespace characters in STRING
# with "[[:blank:]]+". Escaped delimiters within double- and single-quoted
# sequences are recognised.
#
# Example:
#
#     $ lk_regex_expand_whitespace "message = 'Here\'s a message'"
#     message[[:blank:]]+=[[:blank:]]+'Here\'s a message'
function lk_regex_expand_whitespace() {
    sed -E "\
:start
s/^(([^'\"[:blank:]]*|(''|'([^']|\\\\')*[^\\]')|(\"\"|\"([^\"]|\\\\\")*[^\\]\"))*)$S+/\\1[[:blank:]]+/
t start" <<<"$1"
}

# lk_replace FIND REPLACE STRING
#
# Replace all occurrences of FIND in STRING with REPLACE.
function lk_replace() {
    local STRING
    STRING=${3//"$1"/$2}
    echo "$STRING"
}

# lk_in_string NEEDLE HAYSTACK
#
# True if NEEDLE is a substring of HAYSTACK.
function lk_in_string() {
    [ "$(lk_replace "$1" "" "$2.")" != "$2." ]
}

function lk_has_newline() {
    [ "${!1/$'\n'/}" != "${!1}" ]
}

# lk_expand_template [-q] [FILE]
#
# Output FILE or input with each {{KEY}} tag (or each {{KEY}} tag where KEY is
# an element of array LK_EXPAND_KEYS) replaced with the value of variable KEY.
# If -q is set, use `printf %q` when expanding tags.
function lk_expand_template() {
    local QUOTE TEMPLATE KEY REPLACE \
        KEYS=(${LK_EXPAND_KEYS[@]+"${LK_EXPAND_KEYS[@]}"})
    [ "${1:-}" != -q ] || { QUOTE=1 && shift; }
    TEMPLATE=$(cat ${1+"$1"} && printf .) || return
    [ ${#KEYS[@]} -gt 0 ] ||
        KEYS=($(echo "$TEMPLATE" |
            grep -Eo '\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}' | sort -u |
            sed -E 's/^\{\{([a-zA-Z0-9_]+)\}\}$/\1/')) || true
    for KEY in ${KEYS[@]+"${KEYS[@]}"}; do
        REPLACE=${!KEY:-}
        ! lk_is_true QUOTE || {
            REPLACE=$(printf '%q.' "$REPLACE")
            REPLACE=${REPLACE%.}
        }
        TEMPLATE=${TEMPLATE//"{{$KEY}}"/$REPLACE}
    done
    echo "${TEMPLATE%.}"
}

function lk_lower() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        tr '[:upper:]' '[:lower:]'
}

function lk_upper() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        tr '[:lower:]' '[:upper:]'
}

function lk_upper_first() {
    local EXIT_STATUS
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    printf '%s%s\n' "$(lk_upper "${1:0:1}")" "$(lk_lower "${1:1}")"
}

function lk_trim() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        sed -Ee 's/^[[:blank:]]+//' -e 's/[[:blank:]]+$//'
}

function lk_pad_zero() {
    [[ $2 =~ ^0*([0-9]+)$ ]] || lk_warn "not a number: $2" || return
    printf "%0$1d" "${BASH_REMATCH[1]}"
}

# lk_ellipsis LENGTH STRING
function lk_ellipsis() {
    [ "$1" -gt 3 ] &&
        [[ $2 =~ ^(.{$(($1 - 3))}).{4,} ]] &&
        echo "${BASH_REMATCH[1]}..." ||
        echo "$2"
}

# lk_repeat STRING MULTIPLIER
function lk_repeat() {
    [ "$2" -le 0 ] || {
        local STRING=$1
        STRING=${STRING//\\/\\\\}
        STRING=${STRING//%/%%}
        printf -- "$STRING%.s" $(seq 1 "$2")
    }
}

function lk_hostname() {
    hostname -s
}

function lk_fqdn() {
    hostname -f
}

function _lk_get_colour() {
    local SEQ
    while [ $# -ge 2 ]; do
        SEQ=$(tput $2) || SEQ=
        printf '%s%s=%q\n' "$PREFIX" "$1" "$SEQ"
        shift 2
    done
}

# lk_get_colours [PREFIX]
function lk_get_colours() {
    local PREFIX
    PREFIX=$(_lk_var_prefix)${1-LK_}
    _lk_get_colour \
        BLACK "setaf 0" \
        RED "setaf 1" \
        GREEN "setaf 2" \
        YELLOW "setaf 3" \
        BLUE "setaf 4" \
        MAGENTA "setaf 5" \
        CYAN "setaf 6" \
        WHITE "setaf 7" \
        GREY "setaf 8" \
        BLACK_BG "setab 0" \
        RED_BG "setab 1" \
        GREEN_BG "setab 2" \
        YELLOW_BG "setab 3" \
        BLUE_BG "setab 4" \
        MAGENTA_BG "setab 5" \
        CYAN_BG "setab 6" \
        WHITE_BG "setab 7" \
        GREY_BG "setab 8" \
        BOLD "bold" \
        DIM "dim" \
        STANDOUT "smso" \
        STANDOUT_OFF "rmso" \
        WRAP "smam" \
        WRAP_OFF "rmam" \
        RESET "sgr0"
}

function lk_maybe_bold() {
    [[ ${1/"$LK_BOLD"/} != "$1" ]] ||
        echo "$LK_BOLD"
}

function lk_maybe_plural() {
    [ "$1" -eq 1 ] && echo "$2" || echo "$3"
}

# _lk_array_fill_temp ARRAY...
#
# Create new array _LK_TEMP_ARRAY and copy the elements of each ARRAY to it.
function _lk_array_fill_temp() {
    local _LK_ARRAY
    _LK_TEMP_ARRAY=()
    while [ $# -gt 0 ]; do
        lk_is_identifier "$1" ||
            lk_warn "not a valid identifier: $1" || return
        _LK_ARRAY="$1[@]"
        _LK_TEMP_ARRAY+=(${!_LK_ARRAY+"${!_LK_ARRAY}"})
        shift
    done
}

# _lk_array_action COMMAND ARRAY...
#
# Run COMMAND with the combined elements of each ARRAY as arguments. COMMAND is
# executed once and any fixed arguments must be quoted (see lk_implode for an
# example).
function _lk_array_action() {
    local _LK_COMMAND _LK_TEMP_ARRAY
    eval "_LK_COMMAND=($1)"
    _lk_array_fill_temp "${@:2}"
    "${_LK_COMMAND[@]}" ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}
}

# lk_echo_args [-z] [ARG...]
function lk_echo_args() {
    local DELIM=${_LK_NUL_DELIM:+'\0'}
    [ "${1:-}" != -z ] || { DELIM='\0' && shift; }
    printf "%s${DELIM:-\\n}" "$@"
}

# lk_echo_array [-z] [ARRAY...]
function lk_echo_array() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-}
    [ "${1:-}" != -z ] || { _LK_NUL_DELIM=1 && shift; }
    _lk_array_action lk_echo_args "$@"
}

# lk_quote_args [ARG...]
#
# Use `printf %q` to quote each ARG, and output the results on a single
# space-delimited line.
function lk_quote_args() {
    [ $# -eq 0 ] || printf '%q' "$1"
    [ $# -le 1 ] || printf ' %q' "${@:2}"
    printf '\n'
}

# lk_quote [ARRAY...]
function lk_quote() {
    _lk_array_action lk_quote_args "$@"
}

# lk_implode_args GLUE [ARG...]
function lk_implode_args() {
    local GLUE=$1
    GLUE=${GLUE//\\/\\\\}
    GLUE=${GLUE//%/%%}
    [ $# -eq 1 ] || printf '%s' "$2"
    [ $# -le 2 ] || printf -- "$GLUE%s" "${@:3}"
    printf '\n'
}

# lk_implode GLUE [ARRAY...]
function lk_implode() {
    _lk_array_action "$(lk_quote_args lk_implode_args "$1")" "${@:2}"
}

# lk_in_array VALUE ARRAY
#
# Return true if VALUE exists in ARRAY, otherwise return false.
function lk_in_array() {
    local _LK_ARRAY="$2[@]" _LK_VAL
    for _LK_VAL in ${!_LK_ARRAY+"${!_LK_ARRAY}"}; do
        [ "$_LK_VAL" = "$1" ] || continue
        return 0
    done
    false
}

# lk_array_search PATTERN ARRAY
#
# Search ARRAY for PATTERN and output the key of the first match if found,
# otherwise return false.
function lk_array_search() {
    local _LK_KEYS _LK_VALS _lk_i
    eval "_LK_KEYS=(\"\${!$2[@]}\")"
    eval "_LK_VALS=(\"\${$2[@]}\")"
    for _lk_i in "${!_LK_VALS[@]}"; do
        # shellcheck disable=SC2053
        [[ ${_LK_VALS[$_lk_i]} == $1 ]] || continue
        echo "${_LK_KEYS[$_lk_i]}"
        return 0
    done
    false
}

# lk_xargs [-z] COMMAND [ARG...]
#
# Invoke the given command line for each LINE of input, passing LINE as the
# final argument. If -z is set, use NUL instead of newline as the input
# delimiter.
function lk_xargs() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-} _LK_NUL_READ=(-d '') _LK_LINE
    [ "${1:-}" != -z ] || { _LK_NUL_DELIM=1 && shift; }
    while IFS= read -r ${_LK_NUL_DELIM:+"${_LK_NUL_READ[@]}"} _LK_LINE ||
        [ -n "$_LK_LINE" ]; do
        "$@" "$_LK_LINE" || return
    done
}

# _lk_maybe_xargs FIXED_ARGS [ARG...]
#
# For functions that take FIXED_ARGS followed by one value argument, add support
# for passing multiple values in subsequent arguments or on standard input via
# newline- or NUL-delimited lines.
#
# After accounting for FIXED_ARGS, the number of arguments remaining determines
# next steps.
# 1. one argument: return false immediately, signalling the caller to process
#    the value passed
# 2. zero arguments: use lk_xargs to invoke the caller with each line of input,
#    then set EXIT_STATUS to the return value and return true
# 3. two or more arguments: invoke the caller with each argument, then set
#    EXIT_STATUS to the return value and return true
#
# If there are no value arguments and the caller is invoked with -z as the first
# argument, use NUL instead of newline as the input delimiter.
#
# Example:
#
#     function my_function() {
#         local EXIT_STATUS
#         ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
#         # process $1
#     }
function _lk_maybe_xargs() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-} COMMAND
    # Check for -z and no value arguments, i.e. NUL-delimited input
    [ "${2:-}" != -z ] || (($# - $1 - 2)) ||
        { _LK_NUL_DELIM=1 && set -- "$1" "${@:3}"; }
    # Return false ASAP if there's exactly one value for the caller to process
    (($# - $1 - 2)) || return
    COMMAND=("$(lk_myself -f 1)" "${@:2:$1}")
    EXIT_STATUS=0
    # If there are no values to process, use lk_xargs to pass input lines
    if ! (($# - $1 - 1)); then
        lk_xargs "${COMMAND[@]}" || EXIT_STATUS=$?
    else
        # Otherwise pass each value
        for i in "${@:$(($1 + 2))}"; do
            "${COMMAND[@]}" "$i" || {
                EXIT_STATUS=$?
                return 0
            }
        done
    fi
}

# lk_mapfile [-z] ARRAY [FILE]
#
# Read lines from FILE or input into array variable ARRAY.
function lk_mapfile() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-} _LK_NUL_READ=(-d '') _LK_LINE _lk_i=0
    [ "${1:-}" != -z ] || { _LK_NUL_DELIM=1 && shift; }
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    [ -z "${2:-}" ] ||
        [ -e "$2" ] || lk_warn "file not found: $2" || return
    eval "$1=()"
    while IFS= read -r ${_LK_NUL_DELIM:+"${_LK_NUL_READ[@]}"} _LK_LINE ||
        [ -n "$_LK_LINE" ]; do
        eval "$1[$((_lk_i++))]=\$_LK_LINE"
    done < <(cat ${2+"$2"})
}

function lk_has_arg() {
    lk_in_array "$1" "${LK_ARG_ARRAY:-LK_ARGV}"
}

# lk_get_outputs_of COMMAND [ARG...]
#
# Execute COMMAND, output Bash-compatible code that sets _STDOUT and _STDERR to
# COMMAND's respective outputs, and exit with COMMAND's exit status.
function lk_get_outputs_of() {
    local SH EXIT_STATUS
    SH=$(
        _LK_STDOUT=$(lk_mktemp_file) &&
            _LK_STDERR=$(lk_mktemp_file) || exit
        unset _LK_FD
        "$@" >"$_LK_STDOUT" 2>"$_LK_STDERR" || EXIT_STATUS=$?
        for i in _LK_STDOUT _LK_STDERR; do
            _lk_var_prefix
            printf '%s=%q\n' "${i#_LK}" "$(cat "${!i}")"
            rm -f -- "${!i}" || true
        done
        exit "${EXIT_STATUS:-0}"
    ) || EXIT_STATUS=$?
    echo "$SH"
    return "${EXIT_STATUS:-0}"
}

# lk_next_fd
#
# Output the next available file descriptor greater than or equal to 10.
#
# Essentially a shim for Bash 4.1's {var}>, {var}<, etc.
function lk_next_fd() {
    local USED
    [ -d /dev/fd ] &&
        USED=(/dev/fd/*) &&
        [ ${#USED[@]} -ge 3 ] ||
        lk_warn "not supported: /dev/fd" || return
    USED=("${USED[@]#\/dev\/fd\/}")
    lk_echo_array USED | sort -n |
        awk 'BEGIN{n=10} n>$1{next} n==$1{n++;next} {exit} END{print n}'
}

# lk_is_fd_open FILE_DESCRIPTOR
function lk_is_fd_open() {
    { true >&"$1"; } 2>/dev/null
}

function lk_log() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        printf '%s %s\n' "$(lk_date_log)" "$LINE"
    done
}

function lk_log_create_file() {
    local OWNER=$UID LOG_DIRS=() LOG_DIR LOG_PATH
    [ ! -d "${LK_INST:-$LK_BASE}" ] ||
        [ -z "$(ls -A "${LK_INST:-$LK_BASE}")" ] ||
        LOG_DIRS=("${LK_INST:-$LK_BASE}/var/log")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS[@]+"${LOG_DIRS[@]}"}; do
        # Find the first LOG_DIR where the user can write to LOG_DIR/LOG_FILE,
        # installing LOG_DIR (world-writable) and LOG_FILE (owner-only) if
        # needed, running commands via sudo only if they fail without it
        [ -d "$LOG_DIR" ] ||
            lk_elevate_if_error install -d \
                -m "$(lk_pad_zero 5 "${LK_LOG_DIR_MODE:-0777}")" \
                "$LOG_DIR" 2>/dev/null ||
            continue
        LOG_PATH=$LOG_DIR/${LK_LOG_BASENAME:-${0##*/}}-$UID.log
        if [ -f "$LOG_PATH" ]; then
            [ -w "$LOG_PATH" ] || {
                lk_elevate_if_error chmod \
                    "$(lk_pad_zero 5 "${LK_LOG_FILE_MODE:-0600}")" \
                    "$LOG_PATH" || continue
                [ -w "$LOG_PATH" ] ||
                    lk_elevate chown \
                        "$OWNER" \
                        "$LOG_PATH" || continue
            } 2>/dev/null
        else
            lk_elevate_if_error install \
                -m "$(lk_pad_zero 5 "${LK_LOG_FILE_MODE:-0600}")" \
                -o "$OWNER" \
                /dev/null "$LOG_PATH" 2>/dev/null || continue
        fi
        echo "$LOG_PATH"
        return 0
    done
    return 1
}

# lk_log_output [TEMP_LOG_FILE]
function lk_log_output() {
    local LOG_PATH DIR HEADER=() IFS
    ! lk_is_true LK_NO_LOG &&
        ! lk_log_is_open || return 0
    [[ $- != *x* ]] || [ -n "${BASH_XTRACEFD:-}" ] || return 0
    if [ $# -ge 1 ]; then
        if LOG_PATH=$(lk_log_create_file); then
            # If TEMP_LOG_FILE exists, move its contents to the end of LOG_PATH
            [ ! -e "$1" ] || {
                cat "$1" >>"$LOG_PATH" &&
                    rm "$1" || return
            }
        else
            LOG_PATH=$1
        fi
    else
        LOG_PATH=$(lk_log_create_file ~ /tmp) ||
            lk_warn "unable to open log file" || return
    fi
    # Log invocation details, including script path if running from a source
    # file, to separate this from any previous runs
    { [ ${#BASH_SOURCE[@]} -eq 0 ] ||
        [[ ! $0 =~ ^((.*)/)?([^/]+)$ ]] ||
        ! DIR=$(cd "${BASH_REMATCH[2]:-.}" && pwd -P) ||
        HEADER+=("${DIR%/}/"); } 2>/dev/null
    HEADER+=("${0##*/} invoked")
    [ ${#LK_ARGV[@]} -eq 0 ] || HEADER+=($(
        printf ' with %s %s:' \
            ${#LK_ARGV[@]} \
            "$(lk_maybe_plural \
                ${#LK_ARGV[@]} "argument" "arguments")"
        printf '\n- %q' "${LK_ARGV[@]}"
    ))
    IFS=
    echo "$LK_BOLD====> ${HEADER[*]}$LK_RESET" | lk_log >>"$LOG_PATH" &&
        _LK_LOG_OUT_FD=$(lk_next_fd) && eval "exec $_LK_LOG_OUT_FD>&1" &&
        _LK_LOG_ERR_FD=$(lk_next_fd) && eval "exec $_LK_LOG_ERR_FD>&2" &&
        exec > >(tee >(lk_log | { if [ -n "${LK_SECONDARY_LOG_FILE:-}" ]; then
            tee -a "$LK_SECONDARY_LOG_FILE"
        else
            cat
        fi >>"$LOG_PATH"; })) 2>&1 ||
        return
    ! lk_verbose ||
        lk_echoc "Output is being logged to $LK_BOLD$LOG_PATH$LK_RESET" \
            "$LK_GREY" >&"$_LK_LOG_ERR_FD"
    _LK_LOG_FILE=$LOG_PATH
}

function lk_log_is_open() {
    [ "${_LK_LOG_FILE:+1}${_LK_LOG_OUT_FD:+1}${_LK_LOG_ERR_FD:+1}" = 111 ] &&
        lk_is_fd_open "$_LK_LOG_OUT_FD" &&
        lk_is_fd_open "$_LK_LOG_ERR_FD"
}

function lk_log_close() {
    lk_log_is_open || lk_warn "no output log to close" || return
    exec >&"$_LK_LOG_OUT_FD" 2>&"$_LK_LOG_ERR_FD" &&
        eval "exec $_LK_LOG_OUT_FD>&- $_LK_LOG_ERR_FD>&-" &&
        unset _LK_LOG_FILE
}

function lk_log_bypass() {
    if lk_log_is_open; then
        "$@" >&"$_LK_LOG_OUT_FD" 2>&"$_LK_LOG_ERR_FD"
    else
        "$@"
    fi
}

function lk_log_bypass_stdout() {
    if lk_log_is_open; then
        "$@" >&"$_LK_LOG_OUT_FD"
    else
        "$@"
    fi
}

function lk_log_bypass_stderr() {
    if lk_log_is_open; then
        "$@" 2>&"$_LK_LOG_ERR_FD"
    else
        "$@"
    fi
}

# lk_echoc [-n] [MESSAGE [COLOUR]]
function lk_echoc() {
    local NEWLINE MESSAGE
    [ "${1:-}" != -n ] || {
        NEWLINE=0
        shift
    }
    MESSAGE=${1:-}
    [ $# -le 1 ] || [ -z "$LK_RESET" ] ||
        MESSAGE=$2${MESSAGE//"$LK_RESET"/$LK_RESET$2}$LK_RESET
    echo ${NEWLINE:+-n} "$MESSAGE"
}

function lk_readline_format() {
    local LC_ALL=C STRING=$1 REGEX SH
    for REGEX in CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX; do
        SH=$(lk_get_regex "$REGEX") &&
            eval "$SH"
        while [[ $STRING =~ ((.*)(^|[^$'\x01']))(${!REGEX})+(.*) ]]; do
            STRING=${BASH_REMATCH[1]}$'\x01'${BASH_REMATCH[4]}$'\x02'${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
        done
    done
    echo "$STRING"
}

function lk_strip_non_printing() {
    local LC_ALL=C STRING REGEX
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    if [ $# -gt 0 ]; then
        STRING=$1
        while [[ $STRING =~ (.*)$NON_PRINTING_REGEX(.*) ]]; do
            STRING=${BASH_REMATCH[1]}${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
        done
        echo "$STRING"
    else
        export LC_ALL
        sed -E "s/$NON_PRINTING_REGEX//g"
    fi
}

# lk_fold STRING [WIDTH]
#
# Wrap STRING to fit in WIDTH (default: 80) after accounting for non-printing
# character sequences, breaking at whitespace only.
function lk_fold() {
    local LC_ALL=C STRING WIDTH=${2:-80} REGEX \
        PARTS=() CODES=() LINE_TEXT LINE i PART CODE _LINE_TEXT
    [ $# -gt 0 ] || lk_usage "\
Usage: $(lk_myself -f) STRING [WIDTH]" || return
    STRING=$1
    ! lk_command_exists expand ||
        STRING=$(expand <<<"$STRING") || return
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    REGEX=$'^([^\x1b\x01]*)'"(($NON_PRINTING_REGEX)+)(.*)"
    while [[ $STRING =~ $REGEX ]]; do
        PARTS+=("${BASH_REMATCH[1]}")
        CODES+=("${BASH_REMATCH[2]}")
        STRING=${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
    done
    [ -z "$STRING" ] || {
        PARTS+=("$STRING")
        CODES+=("")
    }
    STRING=
    LINE_TEXT=
    LINE=
    REGEX="^(([^[:space:]]*)([[:space:]]*))(.*)"
    for i in "${!PARTS[@]}"; do
        PART=${PARTS[$i]}
        CODE=${CODES[$i]}
        while [ -n "$PART" ]; do
            [[ $PART =~ $REGEX ]]
            _LINE_TEXT=$LINE_TEXT
            LINE_TEXT=$LINE_TEXT${BASH_REMATCH[2]}
            [ ${#LINE_TEXT} -le "$WIDTH" ] ||
                [ "${BASH_REMATCH[2]}" = "$LINE_TEXT" ] ||
                {
                    # If this line only exceeds WIDTH because of trailing
                    # whitespace, trim the excess
                    [[ ! $_LINE_TEXT =~ ^.{$WIDTH}([[:space:]]+)$ ]] ||
                        LINE=${LINE%${BASH_REMATCH[1]}}
                    STRING=$STRING$LINE$'\n'
                    LINE_TEXT=
                    LINE=
                    continue
                }
            LINE_TEXT=$LINE_TEXT${BASH_REMATCH[3]}
            LINE=$LINE${BASH_REMATCH[1]}
            PART=${BASH_REMATCH[4]}
            if lk_has_newline "BASH_REMATCH[3]"; then
                STRING=$STRING${LINE%$'\n'*}$'\n'
                LINE_TEXT=${LINE_TEXT##*$'\n'}
                LINE=$LINE_TEXT
            fi
        done
        LINE=$LINE$CODE
    done
    STRING=$STRING$LINE
    echo "${STRING%$'\n'}"$'\n'
}

function lk_tty_length() {
    local STRING
    STRING=$(lk_strip_non_printing "$1.")
    STRING=${STRING%.}
    echo ${#STRING}
}

function lk_console_blank() {
    echo >&"${_LK_FD:-2}"
}

function lk_tty_columns() {
    local _COLUMNS
    _COLUMNS=${COLUMNS:-${TERM:+$(TERM=$TERM tput cols)}} || _COLUMNS=
    echo "${_COLUMNS:-80}"
}

# lk_console_message MESSAGE [[MESSAGE2] COLOUR]
function lk_console_message() {
    local MESSAGE=$1 MESSAGE2 COLOUR PREFIX=${LK_TTY_PREFIX-==> } \
        WIDTH INDENT=0 SPACES LENGTH \
        MESSAGE_HAS_NEWLINE MESSAGE2_HAS_NEWLINE OUTPUT
    shift
    [ $# -le 1 ] || {
        MESSAGE2=$1
        shift
    }
    COLOUR=${1-$LK_TTY_COLOUR}
    WIDTH=${LK_TTY_WIDTH:-$(lk_tty_columns)}
    # If MESSAGE breaks over multiple lines (or will after wrapping), align
    # second and subsequent lines with the first
    ! lk_has_newline MESSAGE || MESSAGE_HAS_NEWLINE=1
    if lk_is_true MESSAGE_HAS_NEWLINE || { ! lk_is_true LK_TTY_NO_FOLD &&
        [ "$(lk_tty_length "$PREFIX$MESSAGE")" -gt "$WIDTH" ]; }; then
        SPACES=$'\n'"$(lk_repeat " " ${#PREFIX})"
        # Don't fold if MESSAGE is pre-formatted
        lk_is_true MESSAGE_HAS_NEWLINE ||
            MESSAGE=$(lk_fold "$MESSAGE" $((WIDTH - ${#PREFIX})))
        MESSAGE=${MESSAGE//$'\n'/$SPACES}
        MESSAGE_HAS_NEWLINE=1
        INDENT=2
    fi
    [ -z "${MESSAGE2:-}" ] || {
        # If MESSAGE and MESSAGE2 are both one-liners, print them on one line
        # with a space between
        ! lk_has_newline MESSAGE2 || MESSAGE2_HAS_NEWLINE=1
        if ! lk_is_true MESSAGE2_HAS_NEWLINE &&
            ! lk_is_true MESSAGE_HAS_NEWLINE &&
            { lk_is_true LK_TTY_NO_FOLD ||
                [ "$((LENGTH = $(lk_tty_length "$PREFIX$MESSAGE $MESSAGE2")))" -le "$WIDTH" ]; }; then
            MESSAGE2=" $MESSAGE2"
        else
            # Otherwise:
            # - If they both span multiple lines, or MESSAGE2 is a one-liner,
            #   keep INDENT=2 (increase MESSAGE2's left padding)
            # - If only MESSAGE2 spans multiple lines, set INDENT=-2 (decrease
            #   the left padding of MESSAGE2)
            if { lk_is_true MESSAGE2_HAS_NEWLINE || [ -n "${LENGTH:-}" ]; } &&
                ! lk_is_true MESSAGE_HAS_NEWLINE; then
                INDENT=-2
            fi
            INDENT=${LK_TTY_INDENT:-$((${#PREFIX} + INDENT))}
            SPACES=$'\n'$(lk_repeat " " "$INDENT")
            lk_is_true MESSAGE2_HAS_NEWLINE ||
                MESSAGE2=$(lk_fold "$MESSAGE2" $((WIDTH - INDENT)))
            # If a leading newline was added to force MESSAGE2 onto its own
            # line, remove it
            MESSAGE2=${MESSAGE2#$'\n'}
            MESSAGE2=$SPACES${MESSAGE2//$'\n'/$SPACES}
        fi
    }
    OUTPUT=$(
        lk_echoc -n "$PREFIX" \
            "${LK_TTY_PREFIX_COLOUR-$(lk_maybe_bold "$COLOUR")$COLOUR}"
        lk_echoc -n "$MESSAGE" \
            "${LK_TTY_MESSAGE_COLOUR-$(lk_maybe_bold "$MESSAGE")}"
        [ -z "${MESSAGE2:-}" ] ||
            lk_echoc -n "$MESSAGE2" "${LK_TTY_COLOUR2-$COLOUR}"
    )
    case "${FUNCNAME[1]:-}" in
    lk_console_list)
        declare -p WIDTH MESSAGE_HAS_NEWLINE OUTPUT
        ;;
    *)
        echo "$OUTPUT" >&"${_LK_FD:-2}"
        ;;
    esac
}

# lk_console_detail MESSAGE [MESSAGE2 [COLOUR]]
function lk_console_detail() {
    local LK_TTY_PREFIX="${LK_TTY_PREFIX-   -> }" \
        LK_TTY_MESSAGE_COLOUR=''
    lk_console_message "$1" "${2:-}" "${3-$LK_YELLOW}"
}

# lk_console_detail_list MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]
function lk_console_detail_list() {
    local LK_TTY_PREFIX="${LK_TTY_PREFIX-   -> }" \
        LK_TTY_MESSAGE_COLOUR=''
    if [ $# -le 2 ]; then
        lk_console_list "$1" "${2-$LK_YELLOW}"
    else
        lk_console_list "${@:1:3}" "${4-$LK_YELLOW}"
    fi
}

# lk_console_detail_file FILE [COLOUR] [FILE_COLOUR]
function lk_console_detail_file() {
    local LK_TTY_PREFIX="${LK_TTY_PREFIX-  >>> }" \
        LK_TTY_MESSAGE_COLOUR='' LK_TTY_INDENT=4
    lk_console_file "$1" "${2-$LK_YELLOW}" "${3-$LK_TTY_COLOUR}"
}

function _lk_tty_log() {
    local COLOUR=$1 \
        LK_TTY_PREFIX=${LK_TTY_PREFIX- :: } \
        LK_TTY_COLOUR2=${LK_TTY_COLOUR2-} \
        LK_TTY_MESSAGE_COLOUR
    shift
    [ "${1:-}" != -r ] && STATUS=0 || shift
    LK_TTY_MESSAGE_COLOUR=$(lk_maybe_bold "$1")$COLOUR
    LK_TTY_COLOUR2=${LK_TTY_COLOUR2//"$LK_BOLD"/}
    lk_console_message "$1" "${2:+$(
        BOLD=$(lk_maybe_bold "$2")
        RESET=${BOLD:+$LK_RESET}
        [ "${2:0:1}" != $'\n' ] || printf $'\n'
        echo "$BOLD${2#$'\n'}$RESET"
    )}${3:+ ${*:3}}" "$COLOUR"
}

# lk_console_log [-r] MESSAGE [MESSAGE2...]
#
# Output the given message to the console. If -r is set, return the most recent
# command's exit status.
function lk_console_log() {
    local STATUS=$?
    _lk_tty_log "$LK_TTY_COLOUR" "$@"
    return "$STATUS"
}

# lk_console_success [-r] MESSAGE [MESSAGE2...]
#
# Output the given success message to the console. If -r is set, return the most
# recent command's exit status.
function lk_console_success() {
    local STATUS=$?
    _lk_tty_log "$LK_SUCCESS_COLOUR" "$@"
    return "$STATUS"
}

# lk_console_warning [-r] MESSAGE [MESSAGE2...]
#
# Output the given warning to the console. If -r is set, return the most recent
# command's exit status.
function lk_console_warning() {
    local STATUS=$?
    _lk_tty_log "$LK_WARNING_COLOUR" "$@"
    return "$STATUS"
}

# lk_console_error [-r] MESSAGE [MESSAGE2...]
#
# Output the given error message to the console. If -r is set, return the most
# recent command's exit status.
function lk_console_error() {
    local STATUS=$?
    _lk_tty_log "$LK_ERROR_COLOUR" "$@"
    return "$STATUS"
}

# lk_console_item MESSAGE ITEM [COLOUR]
function lk_console_item() {
    lk_console_message "$1" "$2" "${3-$LK_TTY_COLOUR}"
}

# lk_console_list [-z] MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]
function lk_console_list() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-} \
        MESSAGE SINGLE PLURAL COLOUR LK_TTY_PREFIX=${LK_TTY_PREFIX-==> } \
        ITEMS INDENT=-2 LIST SPACES \
        SH WIDTH MESSAGE_HAS_NEWLINE OUTPUT
    [ "${1:-}" != -z ] || { _LK_NUL_DELIM=1 && shift; }
    MESSAGE=$1
    shift
    [ $# -le 1 ] || {
        SINGLE=$1
        PLURAL=$2
        shift 2
    }
    COLOUR=${1-$LK_TTY_COLOUR}
    [ -t 0 ] && ITEMS=() && lk_warn "no input" ||
        lk_mapfile ITEMS || lk_warn "unable to read items from input" || return
    SH=$(lk_console_message "$MESSAGE" "$COLOUR") &&
        eval "$SH" || return
    ! lk_is_true MESSAGE_HAS_NEWLINE ||
        INDENT=2
    LIST="$(lk_echo_array ITEMS |
        COLUMNS=$((WIDTH - ${#LK_TTY_PREFIX} - INDENT)) column -s $'\n' |
        expand)" || return
    SPACES="$(lk_repeat " " $((${#LK_TTY_PREFIX} + INDENT)))"
    echo "$(
        echo "$OUTPUT"
        lk_echoc "$SPACES${LIST//$'\n'/$'\n'$SPACES}" \
            "${LK_TTY_COLOUR2-$COLOUR}"
        [ -z "${SINGLE:-}" ] ||
            _LK_FD=1 \
                LK_TTY_PREFIX=$SPACES \
                lk_console_detail "(${#ITEMS[@]} $(
                lk_maybe_plural ${#ITEMS[@]} "$SINGLE" "$PLURAL"
            ))"
    )" >&"${_LK_FD:-2}"
}

function _lk_console_get_prompt() {
    lk_readline_format "$(
        lk_echoc -n " :: " \
            "${LK_TTY_PREFIX_COLOUR-$(lk_maybe_bold \
                "$LK_TTY_COLOUR")$LK_TTY_COLOUR}"
        lk_echoc -n "${PROMPT[*]//$'\n'/$'\n    '}" \
            "${LK_TTY_MESSAGE_COLOUR-$(lk_maybe_bold "${PROMPT[*]}")}"
    )"
}

# lk_console_read PROMPT [DEFAULT [READ_ARG...]]
function lk_console_read() {
    local PROMPT=("$1") DEFAULT=${2:-} VALUE
    if lk_no_input && [ $# -ge 2 ]; then
        echo "$DEFAULT"
        return 0
    fi
    [ -z "$DEFAULT" ] || PROMPT+=("[$DEFAULT]")
    read -rep "$(_lk_console_get_prompt) " "${@:3}" VALUE \
        2>&"${_LK_FD:-2}" || return
    [ -n "$VALUE" ] || VALUE=$DEFAULT
    echo "$VALUE"
}

# lk_console_read_secret PROMPT [READ_ARG...]
function lk_console_read_secret() {
    lk_console_read "$1" "" -s "${@:2}"
}

# lk_confirm PROMPT [DEFAULT [READ_ARG...]]
function lk_confirm() {
    local PROMPT=("$1") DEFAULT=${2:-} VALUE
    if lk_is_true DEFAULT; then
        PROMPT+=("[Y/n]")
        DEFAULT=Y
    elif lk_is_false DEFAULT; then
        PROMPT+=("[y/N]")
        DEFAULT=N
    else
        PROMPT+=("[y/n]")
        DEFAULT=
    fi
    if lk_no_input; then
        VALUE=$DEFAULT
    fi
    while [[ ! ${VALUE:-} =~ ^([yY]([eE][sS])?|[nN][oO]?)$ ]]; do
        read -re "${@:3}" \
            -p "$(_lk_console_get_prompt) " VALUE 2>&"${_LK_FD:-2}" &&
            [ -n "$VALUE" ] || VALUE=$DEFAULT
    done
    [[ $VALUE =~ ^[yY]([eE][sS])?$ ]]
}

function lk_no_input() {
    if ! lk_is_true LK_FORCE_INPUT; then
        [ ! -t 0 ] ||
            lk_is_true LK_NO_INPUT
    fi
}

function lk_verbose() {
    [ "${LK_VERBOSE:-0}" -ge "${1:-1}" ]
}

# lk_clip
#
# Copy input to the user's clipboard if possible, otherwise print it out.
function lk_clip() {
    local OUTPUT COMMAND LINES MESSAGE DISPLAY_LINES=${LK_CLIP_LINES:-5}
    [ ! -t 0 ] || lk_warn "no input" || return
    OUTPUT=$(cat)
    if COMMAND=$(lk_command_first_existing \
        "xclip -selection clipboard" \
        pbcopy) &&
        echo -n "$OUTPUT" | $COMMAND >/dev/null 2>&1; then
        LINES=$(wc -l <<<"$OUTPUT")
        [ "$LINES" -le "$DISPLAY_LINES" ] || {
            OUTPUT=$(head -n$((DISPLAY_LINES - 1)) <<<"$OUTPUT" &&
                echo "$LK_BOLD$LK_MAGENTA...$LK_RESET")
            MESSAGE="$LINES lines copied"
        }
        lk_console_item "${MESSAGE:-Copied} to clipboard:" \
            $'\n'"$LK_GREEN$OUTPUT$LK_RESET" "$LK_MAGENTA"
    else
        lk_console_error "Unable to copy output to clipboard"
        echo -n "$OUTPUT"
    fi
}

# lk_file_add_suffix FILENAME SUFFIX
#
# Add SUFFIX to FILENAME without changing its extension.
function lk_file_add_suffix() {
    local EXT
    [[ $1 =~ [^/]((\.tar)?\.[-a-zA-Z0-9_]+/*|/*)$ ]] &&
        EXT=${BASH_REMATCH[1]} ||
        EXT=
    echo "${1%$EXT}$2$EXT"
}

# lk_file_maybe_add_extension FILENAME EXT
#
# Add EXT to FILENAME if it's missing.
function lk_file_maybe_add_extension() {
    (
        shopt -s nocasematch
        [[ $1 == *.${2#.} ]] && echo "$1" || echo "$1.${2#.}"
    )
}

function lk_mime_type() {
    [ -e "$1" ] || lk_warn "file not found: $1" || return
    file --brief --mime-type "$1"
}

function lk_is_pdf() {
    local MIME_TYPE
    MIME_TYPE=$(lk_mime_type "$1") &&
        [ "$MIME_TYPE" = application/pdf ]
}

function _lk_regex_define() {
    eval "$(lk_get_regex)"
    while [ $# -ge 2 ]; do
        eval "function $1() {
    local $2=$(printf '%q' "${!2}")
    [[ \$1 =~ ^\$$2\$ ]]
}"
        shift 2
    done
}

_lk_regex_define \
    lk_is_host HOST_REGEX \
    lk_is_fqdn DOMAIN_NAME_REGEX \
    lk_is_email EMAIL_ADDRESS_REGEX \
    lk_is_uri URI_REGEX_REQ_SCHEME_HOST

# lk_uri_parts URI [COMPONENT...]
#
# Output Bash-compatible variable assignments for all components in URI or for
# each COMPONENT.
#
# COMPONENT can be one of: _SCHEME, _USERNAME, _PASSWORD, _HOST, _PORT, _PATH,
# _QUERY, _FRAGMENT, _IPV6_ADDRESS
function lk_uri_parts() {
    local PARTS=("${@:2}") PART VALUE
    eval "$(lk_get_regex URI_REGEX)"
    [[ $1 =~ ^$URI_REGEX$ ]] || return
    [ ${#PARTS[@]} -gt 0 ] || PARTS=(
        _SCHEME _USERNAME _PASSWORD _HOST _PORT _PATH _QUERY _FRAGMENT
        _IPV6_ADDRESS
    )
    for PART in "${PARTS[@]}"; do
        case "$PART" in
        _SCHEME)
            VALUE=${BASH_REMATCH[2]}
            ;;
        _USERNAME)
            VALUE=${BASH_REMATCH[5]}
            ;;
        _PASSWORD)
            VALUE=${BASH_REMATCH[7]}
            ;;
        _HOST)
            VALUE=${BASH_REMATCH[8]}
            ;;
        _IPV6_ADDRESS)
            VALUE=${BASH_REMATCH[9]}
            ;;
        _PORT)
            VALUE=${BASH_REMATCH[11]}
            ;;
        _PATH)
            VALUE=${BASH_REMATCH[12]}
            ;;
        _QUERY)
            VALUE=${BASH_REMATCH[14]}
            ;;
        _FRAGMENT)
            VALUE=${BASH_REMATCH[16]}
            ;;
        *)
            lk_warn "unknown URI component: $PART"
            return 1
            ;;
        esac
        _lk_var_prefix
        printf '%s=%q\n' "$PART" "$VALUE"
    done
}

# lk_get_uris [FILE...]
#
# Match and output URIs ("scheme://host" at minimum) in each FILE or input.
function lk_get_uris() {
    local REGEX_QUOTED REGEX EXIT_STATUS=0
    eval "$(lk_get_regex URI_REGEX_REQ_SCHEME_HOST)"
    REGEX_QUOTED="'($(sed -E "s/(\\[[^]']*)'([^]']*\\])/(\1\2|(\\\\\\\\'))/g" \
        <<<"$URI_REGEX_REQ_SCHEME_HOST"))'"
    REGEX="([^a-zA-Z']|^)($URI_REGEX_REQ_SCHEME_HOST)([^']|\$)"
    grep -Eo "($REGEX|$REGEX_QUOTED)" "$@" |
        sed -E \
            -e "s/^${REGEX//\//\\\/}/\2/" \
            -e "s/^${REGEX_QUOTED//\//\\\/}/\1/" || EXIT_STATUS=$?
    # `grep` returns 1 if there are no matches
    [ "$EXIT_STATUS" -eq 0 ] || [ "$EXIT_STATUS" -eq 1 ]
}

# lk_wget_uris URL
#
# Match and output URIs ("scheme://host" at minimum) in the file downloaded from
# URL. URIs are converted during download using `wget --convert-links`.
function lk_wget_uris() {
    local TEMP_FILE
    # --convert-links is disabled if wget uses standard output
    TEMP_FILE=$(lk_mktemp_file) &&
        wget --quiet --convert-links --output-document "$TEMP_FILE" "$1" ||
        return
    lk_get_uris "$TEMP_FILE"
    rm -f -- "$TEMP_FILE"
}

function lk_curl_version() {
    curl --version | awk 'NR == 1 { print $2 }' ||
        lk_warn "unable to determine curl version" || return
}

# lk_download [-s] [URI[|FILENAME]...]
#
# Download each URI to the current directory unless an up-to-date version is
# already present. If no URI arguments are given, read them from input.
#
# By default, the file name for each URI is taken from its path, and an error is
# returned if a URI has an empty or unsuitable path. To override this behaviour,
# specify the file name for a URI by adding the "|FILENAME" suffix, or set -s to
# use the file name specified by the server.
#
# IMPORTANT: if -s is set, files in the current directory with the same name as
# a server-specified file name will be overwritten, and even if they are
# up-to-date, files previously downloaded will be re-downloaded.
function lk_download() {
    local SERVER_NAMES CURL_VERSION CURL_COMMAND DOWNLOAD_DIR URI FILENAME \
        SH DOWNLOAD_ONE DOWNLOAD_ARGS \
        FILENAMES=() COMMANDS=() COMMAND_ARGS=() COMMAND
    [ "${1:-}" != -s ] || { SERVER_NAMES=1 && shift; }
    CURL_VERSION=$(lk_curl_version) || return
    CURL_COMMAND=(
        curl
        --fail
        --location
        --remote-time
    )
    ! lk_is_true SERVER_NAMES || {
        lk_version_at_least "$CURL_VERSION" 7.26.0 ||
            lk_warn "curl too old to output filename_effective" || return
        DOWNLOAD_DIR=$(lk_mktemp_dir) &&
            pushd "$DOWNLOAD_DIR" >/dev/null || return
        CURL_COMMAND+=(
            --remote-name
            --remote-header-name
            --write-out '%{filename_effective}\n'
        )
    }
    while IFS='|' read -r URI FILENAME; do
        [ -n "$URI" ] || continue
        lk_is_uri "$URI" || lk_warn "not a URI: $URI" || return
        unset DOWNLOAD_ONE
        DOWNLOAD_ARGS=()
        lk_is_true SERVER_NAMES || {
            [ -n "$FILENAME" ] || {
                SH=$(lk_uri_parts "$URI" _PATH) &&
                    eval "$SH"
                FILENAME=${_PATH##*/}
            }
            [ -n "$FILENAME" ] ||
                lk_warn "no filename in URI: $URI" || return
            [ ! -f "$FILENAME" ] || {
                # --time-cond can only be set once per invocation of curl, so
                # queue separate commands for any files downloaded previously
                DOWNLOAD_ONE=1
                DOWNLOAD_ARGS+=(--time-cond "$(lk_timestamp_readable \
                    "$(lk_file_modified "$FILENAME")")")
            }
            DOWNLOAD_ARGS+=(--output "$FILENAME")
            FILENAMES+=("$FILENAME")
        }
        DOWNLOAD_ARGS+=("$URI")
        lk_is_true DOWNLOAD_ONE || {
            COMMAND_ARGS+=("${DOWNLOAD_ARGS[@]}")
            continue
        }
        COMMANDS+=("$(lk_quote CURL_COMMAND DOWNLOAD_ARGS)")
    done < <([ $# -gt 0 ] &&
        lk_echo_args "$@" ||
        cat)
    [ ${#COMMAND_ARGS[@]} -eq 0 ] || {
        CURL_COMMAND=("${CURL_COMMAND[@]//--remote-name/--remote-name-all}")
        ! lk_version_at_least "$CURL_VERSION" 7.66.0 ||
            CURL_COMMAND+=(--parallel)
        ! lk_version_at_least "$CURL_VERSION" 7.68.0 ||
            CURL_COMMAND+=(--parallel-immediate)
        COMMANDS+=("$(lk_quote CURL_COMMAND COMMAND_ARGS)")
    }
    for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
        eval "$COMMAND" || return
    done
    lk_is_true SERVER_NAMES || {
        lk_echo_array FILENAMES
        return
    }
    popd >/dev/null && (
        shopt -s dotglob &&
            mv -f "$DOWNLOAD_DIR"/* "$PWD" &&
            rmdir "$DOWNLOAD_DIR"
    ) || return
}

# lk_can_sudo COMMAND [USERNAME]
#
# Return true if the current user is allowed to execute COMMAND via sudo.
#
# Specify USERNAME to override the default target user (usually root). Set
# LK_NO_INPUT to return false if sudo requires a password.
#
# If the current user has no sudo privileges at all, they will not be prompted
# for a password.
function lk_can_sudo() {
    local COMMAND=${1:-} USERNAME=${2:-} ERROR
    [ -n "$COMMAND" ] || lk_warn "no command" || return
    [ -z "$USERNAME" ] || lk_user_exists "$USERNAME" ||
        lk_warn "user not found: $USERNAME" || return
    # 1. sudo exists
    lk_command_exists sudo && {
        # 2. The current user (or one of their groups) appears in sudo's
        #    security policy
        ERROR=$(sudo -nv 2>&1) ||
            # "sudo: a password is required" means the user can sudo
            grep -i password <<<"$ERROR" >/dev/null
    } && {
        # 3. The current user is allowed to execute COMMAND as USERNAME (attempt
        #    with prompting disabled first)
        sudo -n ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" >/dev/null 2>&1 || {
            ! lk_no_input &&
                sudo ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" >/dev/null
        }
    }
}

function lk_will_sudo() {
    lk_is_true LK_SUDO
}

# lk_maybe_sudo COMMAND [ARG...]
#
# Run the given command line with sudo if LK_SUDO is set.
function lk_maybe_sudo() {
    if lk_is_true LK_SUDO; then
        lk_elevate "$@"
    else
        "$@"
    fi
}

# lk_elevate COMMAND [ARG...]
#
# Run the given command line with sudo unless the current user is root.
function lk_elevate() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        sudo -H "$@"
    fi
}

function lk_elevate_if_error() {
    local EXIT_STATUS=0
    "$@" || {
        EXIT_STATUS=$?
        [ "$EUID" -eq 0 ] || ! lk_can_sudo "$1" ||
            {
                EXIT_STATUS=0
                sudo -H "$@" || EXIT_STATUS=$?
            }
    }
    return "$EXIT_STATUS"
}

# lk_maybe_elevate COMMAND [ARG...]
#
# Run the given command line with sudo if the current user is allowed to,
# otherwise run it without elevation.
function lk_maybe_elevate() {
    if [ "$EUID" -eq 0 ] || ! lk_can_sudo "$1"; then
        "$@"
    else
        sudo -H "$@"
    fi
}

# lk_symlink TARGET LINK
function lk_symlink() {
    local TARGET LINK LINK_DIR CURRENT_TARGET \
        LK_BACKUP_SUFFIX=${LK_BACKUP_SUFFIX-.orig} v='' vv=''
    [ $# -eq 2 ] || lk_usage "\
Usage: $(lk_myself -f) TARGET LINK"
    TARGET=$1
    LINK=${2%/}
    LINK_DIR=${LINK%/*}
    [ "$LINK_DIR" != "$LINK" ] || LINK_DIR=.
    lk_maybe_sudo test -e "$TARGET" ||
        { [ "${TARGET:0:1}" != / ] &&
            lk_maybe_sudo test -e "$LINK_DIR/$TARGET"; } ||
        lk_warn "target not found: $TARGET" || return
    ! lk_verbose || v=v
    ! lk_verbose 2 || vv=v
    unset LK_SYMLINK_NO_CHANGE
    if lk_maybe_sudo test -L "$LINK"; then
        CURRENT_TARGET=$(lk_maybe_sudo readlink -- "$LINK") || return
        [ "$CURRENT_TARGET" != "$TARGET" ] || {
            LK_SYMLINK_NO_CHANGE=1
            return 0
        }
        lk_maybe_sudo rm -f"$vv" -- "$LINK" || return
    elif lk_maybe_sudo test -e "$LINK"; then
        if [ -n "$LK_BACKUP_SUFFIX" ]; then
            lk_maybe_sudo \
                mv -f"$v" -- "$LINK" "$LINK$LK_BACKUP_SUFFIX" || return
        else
            lk_maybe_sudo \
                rm -f"$v" -- "$LINK" || return
        fi
    elif lk_maybe_sudo test ! -d "$LINK_DIR"; then
        lk_maybe_sudo \
            mkdir -p"$v" -- "$LINK_DIR" || return
    fi
    lk_maybe_sudo ln -s"$v" -- "$TARGET" "$LINK"
}

# lk_keep_trying COMMAND [ARG...]
#
# Execute COMMAND, with an increasing delay between each attempt, until its exit
# status is zero or 10 attempts have been made. The delay starts at 5 seconds
# and follows the Fibonnaci sequence (5, 8, 13, 21, 34, etc.).
function lk_keep_trying() {
    local MAX_ATTEMPTS=${LK_KEEP_TRYING_MAX:-10} \
        ATTEMPT=0 WAIT=5 LAST_WAIT=3 NEW_WAIT EXIT_STATUS
    if ! "$@"; then
        while [ $((++ATTEMPT)) -lt "$MAX_ATTEMPTS" ]; do
            lk_console_log \
                "Command failed (attempt $ATTEMPT of $MAX_ATTEMPTS):" \
                $'\n'"$*"
            lk_console_detail "Trying again in $WAIT seconds"
            sleep "$WAIT"
            ((NEW_WAIT = WAIT + LAST_WAIT))
            LAST_WAIT=$WAIT
            WAIT=$NEW_WAIT
            lk_console_blank
            if "$@"; then
                return 0
            else
                EXIT_STATUS=$?
            fi
        done
        return "$EXIT_STATUS"
    fi
}

function lk_user_exists() {
    id "$1" >/dev/null 2>&1 || return
}

function lk_test_many() {
    local TEST="$1"
    shift
    [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        eval "$TEST \"\$1\"" || return
        shift
    done
}

function lk_paths_exist() {
    lk_test_many "test -e" "$@"
}

function lk_files_exist() {
    lk_test_many "test -f" "$@"
}

function lk_dirs_exist() {
    lk_test_many "test -d" "$@"
}

# lk_remove_false TEST ARRAY
#
# Reduce ARRAY to each element where evaluating TEST returns true after
# replacing the string '{}' with the element's value. Array indices are not
# preserved.
function lk_remove_false() {
    local _LK_TEMP_ARRAY _LK_TEST _LK_VAL i=0
    _lk_array_fill_temp "$2"
    _LK_TEST="$(lk_replace '{}' '$_LK_VAL' "$1")"
    eval "$2=()"
    for _LK_VAL in ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}; do
        ! eval "$_LK_TEST" || eval "$2[$((i++))]=\$_LK_VAL"
    done
}

# lk_remove_missing ARRAY
#
# Remove paths to missing files from ARRAY.
function lk_remove_missing() {
    lk_remove_false '[ -e "{}" ]' "$1"
}

# lk_resolve_files ARRAY
#
# Remove paths to missing files from ARRAY, then resolve remaining paths to
# absolute file names and remove any duplicates.
function lk_resolve_files() {
    local _LK_TEMP_ARRAY
    lk_remove_missing "$1" || return
    _lk_array_fill_temp "$1"
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            gnu_realpath -z "${_LK_TEMP_ARRAY[@]}" | sort -zu
    )
}

# lk_expand_path [-z] PATH
#
# Perform quote removal, tilde expansion and glob expansion on PATH, then print
# each result. If -z is set, output NUL instead of newline after each result.
# The globstar shell option must be enabled with `shopt -s globstar` for **
# globs to be expanded.
function lk_expand_path() {
    local _LK_NUL_DELIM=${_LK_NUL_DELIM-} EXIT_STATUS _PATH SHOPT DELIM q g ARR
    [ "${1:-}" != -z ] || { _LK_NUL_DELIM=1 && shift; }
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    [ -n "${1:-}" ] || lk_warn "no path" || return
    _PATH=$1
    SHOPT=$(shopt -p nullglob) || true
    shopt -s nullglob
    DELIM=${_LK_NUL_DELIM:+'\0'}
    # If the path is double- or single-quoted, remove enclosing quotes and
    # unescape
    if [[ $_PATH =~ ^\"(.*)\"$ ]]; then
        _PATH=${BASH_REMATCH[1]//\\\"/\"}
    elif [[ $_PATH =~ ^\'(.*)\'$ ]]; then
        _PATH=${BASH_REMATCH[1]//\\\'/\'}
    fi
    # Perform tilde expansion
    if [[ $_PATH =~ ^(~[-a-z0-9\$_]*)(/.*)?$ ]]; then
        # `printf '%s%q'` outputs "~username''", which doesn't expand, if used
        # with no path
        eval "_PATH=$([ -n "${BASH_REMATCH[2]}" ] &&
            printf '%s%q' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ||
            printf '%s' "${BASH_REMATCH[1]}")"
    fi
    # Expand globs
    if [[ $_PATH =~ [*?] ]]; then
        # Escape characters that have special meanings within double quotes
        _PATH=$(lk_escape "$_PATH" '$' '`' "\\" '"')
        # Add quotes around glob sequences so that when the whole path is
        # quoted, they will be unquoted
        q='"'
        for g in '\*+' '\?+'; do
            while [[ $_PATH =~ (.*([^$q${g:1:1}]|^))($g)(.*) ]]; do
                _PATH=${BASH_REMATCH[1]}$q${BASH_REMATCH[3]}$q${BASH_REMATCH[4]}
            done
        done
        eval "ARR=($q$_PATH$q)"
        [ ${#ARR[@]} -eq 0 ] ||
            printf "%s${DELIM:-\\n}" "${ARR[@]}"
    else
        printf "%s${DELIM:-\\n}" "$_PATH"
    fi
    eval "$SHOPT"
}

# lk_expand_paths ARRAY
function lk_expand_paths() {
    local _LK_TEMP_ARRAY
    _lk_array_fill_temp "$1"
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            lk_expand_path -z "${_LK_TEMP_ARRAY[@]}"
    )
}

function lk_filter() {
    local TEST="$1"
    shift
    if [ $# -gt 0 ]; then
        while [ $# -gt 0 ]; do
            ! test "$TEST" "$1" || printf '%s\n' "$1"
            shift
        done
    else
        lk_xargs lk_filter "$TEST"
    fi
}

function lk_is_identifier() {
    [[ $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

function lk_is_declared() {
    declare -p "$1" >/dev/null 2>&1
}

function lk_is_readonly() {
    (unset "$1" 2>/dev/null) || return 0
    false
}

function lk_get_var_names() {
    eval "printf '%s\n'$(printf ' ${!%s@}' _ {a..z} {A..Z})"
}

# lk_version_at_least installed_version minimum_version
function lk_version_at_least() {
    local MIN
    MIN="$(sort -V <(printf '%s\n' "$1" "$2") | head -n1 || lk_warn "error sorting versions")" &&
        [ "$MIN" = "$2" ]
}

# lk_jq_get_array ARRAY [FILTER]
#
# Apply FILTER (default: ".[]") to the input and populate ARRAY with the
# JSON-encoded value of each result.
function lk_jq_get_array() {
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    eval "$1=($(jq -r "${2:-.[]} | tostring | @sh"))"
}

# lk_jq_get_shell_var [--arg NAME VALUE]... VAR FILTER [VAR FILTER]...
function lk_jq_get_shell_var() {
    local JQ JQ_ARGS=()
    while [ "${1:-}" = --arg ]; do
        [ $# -ge 5 ] || lk_warn "invalid arguments" || return
        JQ_ARGS+=("${@:1:3}")
        shift 3
    done
    [ $# -gt 0 ] && ! (($# % 2)) || lk_warn "invalid arguments" || return
    JQ="\
def to_sh:
  to_entries[] |
    \"$(_lk_var_prefix)\(.key | ascii_upcase)=\(.value | @sh)\";
{
  $(printf '"%s": %s' "$1" "$2" && { [ $# -eq 2 ] ||
        printf ',\n  "%s": %s' "${@:3}"; })
} | to_sh"
    jq -r ${JQ_ARGS[@]+"${JQ_ARGS[@]}"} "$JQ"
}

function lk_tty() {
    if lk_is_macos; then
        function lk_tty() {
            # "-t 0" is equivalent to "-f" on Linux (immediately flush output
            # after each write)
            script -q -t 0 /dev/null "$@"
        }
    else
        function lk_tty() {
            local COMMAND=$1
            shift
            script -qfc "$COMMAND$([ $# -eq 0 ] || printf ' %q' "$@")" /dev/null
        }
    fi
    lk_tty "$@"
}

# lk_random_hex BYTES
function lk_random_hex() {
    printf '%02x' $(for i in $(seq 1 "$1"); do echo $((RANDOM % 256)); done)
}

# lk_random_password [LENGTH]
function lk_random_password() {
    local LENGTH=${1:-16} PASSWORD
    PASSWORD=$(openssl rand -base64 \
        $((BITS = LENGTH * 6, BITS / 8 + (BITS % 8 ? 1 : 0)))) &&
        printf '%s' "${PASSWORD:0:$LENGTH}"
}

function lk_base64() {
    if lk_command_exists openssl &&
        openssl base64 >/dev/null 2>&1 </dev/null; then
        # OpenSSL's implementation is ubiquitous and well-behaved
        openssl base64
    elif lk_command_exists base64 &&
        base64 --version 2>/dev/null </dev/null | grep -i gnu >/dev/null; then
        # base64 on BSD and some legacy systems (e.g. RAIDiator 4.x) doesn't
        # wrap lines by default
        base64
    else
        false
    fi
}

function lk_sort_paths_by_date() {
    if lk_command_exists "$(_lk_gnu_command stat)" &&
        lk_command_exists "$(_lk_gnu_command sed)" || ! lk_macos; then
        function lk_sort_paths_by_date() {
            gnu_stat --printf '%Y :%n\0' "$@" |
                sort -zn |
                gnu_sed -zE 's/^[0-9]+ ://' |
                xargs -0 printf '%s\n'
        }
    else
        function lk_sort_paths_by_date() {
            stat -t '%s' -f '%Sm :%N' "$@" |
                sort -n |
                sed -E 's/^[0-9]+ ://'
        }
    fi
    lk_sort_paths_by_date "$@"
}

function lk_file_modified() {
    if lk_command_exists "$(_lk_gnu_command stat)" || ! lk_macos; then
        function lk_file_modified() {
            gnu_stat --printf '%Y' "$1"
        }
    else
        function lk_file_modified() {
            stat -t '%s' -f '%Sm' "$1"
        }
    fi
    lk_file_modified "$@"
}

function lk_file_owner() {
    if lk_command_exists "$(_lk_gnu_command stat)" || ! lk_macos; then
        function lk_file_owner() {
            gnu_stat --printf '%U' "$1"
        }
    else
        function lk_file_owner() {
            stat -f '%Su' "$1"
        }
    fi
    lk_file_owner "$@"
}

function lk_file_group() {
    if lk_command_exists "$(_lk_gnu_command stat)" || ! lk_macos; then
        function lk_file_group() {
            gnu_stat --printf '%G' "$1"
        }
    else
        function lk_file_group() {
            stat -f '%Sg' "$1"
        }
    fi
    lk_file_group "$@"
}

function lk_timestamp_readable() {
    if lk_command_exists "$(_lk_gnu_command date)" || ! lk_is_macos; then
        function lk_timestamp_readable() {
            gnu_date -Rd "@$1"
        }
    else
        function lk_timestamp_readable() {
            date -Rjf '%s' "$1"
        }
    fi
    lk_timestamp_readable "$@"
}

function lk_ssl_client() {
    local HOST="${1:-}" PORT="${2:-}" SERVER_NAME="${3:-${1:-}}"
    [ -n "$HOST" ] || lk_warn "no hostname" || return
    [ -n "$PORT" ] || lk_warn "no port" || return
    openssl s_client -connect "$HOST":"$PORT" -servername "$SERVER_NAME"
}

function lk_keep_original() {
    local LK_BACKUP_SUFFIX=${LK_BACKUP_SUFFIX-.orig} VERBOSE
    ! lk_verbose 2 || VERBOSE=1
    [ -z "$LK_BACKUP_SUFFIX" ] || while [ $# -gt 0 ]; do
        lk_maybe_sudo test ! -s "$1" ||
            lk_maybe_sudo cp -naL ${VERBOSE:+-v} "$1" "$1$LK_BACKUP_SUFFIX"
        shift
    done
}

# lk_maybe_add_newline FILE
#
# Add a newline to FILE if its last byte is not a newline.
function lk_maybe_add_newline() {
    local WC
    lk_maybe_sudo test -f "$1" || lk_warn "file not found: $1" || return
    # If the last byte is a newline, `wc -l` will return 1
    WC=$(lk_maybe_sudo tail -c1 "$1" | wc -l) || return
    if lk_maybe_sudo test -s "$1" && [ "$WC" -eq 0 ]; then
        echo >>"$1"
    fi
}

# lk_maybe_replace FILE_PATH NEW_CONTENT [IGNORE_PATTERN]
function lk_maybe_replace() {
    if lk_maybe_sudo test -e "$1"; then
        lk_maybe_sudo test -f "$1" || lk_warn "file not found: $1" || return
        LK_MAYBE_REPLACE_NO_CHANGE=
        ! diff -q \
            <(lk_maybe_sudo cat "$1" | _lk_maybe_filter "${@:3:1}") \
            <([ -z "$2" ] || echo "${2%$'\n'}" | _lk_maybe_filter "${@:3:1}") \
            >/dev/null || {
            LK_MAYBE_REPLACE_NO_CHANGE=1
            ! lk_verbose 2 || lk_console_detail "Not changed:" "$1"
            return 0
        }
        lk_keep_original "$1" || return
    fi
    echo "${2%$'\n'}" | lk_maybe_sudo tee "$1" >/dev/null || return
    ! lk_verbose || {
        if lk_is_true LK_NO_DIFF; then
            lk_console_detail "Updated:" "$1"
        else
            lk_console_file "$1"
        fi
    }
}

function _lk_maybe_filter() {
    if [ -n "${1:-}" ]; then
        sed -E "/$1/d"
    else
        cat
    fi
}

# lk_console_file FILE [COLOUR_SEQUENCE] [FILE_COLOUR_SEQUENCE]
#
# Output the diff between FILE{SUFFIX} and FILE, or all lines in FILE if SUFFIX
# is the null string or FILE{SUFFIX} does not exist, where SUFFIX is
# LK_BACKUP_SUFFIX or ".orig" if LK_BACKUP_SUFFIX is not set.
function lk_console_file() {
    local FILE=$1 ORIG_FILE BOLD_COLOUR \
        LK_TTY_PREFIX=${LK_TTY_PREFIX:->>> } \
        LK_TTY_MESSAGE_COLOUR='' LK_TTY_COLOUR2='' \
        COLOUR=${2-${LK_TTY_MESSAGE_COLOUR-$LK_MAGENTA}} \
        FILE_COLOUR=${3-${LK_TTY_COLOUR2-${2:-$LK_GREEN}}} \
        LK_TTY_INDENT=${LK_TTY_INDENT:-2}
    BOLD_COLOUR="$(lk_maybe_bold "$COLOUR")$COLOUR"
    local LK_TTY_PREFIX_COLOUR=${LK_TTY_PREFIX_COLOUR-$BOLD_COLOUR}
    lk_maybe_sudo test -r "$FILE" ||
        lk_warn "cannot read file: $FILE" || return
    ORIG_FILE=$FILE${LK_BACKUP_SUFFIX-.orig}
    [ "$FILE" != "$ORIG_FILE" ] &&
        lk_maybe_sudo test -r "$ORIG_FILE" || ORIG_FILE=
    lk_console_item "$BOLD_COLOUR$FILE$LK_RESET" "$(
        if [ -n "$ORIG_FILE" ]; then
            # TODO: add alternative implementation if GNU diff is missing
            ! lk_maybe_sudo gnu_diff --unified --color=always \
                "$ORIG_FILE" "$FILE" || echo "$FILE_COLOUR<unchanged>"
        else
            echo -n "$FILE_COLOUR"
            lk_maybe_sudo cat "$FILE"
        fi
    )"$'\n'"$LK_TTY_PREFIX_COLOUR<<<$LK_RESET"
}

# lk_user_in_group username groupname...
#   True if USERNAME belongs to at least one of GROUPNAME.
function lk_user_in_group() {
    [ "$(comm -12 \
        <(groups "$1" | sed -E 's/^.*://' | grep -Eo '[^[:blank:]]+' | sort) \
        <(lk_echo_args "${@:2}" | sort -u) | wc -l)" -gt 0 ]
}

# lk_make_iso path...
#  Add each PATH to a new ISO image in the current directory. The .iso file
#  is named after the first file or directory specified.
function lk_make_iso() {
    local ISOFILE
    lk_paths_exist "$@" || lk_warn "all paths must exist" || return
    ISOFILE="${1##*/}.iso"
    [ ! -e "$ISOFILE" ] || lk_warn "$ISOFILE already exists" || return
    mkisofs -V "$(lk_date "%y%m%d")${1##*/}" -J -r -hfs -o "$ISOFILE" "$@"
}

set -o pipefail

_LK_INCLUDES=(core)

case "${TERM:-dumb}" in
dumb | unknown)
    LK_BLACK=
    LK_RED=
    LK_GREEN=
    LK_YELLOW=
    LK_BLUE=
    LK_MAGENTA=
    LK_CYAN=
    LK_WHITE=
    LK_GREY=
    LK_BLACK_BG=
    LK_RED_BG=
    LK_GREEN_BG=
    LK_YELLOW_BG=
    LK_BLUE_BG=
    LK_MAGENTA_BG=
    LK_CYAN_BG=
    LK_WHITE_BG=
    LK_GREY_BG=
    LK_BOLD=
    LK_DIM=
    LK_STANDOUT=
    LK_STANDOUT_OFF=
    LK_WRAP=
    LK_WRAP_OFF=
    LK_RESET=
    ;;
xterm-256color)
    LK_BLACK=$'\E[30m'
    LK_RED=$'\E[31m'
    LK_GREEN=$'\E[32m'
    LK_YELLOW=$'\E[33m'
    LK_BLUE=$'\E[34m'
    LK_MAGENTA=$'\E[35m'
    LK_CYAN=$'\E[36m'
    LK_WHITE=$'\E[37m'
    LK_GREY=$'\E[90m'
    LK_BLACK_BG=$'\E[40m'
    LK_RED_BG=$'\E[41m'
    LK_GREEN_BG=$'\E[42m'
    LK_YELLOW_BG=$'\E[43m'
    LK_BLUE_BG=$'\E[44m'
    LK_MAGENTA_BG=$'\E[45m'
    LK_CYAN_BG=$'\E[46m'
    LK_WHITE_BG=$'\E[47m'
    LK_GREY_BG=$'\E[100m'
    LK_BOLD=$'\E[1m'
    LK_DIM=$'\E[2m'
    LK_STANDOUT=$'\E[7m'
    LK_STANDOUT_OFF=$'\E[27m'
    LK_WRAP=$'\E[?7h'
    LK_WRAP_OFF=$'\E[?7l'
    LK_RESET=$'\E(B\E[m'
    ;;
*)
    eval "$(lk_get_colours)"
    ;;
esac

LK_TTY_COLOUR=$LK_CYAN
LK_SUCCESS_COLOUR=$LK_GREEN
LK_WARNING_COLOUR=$LK_YELLOW
LK_ERROR_COLOUR=$LK_RED
lk_is_readonly LK_ARGV || readonly LK_ARGV=("$@")
lk_is_readonly S || readonly S="[[:blank:]]"
lk_is_readonly NS || readonly NS="[^[:blank:]]"

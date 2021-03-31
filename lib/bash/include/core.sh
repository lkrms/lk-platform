#!/bin/bash

# shellcheck disable=SC2046,SC2086,SC2094,SC2116,SC2120

export -n BASH_XTRACEFD SHELLOPTS
[ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)

USER=${USER:-$(id -un)} || return

# lk_bash_at_least MAJOR [MINOR]
function lk_bash_at_least() {
    [ "${BASH_VERSINFO[0]}" -eq "$1" ] &&
        [ "${BASH_VERSINFO[1]}" -ge "${2:-0}" ] ||
        [ "${BASH_VERSINFO[0]}" -gt "$1" ]
}

function lk_command_exists() {
    type -P "$1" >/dev/null
}

function lk_is_macos() {
    [[ $OSTYPE == darwin* ]]
}

function lk_is_apple_silicon() {
    lk_is_macos && [[ $MACHTYPE =~ ^(arm|aarch)64- ]]
}

function lk_is_linux() {
    [[ $OSTYPE == linux-gnu ]]
}

function lk_is_arch() {
    lk_is_linux && [ -f /etc/arch-release ]
}

function lk_is_ubuntu() {
    lk_is_linux && [ -r /etc/os-release ] &&
        (. /etc/os-release && [ "$NAME" = Ubuntu ])
}

function lk_ubuntu_at_least() {
    lk_is_linux && [ -r /etc/os-release ] &&
        (. /etc/os-release && [ "$NAME" = Ubuntu ] &&
            lk_version_at_least "$VERSION_ID" "$1")
}

function lk_is_wsl() {
    lk_is_linux && grep -qi Microsoft /proc/version &>/dev/null
}

function lk_is_desktop() {
    lk_node_service_enabled desktop
}

function lk_is_virtual() {
    lk_is_linux &&
        grep -Eq "^flags$S*:.*\\bhypervisor\\b" /proc/cpuinfo
}

function lk_is_qemu() {
    lk_is_virtual &&
        (shopt -s nullglob &&
            FILES=(/sys/devices/virtual/dmi/id/*_vendor) &&
            [ ${#FILES[@]} -gt 0 ] &&
            grep -iq qemu "${FILES[@]}")
}

# lk_first_existing [FILE...]
function lk_first_existing() {
    while [ $# -gt 0 ]; do
        ! lk_maybe_sudo test -e "$1" || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

if lk_bash_at_least 4 0; then
    function lk_eval_input() {
        . /dev/stdin
    }
else
    # On Bash 3.2, output is "lost when a redirection is acting on the shell's
    # output file descriptor", which seems to be why these don't work
    # consistently:
    # - . /dev/stdin
    # - . <(cat /dev/stdin)
    function lk_eval_input() {
        local FILE STATUS=0
        FILE=$(mktemp) && {
            cat >"$FILE" &&
                . "$FILE" || STATUS=$?
            rm -f -- "$FILE" || true
            return "$STATUS"
        }
    }
fi

_LK_GNU_COMMANDS=(
    awk
    chgrp chmod chown cp
    date df diff du
    find
    getopt grep
    ln
    mktemp mv
    realpath
    sed sort stat
    tar
    xargs
)

#### Reviewed: 2021-01-28

_LK_CACHE=$(
    b=${LK_INST:-${LK_BASE:-}}
    s=/
    [ -n "$b" ] &&
        [ "$b/lib/bash/include/core.sh" -ef "${BASH_SOURCE[0]:-}" ] &&
        echo ~/.lk-platform/cache/${b//"$s"/__}
) && { [ -d "$_LK_CACHE" ] || install -d -m 00755 "$_LK_CACHE"; } || _LK_CACHE=

function _lk_from_cache() {
    local FILE=$_LK_CACHE/$1.sh
    [ -n "$_LK_CACHE" ] && [ "$FILE" -nt "${BASH_SOURCE[0]}" ] &&
        . "$FILE"
}

function _lk_to_cache() {
    local FILE=$_LK_CACHE/$1.sh
    if [ -n "$_LK_CACHE" ]; then
        cat >"$FILE" && . "$FILE"
    else
        lk_eval_input
    fi
}

function _lk_gnu_command() {
    local COMMAND PREFIX=
    ! lk_is_macos || {
        PREFIX=g
        HOMEBREW_PREFIX=${HOMEBREW_PREFIX-$(brew --prefix 2>/dev/null)} ||
            HOMEBREW_PREFIX=
        COMMAND=${HOMEBREW_PREFIX:-$(lk_is_apple_silicon &&
            echo /opt/homebrew ||
            echo /usr/local)}
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

# Define wrapper functions (e.g. `gnu_find`) to invoke the GNU version of
# certain commands (e.g. `gfind`) on systems where standard utilities are not
# compatible with their GNU counterparts, e.g. BSD/macOS
_lk_from_cache gnu || {
    function _lk_gnu_define() {
        local COMMAND
        for COMMAND in "${_LK_GNU_COMMANDS[@]}"; do
            printf 'function gnu_%s() { lk_maybe_sudo %q "$@"; }\n' \
                "$COMMAND" "$(_lk_gnu_command "$COMMAND")"
        done
    }
    _lk_to_cache gnu < <(_lk_gnu_define)
    unset -f _lk_gnu_define
}

function lk_gnu_check() {
    while [ $# -gt 0 ]; do
        lk_command_exists "$(_lk_gnu_command "$1")" || return
        shift
    done
} #### Reviewed: 2021-03-26

function lk_include() {
    local i FILE
    for i in "$@"; do
        ! lk_in_array "$i" _LK_INCLUDES || continue
        FILE=${LK_INST:-$LK_BASE}/lib/bash/include/$i.sh
        [ -r "$FILE" ] || lk_warn "$FILE: file not found" || return
        . "$FILE" || return
    done
}

function lk_provide() {
    _LK_INCLUDES+=("$1")
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
        echo "${FUNCNAME[$((1 + ${1:-0} + ${_LK_STACK_DEPTH:-0}))]:-${0##*/}}"
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
                lk_pretty_path "$SOURCE"
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
        -e "s/^($S*([uU]sage|[oO]r):$S+(sudo )?)($CMD)($S|\$)/\1$BOLD\4$RESET\5/" \
        -e "s/^[a-zA-Z0-9 ]+:\$/$BOLD&$RESET/" \
        -e "s/^\\\\($NS)/\\1/" <<<"$1"
}

function lk_usage() {
    local EXIT_STATUS=$? MESSAGE=${1:-${LK_USAGE:-}}
    [ -z "$MESSAGE" ] || MESSAGE=$(_lk_usage_format "$MESSAGE")
    LK_TTY_NO_FOLD=1 \
        lk_console_log "${MESSAGE:-$(_lk_caller): invalid arguments}"
    if lk_is_script_running; then
        exit "$EXIT_STATUS"
    else
        return "$EXIT_STATUS"
    fi
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
    case "${FUNCNAME[$((${_LK_STACK_DEPTH:-0} + 2))]:-}" in
    '' | source | main)
        return
        ;;
    esac
    printf 'local '
}

_lk_from_cache regex || {
    function _lk_regex_sh() {
        printf 'local %s=%q\n' "$1" "$2"
        printf '_LK_REGEX[$((i++))]=%s\n' "$1"
    }
    function _lk_regex() {
        local _O _H _P _S _U _A _Q _F _1 _2 _4 _6 SH i=0 _LK_REGEX=() REGEX

        SH=$(_lk_regex_sh DOMAIN_PART_REGEX "[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?") && eval "$SH"
        SH=$(_lk_regex_sh DOMAIN_NAME_REGEX "$DOMAIN_PART_REGEX(\\.$DOMAIN_PART_REGEX)+") && eval "$SH"
        SH=$(_lk_regex_sh EMAIL_ADDRESS_REGEX "[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~]([-a-zA-Z0-9.!#\$%&'*+/=?^_\`{|}~]{,62}[-a-zA-Z0-9!#\$%&'*+/=?^_\`{|}~])?@$DOMAIN_NAME_REGEX") && eval "$SH"

        _O="(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])"
        SH=$(_lk_regex_sh IPV4_REGEX "($_O\\.){3}$_O") && eval "$SH"
        SH=$(_lk_regex_sh IPV4_OPT_PREFIX_REGEX "$IPV4_REGEX(/(3[0-2]|[12][0-9]|[1-9]))?") && eval "$SH"

        _H="[0-9a-fA-F]{1,4}"
        _P="/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])"
        SH=$(_lk_regex_sh IPV6_REGEX "(($_H:){7}(:|$_H)|($_H:){6}(:|:$_H)|($_H:){5}(:|(:$_H){1,2})|($_H:){4}(:|(:$_H){1,3})|($_H:){3}(:|(:$_H){1,4})|($_H:){2}(:|(:$_H){1,5})|$_H:(:|(:$_H){1,6})|:(:|(:$_H){1,7}))") && eval "$SH"
        SH=$(_lk_regex_sh IPV6_OPT_PREFIX_REGEX "$IPV6_REGEX($_P)?") && eval "$SH"

        SH=$(_lk_regex_sh IP_REGEX "($IPV4_REGEX|$IPV6_REGEX)") && eval "$SH"
        SH=$(_lk_regex_sh IP_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX)") && eval "$SH"
        SH=$(_lk_regex_sh HOST_NAME_REGEX "($DOMAIN_PART_REGEX(\\.$DOMAIN_PART_REGEX)*)") && eval "$SH"
        SH=$(_lk_regex_sh HOST_REGEX "($IPV4_REGEX|$IPV6_REGEX|$HOST_NAME_REGEX)") && eval "$SH"
        SH=$(_lk_regex_sh HOST_OPT_PREFIX_REGEX "($IPV4_OPT_PREFIX_REGEX|$IPV6_OPT_PREFIX_REGEX|$HOST_NAME_REGEX)") && eval "$SH"

        # https://en.wikipedia.org/wiki/Uniform_Resource_Identifier
        _S="[a-zA-Z][-a-zA-Z0-9+.]*"                               # scheme
        _U="[-a-zA-Z0-9._~%!\$&'()*+,;=]+"                         # username
        _P="[-a-zA-Z0-9._~%!\$&'()*+,;=]*"                         # password
        _H="([-a-zA-Z0-9._~%!\$&'()*+,;=]+|\\[([0-9a-fA-F:]+)\\])" # host
        _O="[0-9]+"                                                # port
        _A="[-a-zA-Z0-9._~%!\$&'()*+,;=:@/]+"                      # path
        _Q="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]+"                     # query
        _F="[-a-zA-Z0-9._~%!\$&'()*+,;=:@?/]*"                     # fragment
        SH=$(_lk_regex_sh URI_REGEX "(($_S):)?(//(($_U)(:($_P))?@)?$_H(:($_O))?)?($_A)?(\\?($_Q))?(#($_F))?") && eval "$SH"
        SH=$(_lk_regex_sh URI_REGEX_REQ_SCHEME_HOST "(($_S):)(//(($_U)(:($_P))?@)?$_H(:($_O))?)($_A)?(\\?($_Q))?(#($_F))?") && eval "$SH"

        SH=$(_lk_regex_sh LINUX_USERNAME_REGEX "[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\\\$)") && eval "$SH"
        SH=$(_lk_regex_sh MYSQL_USERNAME_REGEX "[a-zA-Z0-9_]+") && eval "$SH"

        # https://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-source
        SH=$(_lk_regex_sh DPKG_SOURCE_REGEX "[a-z0-9][-a-z0-9+.]+") && eval "$SH"

        SH=$(_lk_regex_sh IDENTIFIER_REGEX "[a-zA-Z_][a-zA-Z0-9_]*") && eval "$SH"
        SH=$(_lk_regex_sh PHP_SETTING_NAME_REGEX "$IDENTIFIER_REGEX(\\.$IDENTIFIER_REGEX)*") && eval "$SH"
        SH=$(_lk_regex_sh PHP_SETTING_REGEX "$PHP_SETTING_NAME_REGEX=.+") && eval "$SH"

        SH=$(_lk_regex_sh READLINE_NON_PRINTING_REGEX $'\x01[^\x02]*\x02') && eval "$SH"
        SH=$(_lk_regex_sh CONTROL_SEQUENCE_REGEX $'\x1b\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]') && eval "$SH"
        SH=$(_lk_regex_sh ESCAPE_SEQUENCE_REGEX $'\x1b[\x20-\x2f]*[\x30-\x7e]') && eval "$SH"
        SH=$(_lk_regex_sh NON_PRINTING_REGEX $'(\x01[^\x02]*\x02|\x1b(\\\x5b[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]|[\x20-\x2f]*[\x30-\x5a\\\x5c-\x7e]))') && eval "$SH"

        # *_FILTER_REGEX expressions are:
        # 1. anchored
        # 2. not intended for validation
        SH=$(_lk_regex_sh IPV4_PRIVATE_FILTER_REGEX "^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|127\\.)") && eval "$SH"

        _1="[0-9]"
        _2="$_1$_1"
        _4="$_2$_2"
        _6="$_2$_2$_2"
        SH=$(_lk_regex_sh BACKUP_TIMESTAMP_FINDUTILS_REGEX "$_4-$_2-$_2-$_6") && eval "$SH"

        # lk_is_identifier, lk_is_fqdn, etc.
        while [ $# -ge 2 ]; do
            printf 'function %s() { local %s=%q; [[ $1 =~ ^$%s$ ]]; }\n' \
                "$1" "$2" "${!2}" "$2"
            shift 2
        done

        # _lk_get_regex
        SH=$(for REGEX in "${_LK_REGEX[@]}"; do
            printf "%s) printf '%%s=%%q\\\\n' %q %q ;;\n" \
                "$REGEX" "$REGEX" "${!REGEX}"
        done)
        printf 'function %s() { local EXIT_STATUS=0; while [ $# -gt 0 ]; do
    _lk_var_prefix; case "$1" in
        %s
        *) lk_warn "regex not found: $1"; EXIT_STATUS=1 ;;
    esac; shift
done; return "$EXIT_STATUS"; }\n' _lk_get_regex "${SH//$'\n'/$'\n        '}"

        # __lk_regex_* and _LK_REGEX variables
        for REGEX in "${_LK_REGEX[@]}"; do
            printf '__lk_regex_%s=%q\n' "$REGEX" "${!REGEX}"
        done
        printf '%s=(%s)\n' _LK_REGEX "${_LK_REGEX[*]}"
    }
    _lk_to_cache regex < <(_lk_regex \
        lk_is_host HOST_REGEX \
        lk_is_fqdn DOMAIN_NAME_REGEX \
        lk_is_email EMAIL_ADDRESS_REGEX \
        lk_is_uri URI_REGEX_REQ_SCHEME_HOST \
        lk_is_identifier IDENTIFIER_REGEX)
    unset -f _lk_regex_sh _lk_regex
}

# lk_get_regex [REGEX_NAME...]
#
# Output Bash-compatible variable assignments for all available regular
# expressions or for each REGEX_NAME.
function lk_get_regex() {
    [ $# -gt 0 ] || set -- "${_LK_REGEX[@]}"
    _LK_STACK_DEPTH=1 \
        _lk_get_regex "$@"
}

if lk_bash_at_least 4 2; then
    # lk_date FORMAT [TIMESTAMP]
    function lk_date() {
        # Take advantage of printf support for strftime in Bash 4.2+
        printf "%($1)T\n" "${2:--1}"
    }
else
    if ! lk_is_macos; then
        # lk_date FORMAT [TIMESTAMP]
        function lk_date() {
            gnu_date ${2:+-d "@$2"} +"$1"
        }
    else
        # lk_date FORMAT [TIMESTAMP]
        function lk_date() {
            date ${2:+-jf '%s' "$2"} +"$1"
        }
    fi
fi #### Reviewed: 2021-03-26

# lk_date_log [TIMESTAMP]
function lk_date_log() {
    lk_date "%Y-%m-%d %H:%M:%S %z" "$@"
} #### Reviewed: 2021-03-26

# lk_date_ymdhms [TIMESTAMP]
function lk_date_ymdhms() {
    lk_date "%Y%m%d%H%M%S" "$@"
} #### Reviewed: 2021-03-26

# lk_date_ymd [TIMESTAMP]
function lk_date_ymd() {
    lk_date "%Y%m%d" "$@"
} #### Reviewed: 2021-03-26

# lk_timestamp
function lk_timestamp() {
    lk_date "%s"
} #### Reviewed: 2021-03-26

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

function lk_double_quote() {
    local STRING
    STRING=$(lk_escape "$1." '$' '`' "\\" '"')
    printf '"%s"\n' "${STRING%.}"
}

function lk_get_shell_var() {
    while [ $# -gt 0 ]; do
        if [ -n "${!1:-}" ]; then
            printf '%s=%s\n' "$1" "$(lk_double_quote "${!1}")"
        else
            printf '%s=\n' "$1"
        fi
        shift
    done
}

function lk_get_quoted_var() {
    while [ $# -gt 0 ]; do
        _lk_var_prefix
        if [ -n "${!1:-}" ]; then
            printf '%s=%q\n' "$1" "${!1}"
        else
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_get_env [-n] [VAR...]
function lk_get_env() {
    local _LK_VAR_LIST _LK_IGNORE_REGEX="^(__?(LK|lk)|(PATH|BASH_XTRACEFD)$)"
    unset _LK_VAR_LIST
    [ "${1:-}" != -n ] || { _LK_VAR_LIST= && shift; }
    [ -n "${_LK_ENV+1}" ] || _LK_ENV=$(declare -x)
    (
        # Unset every variable that can be unset
        unset $(lk_var_list |
            sed -E "/$_LK_IGNORE_REGEX/d") 2>/dev/null || true
        # Ignore the rest
        _LK_IGNORE=$(lk_var_list |
            sed -E "/$_LK_IGNORE_REGEX/d")
        # Restore environment variables
        eval "$_LK_ENV" 2>/dev/null
        # Reduce the selection to variables not being ignored
        set -- $(comm -13 \
            <(sort -u <<<"$_LK_IGNORE") \
            <({ [ $# -gt 0 ] && lk_echo_args "$@" || lk_var_list; } |
                sed -E "/$_LK_IGNORE_REGEX/d" | sort -u))
        [ $# -eq 0 ] ||
            _LK_STACK_DEPTH=1 \
                ${_LK_VAR_LIST-lk_get_quoted_var} \
                ${_LK_VAR_LIST+lk_echo_args} \
                "$@"
    )
}

# lk_check_pid PID
#
# Return true if a signal could be sent to the given process by the current
# user.
function lk_check_pid() {
    [ $# -eq 1 ] || return
    lk_maybe_sudo kill -0 "$1" 2>/dev/null
}

function lk_escape_ere() {
    lk_escape "$1" '$' '(' ')' '*' '+' '.' '/' '?' '[' "\\" ']' '^' '{' '|' '}'
}

function lk_escape_input_ere() {
    sed -E 's/[]$()*+./?\^{|}[]/\\&/g'
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
    [ $# -gt 0 ] || lk_warn "no string" || return
    [ -n "$1" ] || return 0
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

# lk_regex_expand_whitespace [-o] STRING
#
# Replace each unquoted sequence of one or more whitespace characters in STRING
# with "[[:blank:]]+". If -o is set, make whitespace optional with
# "[[:blank:]]*". Escaped delimiters within double- and single-quoted sequences
# are recognised.
#
# Example:
#
#     $ lk_regex_expand_whitespace "message = 'Here\'s a message'"
#     message[[:blank:]]+=[[:blank:]]+'Here\'s a message'
function lk_regex_expand_whitespace() {
    local NOT_SPECIAL="[^'\"[:blank:]]*[^\\]" \
        ESCAPED_WHITESPACE="(\\\\[[:blank:]])*" \
        QUOTED_SINGLE="(''|'([^']|\\\\')*[^\\]')" \
        QUOTED_DOUBLE="(\"\"|\"([^\"]|\\\\\")*[^\\]\")" \
        QUANTIFIER="+"
    [ "${1:-}" != -o ] || { QUANTIFIER="*" && shift; }
    sed -E "\
:start
s/^(($NOT_SPECIAL|$ESCAPED_WHITESPACE|$QUOTED_SINGLE|$QUOTED_DOUBLE)*)$S+/\\1[[:blank:]]$QUANTIFIER/
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

function lk_var_list() {
    eval "printf '%s\n'$(printf ' "${!%s@}"' {a..z} {A..Z} _)"
}

# lk_expand_template [-e] [-q] [FILE]
#
# Replace each {{KEY}} in FILE or input with the value of variable KEY. If -e is
# set, also replace each ({:LIST:}) with the output of `eval LIST`. If -q is
# set, use `printf %q` to quote each replacement value.
function lk_expand_template() {
    local OPTIND OPTARG OPT EVAL QUOTE TEMPLATE KEYS i REPLACE KEY
    unset EVAL QUOTE
    while getopts ":eq" OPT; do
        case "$OPT" in
        e)
            EVAL=1
            ;;
        q)
            QUOTE=1
            ;;
        \? | :)
            lk_usage "\
Usage: $(lk_myself -f) [-e] [-q] [FILE]"
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    TEMPLATE=$(cat ${1+"$1"} && printf .) || return
    ! lk_is_true EVAL || {
        lk_mapfile KEYS <(
            printf '%q' "$TEMPLATE" |
                sed -E \
                    -e "s/$(lk_escape_ere "$(printf '%q' "({:")")/\(\{:/g" \
                    -e "s/$(lk_escape_ere "$(printf '%q' ":})")")/:\}\)/g" |
                grep -Eo '\(\{:([^:]*|:[^}]|:\}[^)])*:\}\)' |
                sort -u
        )
        [ ${#KEYS[@]} -eq 0 ] ||
            for i in $(seq 0 $((${#KEYS[@]} - 1))); do
                eval "KEYS[$i]=\$'${KEYS[$i]:3:$((${#KEYS[$i]} - 6))}'"
                eval "REPLACE=\$({ ${KEYS[$i]}"$'\n'"} && printf .)" ||
                    lk_warn "error evaluating: ${KEYS[$i]}" || return
                ! lk_is_true QUOTE ||
                    REPLACE=$(printf '%q.' "${REPLACE%.}")
                REPLACE=${REPLACE%.}
                TEMPLATE=${TEMPLATE//"({:${KEYS[$i]}:})"/$REPLACE}
            done
    }
    KEYS=($(echo "$TEMPLATE" |
        grep -Eo '\{\{[a-zA-Z_][a-zA-Z0-9_]*\}\}' | sort -u |
        sed -E 's/^\{\{([a-zA-Z0-9_]+)\}\}$/\1/')) || true
    for KEY in ${KEYS[@]+"${KEYS[@]}"}; do
        [ -n "${!KEY+1}" ] ||
            lk_warn "variable not set: $KEY" || return
        REPLACE=${!KEY}
        ! lk_is_true QUOTE || {
            REPLACE=$(printf '%q.' "$REPLACE")
            REPLACE=${REPLACE%.}
        }
        TEMPLATE=${TEMPLATE//"{{$KEY}}"/$REPLACE}
    done
    TEMPLATE=${TEMPLATE%.}
    echo "${TEMPLATE%$'\n'}"
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
    _lk_array_fill_temp "${@:2}" &&
        "${_LK_COMMAND[@]}" ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}
}

# lk_echo_args [-z] [ARG...]
function lk_echo_args() {
    local DELIM=${LK_Z:+'\0'}
    [ "${1:-}" != -z ] || { DELIM='\0' && shift; }
    [ $# -eq 0 ] ||
        printf "%s${DELIM:-\\n}" "$@"
}

# lk_echo_array [-z] [ARRAY...]
function lk_echo_array() {
    local LK_Z=${LK_Z-}
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    _lk_array_action lk_echo_args "$@"
}

# lk_array_merge NEW_ARRAY [ARRAY...]
function lk_array_merge() {
    [ $# -ge 2 ] || return
    eval "$1=($(for i in "${@:2}"; do
        printf '${%s[@]+"${%s[@]}"}\n' "$i" "$i"
    done))"
}

# lk_quote_args [ARG...]
#
# Use `printf %q` to output each ARG on a single space-delimited line.
#
# Example:
#
#     $ lk_quote_args printf '%s\n' "Hello, world."
#     printf %s\\n Hello\,\ world.
function lk_quote_args() {
    [ $# -eq 0 ] || printf '%q' "$1"
    [ $# -le 1 ] || printf ' %q' "${@:2}"
    printf '\n'
}

# lk_quote_args_folded [ARG...]
#
# Same as lk_quote_args, but start each ARG on a new line.
#
# Example:
#
#     $ lk_quote_args_folded printf '%s\n' "Hello, world."
#     printf \
#         %s\\n \
#         Hello\,\ world.
function lk_quote_args_folded() {
    [ $# -eq 0 ] || printf '%q' "$1"
    [ $# -le 1 ] || printf ' \\\n    %q' "${@:2}"
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

# lk_implode_input [GLUE]
function lk_implode_input() {
    awk -v "OFS=${1:-,}" 'NR > 1 { printf "%s", OFS } { printf "%s", $0 }'
}

# lk_in_array VALUE ARRAY [ARRAY...]
#
# Return true if VALUE exists in any ARRAY, otherwise return false.
function lk_in_array() {
    local _LK_ARRAY _LK_VAL
    for _LK_ARRAY in "${@:2}"; do
        _LK_ARRAY="${_LK_ARRAY}[@]"
        for _LK_VAL in ${!_LK_ARRAY+"${!_LK_ARRAY}"}; do
            [ "$_LK_VAL" = "$1" ] || continue
            return 0
        done
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
    local LK_Z=${LK_Z-} _LK_NUL_READ=(-d '') _LK_LINE _LK_STATUS=0
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    while IFS= read -r ${LK_Z:+"${_LK_NUL_READ[@]}"} _LK_LINE ||
        [ -n "$_LK_LINE" ]; do
        "$@" "$_LK_LINE" || _LK_STATUS=$?
    done
    return "$_LK_STATUS"
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
    local LK_Z=${LK_Z-} COMMAND
    # Check for -z and no value arguments, i.e. NUL-delimited input
    [ "${2:-}" != -z ] || (($# - $1 - 2)) ||
        { LK_Z=1 && set -- "$1" "${@:3}"; }
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
    local LK_Z=${LK_Z-} _LK_NUL_READ=(-d '') _LK_LINE _lk_i=0
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    [ -z "${2:-}" ] ||
        [ -e "$2" ] || lk_warn "file not found: $2" || return
    eval "$1=()"
    while IFS= read -r ${LK_Z:+"${_LK_NUL_READ[@]}"} _LK_LINE ||
        [ -n "$_LK_LINE" ]; do
        eval "$1[$((_lk_i++))]=\$_LK_LINE"
    done < <(cat ${2+"$2"})
}

function lk_has_arg() {
    lk_in_array "$1" "${LK_ARG_ARRAY:-LK_ARGV}"
}

function lk_pass() {
    local STATUS=$?
    "$@" || true
    return $STATUS
} #### Reviewed: 2021-03-25

function _lk_cache_dir() {
    echo "${_LK_OUTPUT_CACHE:=$(
        TMPDIR=${TMPDIR:-/tmp}
        DIR=${TMPDIR%/}/_lk_output_cache_${EUID}_$$
        install -d -m 00700 "$DIR" && echo "$DIR"
    )}"
} #### Reviewed: 2021-03-25

# lk_cache [-t TTL] COMMAND [ARG...]
#
# Print output from a previous run if possible, otherwise execute the command
# line and cache its output in a transient per-process cache. If -t is set, use
# cached output for up to TTL seconds (default: 300). If TTL is 0, use cached
# output indefinitely.
function lk_cache() {
    local TTL=300 FILE AGE s=/
    [ "${1:-}" != -t ] || { TTL=$2 && shift 2; }
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__} &&
        { [ ! -f "${FILE}_dirty" ] || rm -f "$FILE"*; } || return
    FILE+=_${FUNCNAME[1]}_$(lk_hash "$@") || return
    if [ -f "$FILE" ] &&
        { [ "$TTL" -eq 0 ] ||
            { AGE=$(lk_file_age "$FILE") &&
                [ "$AGE" -lt "$TTL" ]; }; }; then
        cat "$FILE"
    else
        "$@" | tee "$FILE" || lk_pass rm -f "$FILE"
    fi
} #### Reviewed: 2021-03-25

function lk_cache_mark_dirty() {
    local FILE s=/
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__}_dirty || return
    touch "$FILE"
} #### Reviewed: 2021-03-25

# lk_get_outputs_of COMMAND [ARG...]
#
# Execute COMMAND, output Bash-compatible code that sets _STDOUT and _STDERR to
# COMMAND's respective outputs, and exit with COMMAND's exit status.
function lk_get_outputs_of() {
    local SH EXIT_STATUS
    SH=$(
        _LK_STDOUT=$(lk_mktemp_file) &&
            _LK_STDERR=$(lk_mktemp_file) &&
            lk_delete_on_exit "$_LK_STDOUT" "$_LK_STDERR" || exit
        unset _LK_FD
        "$@" >"$_LK_STDOUT" 2>"$_LK_STDERR" || EXIT_STATUS=$?
        for i in _LK_STDOUT _LK_STDERR; do
            _lk_var_prefix
            printf '%s=%q\n' "${i#_LK}" "$(cat "${!i}" | lk_strip_non_printing)"
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

function _lk_lock_check_args() {
    EXIT_STATUS=0
    lk_is_linux || lk_command_exists flock || {
        [ ! "${FUNCNAME[1]:-}" = lk_lock ] ||
            lk_console_warning "File locking is not supported on this platform"
        return 1
    }
    [ $# -ge 2 ] &&
        lk_test_many lk_is_identifier "${@:1:2}" ||
        lk_warn "invalid arguments" || EXIT_STATUS=$?
    return "$EXIT_STATUS"
}

# lk_lock LOCK_FILE_VAR LOCK_FD_VAR [LOCK_NAME]
function lk_lock() {
    local EXIT_STATUS
    _lk_lock_check_args "$@" || return "$EXIT_STATUS"
    unset "${@:1:2}"
    eval "$1=/tmp/.\${LK_PATH_PREFIX:-lk-}\${3:-\$(lk_myself 1)}.lock" &&
        eval "$2=\$(lk_next_fd)" &&
        eval "exec ${!2}>\"\$$1\"" || return
    flock -n "${!2}" || lk_warn "unable to acquire a lock on ${!1}"
}

# lk_lock_drop LOCK_FILE_VAR LOCK_FD_VAR [LOCK_NAME]
function lk_lock_drop() {
    local EXIT_STATUS
    _lk_lock_check_args "$@" || return "$EXIT_STATUS"
    if [ "${!1:+1}${!2:+1}" = 11 ]; then
        eval "exec ${!2}>&-" &&
            rm -f -- "${!1}"
    fi
    unset "${@:1:2}"
}

function lk_log() {
    local PREFIX=${1:-}
    if lk_command_exists ts; then
        PREFIX=${PREFIX//"%"/"%%"}
        LC_ALL=C exec ts "$PREFIX%Y-%m-%d %H:%M:%.S %z"
    else
        local LINE
        while IFS= read -r LINE; do
            printf '%s%s %s\n' \
                "$PREFIX" "$(lk_date "%Y-%m-%d %H:%M:%S %z")" "$LINE"
        done
    fi
} #### Reviewed: 2021-03-26

# lk_log_create [-e EXT] [DIR...]
function lk_log_create() {
    local OWNER=$UID GROUP EXT LOG_CMD LOG_DIRS=() LOG_DIR LOG_PATH
    GROUP=$(id -gn) || return
    [ "${1:-}" != -e ] || { EXT=$2 && shift 2; }
    LOG_CMD=${_LK_LOG_CMDLINE[0]:-$0}
    [ ! -d "${LK_INST:-$LK_BASE}" ] ||
        [ -z "$(ls -A "${LK_INST:-$LK_BASE}")" ] ||
        LOG_DIRS=("${LK_INST:-$LK_BASE}/var/log")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS[@]+"${LOG_DIRS[@]}"}; do
        # Find the first LOG_DIR in which the user can write to LOG_FILE,
        # installing LOG_DIR (world-writable) and LOG_FILE (owner-only) if
        # needed, running commands via sudo only if they fail without it
        [ -d "$LOG_DIR" ] || lk_elevate_if_error \
            lk_install -d -m 00777 "$LOG_DIR" 2>/dev/null || continue
        LOG_PATH=$LOG_DIR/${LK_LOG_BASENAME:-${LOG_CMD##*/}}-$UID.${EXT:-log}
        if [ -f "$LOG_PATH" ]; then
            [ -w "$LOG_PATH" ] || {
                lk_elevate_if_error chmod 00600 "$LOG_PATH" || continue
                [ -w "$LOG_PATH" ] ||
                    lk_elevate chown "$OWNER:$GROUP" "$LOG_PATH" || continue
            }
        else
            lk_elevate_if_error \
                lk_install -m 00600 -o "$OWNER" -g "$GROUP" "$LOG_PATH" ||
                continue
        fi 2>/dev/null
        echo "$LOG_PATH"
        return 0
    done
    false
}

function lk_start_trace() {
    local TRACE_PATH
    # Don't interfere with an existing trace
    [[ $- != *x* ]] || return 0
    TRACE_PATH=$(lk_log_create -e "$(lk_date_ymdhms).trace" ~ /tmp) &&
        exec 4> >(lk_log >"$TRACE_PATH") || return
    if lk_bash_at_least 4 1; then
        BASH_XTRACEFD=4
    else
        exec 2>&4 &&
            { ! lk_log_is_open || _LK_TRACE_FD=4; } &&
            { [ "${_LK_FD:-2}" -ne 2 ] ||
                { exec 3>&1 && export _LK_FD=3; }; }
    fi || lk_warn "unable to open trace file" || return
    set -x
}

# lk_log_output [TEMP_LOG_FILE]
function lk_log_output() {
    local LOG_CMD ARGC LOG_PATH DIR HEADER=() IFS
    ! lk_is_true LK_NO_LOG &&
        ! lk_log_is_open &&
        lk_is_script_running || return 0
    [[ $- != *x* ]] || [ -n "${BASH_XTRACEFD:-}" ] || return 0
    [ -n "${_LK_LOG_CMDLINE+1}" ] ||
        local _LK_LOG_CMDLINE=("$0" ${LK_ARGV[@]+"${LK_ARGV[@]}"})
    LOG_CMD=$(type -P "${_LK_LOG_CMDLINE[0]}") ||
        LOG_CMD=${_LK_LOG_CMDLINE[0]##*/}
    _LK_LOG_CMDLINE[0]=$LOG_CMD
    ARGC=$((${#_LK_LOG_CMDLINE[@]} - 1))
    if [ $# -ge 1 ]; then
        if LOG_PATH=$(lk_log_create); then
            # If TEMP_LOG_FILE exists, move its contents to the end of LOG_PATH
            [ ! -e "$1" ] || {
                cat "$1" >>"$LOG_PATH" &&
                    lk_rm "$1" || return
            }
        else
            LOG_PATH=$1
        fi
    else
        LOG_PATH=$(lk_log_create ~ /tmp) ||
            lk_warn "unable to open log file" || return
    fi
    HEADER+=("${_LK_LOG_CMDLINE[0]} invoked")
    [ "$ARGC" -eq 0 ] && HEADER+=("$LK_RESET") || HEADER+=("$(
        printf ' with %s %s:%s' "$ARGC" \
            "$(lk_maybe_plural "$ARGC" argument arguments)" \
            "$LK_RESET"
        for ARG in "${_LK_LOG_CMDLINE[@]:1}"; do
            printf '\n %s->%s %q' "$LK_BOLD" "$LK_RESET" "$ARG"
        done
    )")
    IFS=
    echo "$LK_BOLD====> ${HEADER[*]}" | lk_log >>"$LOG_PATH" &&
        _LK_LOG_OUT_FD=$(lk_next_fd) && eval "exec $_LK_LOG_OUT_FD>&1" &&
        _LK_LOG_ERR_FD=$(lk_next_fd) && eval "exec $_LK_LOG_ERR_FD>&2" || return
    if [ -n "${LK_SECONDARY_LOG_FILE:-}" ]; then
        exec > >(tee >(lk_log |
            tee -a "$LK_SECONDARY_LOG_FILE" >>"$LOG_PATH")) 2>&1
    else
        exec > >(tee >(lk_log >>"$LOG_PATH")) 2>&1
    fi || return
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

# lk_log_close [-r]
#
# Close output redirections opened by lk_log_output. If -r is set, reopen them
# for further logging (useful when closing a secondary log file).
function lk_log_close() {
    lk_log_is_open || lk_warn "no output log to close" || return
    exec >&"$_LK_LOG_OUT_FD" 2>&"${_LK_TRACE_FD:-$_LK_LOG_ERR_FD}" || return
    if [ "${1:-}" = -r ]; then
        exec > >(tee >(lk_log >>"$_LK_LOG_FILE")) 2>&"${_LK_TRACE_FD:-1}"
    else
        eval "exec $_LK_LOG_OUT_FD>&- $_LK_LOG_ERR_FD>&-" &&
            unset _LK_LOG_FILE
    fi
}

function lk_log_bypass() {
    if lk_log_is_open; then
        "$@" >&"$_LK_LOG_OUT_FD" 2>&"${_LK_TRACE_FD:-$_LK_LOG_ERR_FD}"
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
        "$@" 2>&"${_LK_TRACE_FD:-$_LK_LOG_ERR_FD}"
    else
        "$@"
    fi
}

# lk_echoc [-n] [MESSAGE [COLOUR]]
function lk_echoc() {
    local NEWLINE MESSAGE
    [ "${1:-}" != -n ] || { NEWLINE=0 && shift; }
    MESSAGE=${1:-}
    [ $# -le 1 ] || [ -z "$LK_RESET" ] ||
        MESSAGE=$2${MESSAGE//"$LK_RESET"/$LK_RESET$2}$LK_RESET
    echo ${NEWLINE:+-n} "$MESSAGE"
}

function lk_readline_format() {
    local LC_ALL=C STRING=$1 REGEX
    for REGEX in CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX; do
        REGEX=__lk_regex_$REGEX
        while [[ $STRING =~ ((.*)(^|[^$'\x01']))(${!REGEX})+(.*) ]]; do
            STRING=${BASH_REMATCH[1]}$'\x01'${BASH_REMATCH[4]}$'\x02'${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
        done
    done
    echo "$STRING"
}

function lk_strip_non_printing() {
    local LC_ALL=C STRING REGEX=$__lk_regex_NON_PRINTING_REGEX
    if [ $# -gt 0 ]; then
        STRING=$1
        while [[ $STRING =~ (.*)$REGEX(.*) ]]; do
            STRING=${BASH_REMATCH[1]}${BASH_REMATCH[$((${#BASH_REMATCH[@]} - 1))]}
        done
        echo "$STRING"
    else
        export LC_ALL
        sed -E "s/$REGEX//g"
    fi
}

# lk_fold STRING [WIDTH]
#
# Wrap STRING to fit in WIDTH (default: 80) after accounting for non-printing
# character sequences, breaking at whitespace only.
function lk_fold() {
    local LC_ALL=C STRING WIDTH=${2:-80} REGEX=$__lk_regex_NON_PRINTING_REGEX \
        PARTS=() CODES=() LINE_TEXT LINE i PART CODE _LINE_TEXT
    [ $# -gt 0 ] || lk_usage "\
Usage: $(lk_myself -f) STRING [WIDTH]" || return
    STRING=$1
    ! lk_command_exists expand ||
        STRING=$(expand <<<"$STRING") || return
    REGEX=$'^([^\x1b\x01]*)'"(($REGEX)+)(.*)"
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
    echo "${STRING%$'\n'}"
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

function _lk_tty_message_length() {
    echo "${MESSAGE_LENGTH:=$(lk_tty_length "$PREFIX$MESSAGE")}"
}

function _lk_tty_message2_length() {
    echo "${MESSAGE2_LENGTH:=$(lk_tty_length "$PREFIX$MESSAGE $MESSAGE2")}"
}

# lk_console_message MESSAGE [[MESSAGE2] COLOUR]
function lk_console_message() {
    local IFS MESSAGE=$1 MESSAGE_HAS_NEWLINE MESSAGE_LENGTH \
        MESSAGE2 MESSAGE2_HAS_NEWLINE MESSAGE2_LENGTH \
        COLOUR WIDTH PREFIX=${LK_TTY_PREFIX-==> } SPACES INDENT=0 OUTPUT
    # Save ourselves from word-splitting hell
    unset IFS
    shift
    [ $# -le 1 ] || {
        MESSAGE2=$1
        shift
    }
    COLOUR=${1-$LK_TTY_COLOUR}
    WIDTH=${LK_TTY_WIDTH:-$(lk_tty_columns)}
    [ "${LK_TTY_NO_BREAK:-0}" -ne 1 ] ||
        local LK_TTY_NO_FOLD=1
    # If MESSAGE breaks over multiple lines (or will after wrapping), align
    # second and subsequent lines with the first
    [[ ! $MESSAGE == *$'\n'* ]] || {
        MESSAGE_HAS_NEWLINE=1
        # LK_TTY_NO_BREAK only makes sense when MESSAGE prints on one line
        local LK_TTY_NO_BREAK=0
    }
    if [ "${MESSAGE_HAS_NEWLINE:-0}" -eq 1 ] ||
        { [ "${LK_TTY_NO_FOLD:-0}" -ne 1 ] &&
            [ "$(_lk_tty_message_length)" -gt "$WIDTH" ]; }; then
        SPACES=$'\n'"$(lk_repeat " " ${#PREFIX})"
        # Don't fold if MESSAGE is pre-formatted
        [ "${MESSAGE_HAS_NEWLINE:-0}" -eq 1 ] ||
            MESSAGE=$(lk_fold "$MESSAGE" $((WIDTH - ${#PREFIX})))
        MESSAGE=${MESSAGE//$'\n'/$SPACES}
        MESSAGE_HAS_NEWLINE=1
        INDENT=2
    fi
    [ -z "${MESSAGE2:-}" ] || {
        # If MESSAGE and MESSAGE2 are both one-liners, print them on one line
        # with a space between
        [[ ! $MESSAGE2 == *$'\n'* ]] || MESSAGE2_HAS_NEWLINE=1
        if [ ${MESSAGE2_HAS_NEWLINE:-0} -eq 0 ] &&
            [ ${MESSAGE_HAS_NEWLINE:-0} -eq 0 ] &&
            { [ "${LK_TTY_NO_FOLD:-0}" -eq 1 ] ||
                [ "$(_lk_tty_message2_length)" -le "$WIDTH" ]; }; then
            MESSAGE2=" $MESSAGE2"
        else
            # Otherwise:
            # - If they both span multiple lines, or MESSAGE2 is a one-liner,
            #   keep INDENT=2 (increase MESSAGE2's left padding)
            # - If only MESSAGE2 spans multiple lines, set INDENT=-2 (decrease
            #   the left padding of MESSAGE2)
            # - If LK_TTY_NO_BREAK is set, align MESSAGE2 under the first line
            if [ "${LK_TTY_NO_BREAK:-0}" -ne 1 ]; then
                if { [ ${MESSAGE2_HAS_NEWLINE:-0} -eq 1 ] ||
                    [ -n "${MESSAGE2_LENGTH:-}" ]; } &&
                    [ "${MESSAGE_HAS_NEWLINE:-0}" -eq 0 ]; then
                    INDENT=-2
                fi
                INDENT=${_LK_TTY_INDENT:-$((${#PREFIX} + INDENT))}
            else
                INDENT=${_LK_TTY_INDENT:-$(($(_lk_tty_message_length) + 1))}
            fi
            SPACES=$'\n'$(lk_repeat " " "$INDENT")
            [ ${MESSAGE2_HAS_NEWLINE:-0} -eq 1 ] ||
                MESSAGE2=$(lk_fold "$MESSAGE2" $((WIDTH - INDENT)))
            # If a leading newline was added to force MESSAGE2 onto its own
            # line, remove it
            MESSAGE2=${MESSAGE2#$'\n'}
            MESSAGE2=${MESSAGE2//$'\n'/$SPACES}
            [ "${LK_TTY_NO_BREAK:-0}" -eq 1 ] &&
                MESSAGE2=" $MESSAGE2" ||
                MESSAGE2=$SPACES$MESSAGE2
        fi
    }
    OUTPUT=$(
        lk_echoc -n "$PREFIX" \
            "${LK_TTY_PREFIX_COLOUR-$([[ $COLOUR == *$LK_BOLD* ]] ||
                echo "$LK_BOLD")$COLOUR}"
        lk_echoc -n "$MESSAGE" \
            "${LK_TTY_MESSAGE_COLOUR-$([[ $MESSAGE == *$LK_BOLD* ]] ||
                echo "$LK_BOLD")}"
        [ -z "${MESSAGE2:-}" ] ||
            lk_echoc -n "$MESSAGE2" "${LK_TTY_COLOUR2-$COLOUR}"
    )
    case "${FUNCNAME[1]:-}" in
    lk_console_list)
        declare -p WIDTH MESSAGE_HAS_NEWLINE OUTPUT 2>/dev/null || true
        ;;
    *)
        echo "$OUTPUT" >&"${_LK_FD:-2}"
        ;;
    esac
} #### Reviewed: 2021-03-22

# lk_tty_pairs [-d DELIM] [COLOUR]
function lk_tty_pairs() {
    local LK_TTY_NO_FOLD=1 ARGS LEN=0 KEY VALUE KEYS=() VALUES=() GAP SPACES i
    [ "${1:-}" != -d ] || { ARGS=(-d "$2") && shift 2; }
    while read -r ${ARGS[@]+"${ARGS[@]}"} KEY VALUE; do
        [ ${#KEY} -le "$LEN" ] || LEN=${#KEY}
        KEYS[${#KEYS[@]}]=$KEY
        VALUES[${#VALUES[@]}]=$VALUE
    done
    # Align to the nearest tab
    [ -n "${LK_TTY_PREFIX:-}" ] && GAP=${#LK_TTY_PREFIX} || GAP=0
    ((GAP = ((GAP + LEN + 2) % 4), GAP = (GAP > 0 ? 4 - GAP : 0))) || true
    for i in "${!KEYS[@]}"; do
        KEY=${KEYS[$i]}
        ((SPACES = LEN - ${#KEY} + GAP)) || true
        LK_TTY_NO_BREAK=1 lk_console_item \
            "$KEY:$( ! ((SPACES)) || eval "printf ' %.s' {1..$SPACES}")" \
            "${VALUES[$i]}" \
            "$@"
    done
} #### Reviewed: 2021-03-22

# lk_tty_detail_pairs [-d DELIM] [COLOUR]
function lk_tty_detail_pairs() {
    local ARGS LK_TTY_PREFIX=${LK_TTY_PREFIX-   -> } \
        LK_TTY_MESSAGE_COLOUR=${LK_TTY_MESSAGE_COLOUR-}
    [ "${1:-}" != -d ] || { ARGS=(-d "$2") && shift 2; }
    lk_tty_pairs ${ARGS[@]+"${ARGS[@]}"} "${1-$LK_YELLOW}"
} #### Reviewed: 2021-03-22

# lk_console_detail MESSAGE [MESSAGE2 [COLOUR]]
function lk_console_detail() {
    local LK_TTY_PREFIX=${LK_TTY_PREFIX-   -> } \
        LK_TTY_MESSAGE_COLOUR=${LK_TTY_MESSAGE_COLOUR-}
    lk_console_message "$1" "${2:-}" "${3-$LK_YELLOW}"
}

# lk_console_detail_list MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]
function lk_console_detail_list() {
    local LK_TTY_PREFIX=${LK_TTY_PREFIX-   -> } \
        LK_TTY_MESSAGE_COLOUR=${LK_TTY_MESSAGE_COLOUR-}
    if [ $# -le 2 ]; then
        lk_console_list "$1" "${2-$LK_YELLOW}"
    else
        lk_console_list "${@:1:3}" "${4-$LK_YELLOW}"
    fi
}

# lk_console_detail_file FILE [COLOUR [FILE_COLOUR]]
function lk_console_detail_file() {
    local LK_TTY_PREFIX=${LK_TTY_PREFIX-  >>> } \
        LK_TTY_SUFFIX=${LK_TTY_SUFFIX-  <<< } \
        LK_TTY_MESSAGE_COLOUR=${LK_TTY_MESSAGE_COLOUR-$LK_YELLOW} \
        LK_TTY_COLOUR2=${LK_TTY_COLOUR2-$LK_TTY_COLOUR} \
        _LK_TTY_INDENT=2
    ${_LK_TTY_COMMAND:-lk_console_file} "$@"
}

# lk_console_detail_diff FILE1 [FILE2 [MESSAGE [COLOUR]]]
function lk_console_detail_diff() {
    _LK_TTY_COMMAND=lk_console_diff \
        lk_console_detail_file "$@"
}

function _lk_tty_log() {
    local STATUS=$? COLOUR=$1 \
        LK_TTY_COLOUR2=${LK_TTY_COLOUR2-} \
        LK_TTY_MESSAGE_COLOUR
    shift
    [ "${1:-}" != -r ] && STATUS=0 || shift
    LK_TTY_MESSAGE_COLOUR=$(lk_maybe_bold "$1")$COLOUR
    LK_TTY_COLOUR2=${LK_TTY_COLOUR2//"$LK_BOLD"/}
    lk_console_message "$1" "${2:+$(
        BOLD=$(lk_maybe_bold "$2")
        RESET=${BOLD:+$LK_RESET}
        [ "${2#$'\n'}" = "$2" ] || printf '\n'
        echo "$BOLD${2#$'\n'}$RESET"
    )}${3:+ ${*:3}}" "$COLOUR"
    return "$STATUS"
}

# lk_console_log [-r] MESSAGE [MESSAGE2...]
#
# Output the given message to the console. If -r is set, return the most recent
# command's exit status.
function lk_console_log() {
    LK_TTY_PREFIX=${LK_TTY_PREFIX-" :: "} \
        _lk_tty_log "$LK_TTY_COLOUR" "$@"
}

# lk_console_success [-r] MESSAGE [MESSAGE2...]
#
# Output the given success message to the console. If -r is set, return the most
# recent command's exit status.
function lk_console_success() {
    # ✔ (\u2714)
    LK_TTY_PREFIX=${LK_TTY_PREFIX-$'  \xe2\x9c\x94 '} \
        _lk_tty_log "$LK_SUCCESS_COLOUR" "$@"
}

# lk_console_warning [-r] MESSAGE [MESSAGE2...]
#
# Output the given warning to the console. If -r is set, return the most recent
# command's exit status.
function lk_console_warning() {
    # ✘ (\u2718)
    LK_TTY_PREFIX=${LK_TTY_PREFIX-$'  \xe2\x9c\x98 '} \
        _lk_tty_log "$LK_WARNING_COLOUR" "$@"
}

# lk_console_error [-r] MESSAGE [MESSAGE2...]
#
# Output the given error message to the console. If -r is set, return the most
# recent command's exit status.
function lk_console_error() {
    # ✘ (\u2718)
    LK_TTY_PREFIX=${LK_TTY_PREFIX-$'  \xe2\x9c\x98 '} \
        _lk_tty_log "$LK_ERROR_COLOUR" "$@"
}

# lk_console_item MESSAGE ITEM [COLOUR]
function lk_console_item() {
    lk_console_message "$1" "$2" "${3-$LK_TTY_COLOUR}"
}

# lk_console_list [-z] MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]
function lk_console_list() {
    local LK_Z=${LK_Z-} \
        MESSAGE SINGLE PLURAL COLOUR LK_TTY_PREFIX=${LK_TTY_PREFIX-==> } \
        ITEMS INDENT=-2 LIST SPACES SH
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
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
    [ "${MESSAGE_HAS_NEWLINE:-0}" -eq 0 ] ||
        INDENT=2
    LIST="$(lk_echo_array ITEMS |
        COLUMNS=$((WIDTH - ${#LK_TTY_PREFIX} - INDENT)) column -s $'\n' |
        expand)" || return
    SPACES="$(lk_repeat " " $((${#LK_TTY_PREFIX} + INDENT)))"
    # OUTPUT is assigned by lk_console_message
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
} #### Reviewed: 2021-03-22

# lk_console_dump CONTENT [MESSAGE [MESSAGE_END [COLOUR [CONTENT_COLOUR]]]]
function lk_console_dump() {
    local CONTENT=${1%$'\n'} SPACES BOLD_COLOUR \
        COLOUR=${4-${LK_TTY_MESSAGE_COLOUR-$LK_TTY_COLOUR}} \
        LK_TTY_COLOUR2=${5-${LK_TTY_COLOUR2-}} \
        LK_TTY_PREFIX=${LK_TTY_PREFIX->>> } \
        LK_TTY_SUFFIX=${LK_TTY_SUFFIX-<<< } \
        _LK_TTY_INDENT=${_LK_TTY_INDENT:-0} \
        LK_TTY_NO_FOLD=1 \
        LK_TTY_MESSAGE_COLOUR
    [ -n "$CONTENT" ] || [ -t 0 ] || CONTENT=$(cat)
    BOLD_COLOUR=$(lk_maybe_bold "$COLOUR")$COLOUR
    LK_TTY_MESSAGE_COLOUR=$(lk_maybe_bold "${2:-}$COLOUR")$COLOUR
    local LK_TTY_PREFIX_COLOUR=${LK_TTY_PREFIX_COLOUR-$BOLD_COLOUR}
    SPACES=$'\n'$(lk_repeat " " "$((_LK_TTY_INDENT + 2))")
    CONTENT=$SPACES${CONTENT//$'\n'/$SPACES}
    _LK_TTY_INDENT=0 \
        lk_console_item "${2:-}" "$(echo "$CONTENT" &&
            printf '%s' "$LK_TTY_PREFIX_COLOUR$LK_TTY_SUFFIX$LK_RESET" \
                ${3:+"$COLOUR$3$LK_RESET"})"
}

# lk_console_file FILE [COLOUR [FILE_COLOUR]]
function lk_console_file() {
    lk_maybe_sudo test -r "$1" || lk_warn "file not found: $1" || return
    lk_console_dump "" \
        "$1" \
        "($(lk_file_summary "$1"))" \
        "${2-${LK_TTY_MESSAGE_COLOUR-$LK_MAGENTA}}" \
        "${3-${LK_TTY_COLOUR2-$LK_GREEN}}" \
        <"$1"
}

# lk_console_diff FILE1 [FILE2 [MESSAGE [COLOUR]]]
#
# Compare FILE1 and FILE2 using diff. If FILE2 is the empty string, read it from
# input. If FILE1 is the only argument, compare with FILE1.orig if it exists,
# otherwise pass FILE1 to lk_console_file.
function lk_console_diff() {
    local FILE1=$1 FILE2=${2:-} f MESSAGE DIFF_VER
    [ -n "$FILE1$FILE2" ] || lk_warn "invalid arguments" || return
    for f in FILE1 FILE2; do
        [ -n "${!f}" ] || {
            if [ "$f" = FILE2 ] && { [ -t 0 ] || [ $# -eq 1 ]; }; then
                ! lk_maybe_sudo test -r "$1.orig" || {
                    FILE1=$1.orig
                    FILE2=$1
                    set -- "$FILE1" "$FILE2" "${@:3}"
                    break
                }
                lk_console_file "$1" \
                    "${4-${LK_TTY_MESSAGE_COLOUR-$LK_MAGENTA}}"
                return
            fi
            eval "$f=/dev/stdin"
            continue
        }
        lk_maybe_sudo test -r "${!f}" ||
            lk_warn "file not found: ${!f}" || return
    done
    MESSAGE="\
${1:-${LK_TTY_INPUT_NAME:-/dev/stdin}} -> \
$LK_BOLD${2:-${LK_TTY_INPUT_NAME:-/dev/stdin}}$LK_RESET"
    MESSAGE=${3-$MESSAGE}
    DIFF_VER=$(lk_diff_version 2>/dev/null) &&
        lk_version_at_least "$DIFF_VER" 3.4 || unset DIFF_VER
    lk_console_dump \
        "$(! lk_maybe_sudo gnu_diff --unified ${DIFF_VER+--color=always} \
            "$FILE1" "$FILE2" ||
            echo "${LK_CYAN}Files are identical$LK_RESET")" \
        "$MESSAGE" \
        "" \
        "${4-${LK_TTY_MESSAGE_COLOUR-$LK_MAGENTA}}" \
        "${LK_TTY_COLOUR2-}"
}

function lk_run() {
    local COMMAND TRACE SH ARGS WIDTH SHIFT=
    [[ ! ${1:-} =~ ^-([0-9]+)$ ]] || { SHIFT=${BASH_REMATCH[1]} && shift; }
    COMMAND=("$@")
    [ -z "$SHIFT" ] || shift "$SHIFT"
    while [[ ${1:-} =~ ^(lk_(elevate|maybe_(sudo|trace))|sudo)$ ]] &&
        [[ ${2:-} != -* ]]; do
        case "$1" in
        lk_maybe_trace)
            TRACE=1
            ;;
        esac
        shift
    done
    ! lk_is_true TRACE || {
        SH="set -- $(lk_maybe_trace -o "$@")" &&
            eval "$SH"
    } || return
    ARGS=$(lk_quote_args "$@")
    WIDTH=${LK_TTY_WIDTH:-$(lk_tty_columns)}
    [ ${#ARGS} -le $((WIDTH - ${_LK_TTY_INDENT:-2} - 11)) ] ||
        ARGS=$'\n'$(lk_quote_args_folded "$@")
    LK_TTY_NO_FOLD=1 \
        ${_LK_TTY_COMMAND:-lk_console_item} "Running:" "$ARGS"
    "${COMMAND[@]}"
}

function lk_run_detail() {
    _LK_TTY_COMMAND=lk_console_detail \
        _LK_TTY_INDENT=${_LK_TTY_INDENT:-4} \
        lk_run "$@"
}

function lk_maybe_trace() {
    local OUTPUT COMMAND
    [ "${1:-}" != -o ] || { OUTPUT=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no command" || return
    COMMAND=("$@")
    [[ $- != *x* ]] ||
        COMMAND=(env
            ${BASH_XTRACEFD:+BASH_XTRACEFD=$BASH_XTRACEFD}
            SHELLOPTS=xtrace
            "$@")
    ! lk_will_sudo ||
        COMMAND=(sudo -C 5 -H "${COMMAND[@]:1}")
    ! lk_is_true OUTPUT ||
        COMMAND=(lk_quote_args "${COMMAND[@]}")
    "${COMMAND[@]}"
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
    lk_console_blank
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
    ! lk_is_true LK_FORCE_INPUT || return
    [ ! -t 0 ] ||
        lk_is_true LK_NO_INPUT
}

function lk_verbose() {
    [ "${LK_VERBOSE:-0}" -ge "${1:-1}" ]
}

# lk_require_output [-q|-s] COMMAND [ARG...]
#
# Run COMMAND and return true if its exit status is zero and output other than
# newline characters was written. If -q is set, suppress output. If -s is set,
# suppress output if COMMAND fails.
function lk_require_output() {
    local SUPPRESS QUIET FD OUTPUT EXIT_STATUS=
    # Until Bash 4.0, local variables were "created with the empty string for a
    # value rather than no value"
    unset SUPPRESS QUIET
    [ "${1:-}" != -q ] || { SUPPRESS= && QUIET= && shift; }
    [ "${1:-}" != -s ] || { SUPPRESS= && shift; }
    FD=$(lk_next_fd) && eval "exec $FD>&1" || return
    OUTPUT=$("$@" |
        tee ${SUPPRESS-"/dev/fd/$FD"} ${SUPPRESS+/dev/null} && printf .) &&
        OUTPUT=${OUTPUT%.} || EXIT_STATUS=$?
    eval "exec $FD>&-" || EXIT_STATUS=${EXIT_STATUS:-$?}
    (exit "${EXIT_STATUS:-0}") &&
        [ -n "$(echo "$OUTPUT")" ] &&
        { [ -z "${SUPPRESS+1}" ] || [ -n "${QUIET+1}" ] ||
            printf '%s' "$OUTPUT"; }
}

# lk_clip
#
# Copy input to the user's clipboard if possible, otherwise print it out.
function lk_clip() {
    local OUTPUT COMMAND LINES MESSAGE DISPLAY_LINES=${LK_CLIP_LINES:-5}
    [ ! -t 0 ] || lk_warn "no input" || return
    OUTPUT=$(cat && printf .) && OUTPUT=${OUTPUT%.}
    if COMMAND=$(lk_command_first_existing \
        "xclip -selection clipboard" \
        pbcopy) &&
        echo -n "$OUTPUT" | $COMMAND &>/dev/null; then
        LINES=$(wc -l <<<"$OUTPUT")
        [ "$LINES" -le "$DISPLAY_LINES" ] || {
            OUTPUT=$(head -n$((DISPLAY_LINES - 1)) <<<"$OUTPUT" &&
                echo "$LK_BOLD$LK_MAGENTA...$LK_RESET")
            MESSAGE="$LINES lines copied"
        }
        lk_console_item "${MESSAGE:-Copied} to clipboard:" \
            $'\n'"$LK_GREEN$OUTPUT$LK_RESET" "$LK_MAGENTA"
    else
        lk_console_error "Unable to copy input to clipboard"
        echo -n "$OUTPUT"
    fi
}

# lk_paste
#
# Paste the user's clipboard to output, if possible.
function lk_paste() {
    local COMMAND
    COMMAND=$(lk_command_first_existing \
        "xclip -selection clipboard -out" \
        pbpaste) &&
        $COMMAND ||
        lk_console_error "Unable to paste clipboard to output"
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
        lk_delete_on_exit "$TEMP_FILE" &&
        wget --quiet --convert-links --output-document "$TEMP_FILE" "$1" ||
        return
    lk_get_uris "$TEMP_FILE"
    rm -f -- "$TEMP_FILE"
}

function lk_curl_version() {
    curl --version | awk 'NR == 1 { print $2 }' ||
        lk_warn "unable to determine curl version" || return
}

function lk_diff_version() {
    gnu_diff --version | awk 'NR == 1 { print $NF }' ||
        lk_warn "unable to determine diff version" || return
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

function lk_curl() {
    local CURL_OPTIONS=(${LK_CURL_OPTIONS[@]+"${LK_CURL_OPTIONS[@]}"})
    [ ${#CURL_OPTIONS[@]} -gt 0 ] || CURL_OPTIONS=(
        --fail
        --header "Cache-Control: no-cache"
        --header "Pragma: no-cache"
        --location
        --retry 8
        --show-error
        --silent
    )
    curl ${CURL_OPTIONS[@]+"${CURL_OPTIONS[@]}"} "$@"
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
        sudo -n ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" &>/dev/null || {
            ! lk_no_input &&
                sudo ${USERNAME:+-u "$USERNAME"} -l "$COMMAND" >/dev/null
        }
    }
}

function lk_will_elevate() {
    lk_is_root || lk_is_true LK_SUDO
}

function lk_will_sudo() {
    ! lk_is_root && lk_is_true LK_SUDO
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
# Run the given command with sudo unless the current user is root. If COMMAND is
# not found in PATH and is a function, run it with LK_SUDO=1.
function lk_elevate() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    else
        if ! lk_command_exists "$1" &&
            [ "$(type -t "$1")" = function ]; then
            LK_SUDO=1 "$@"
        else
            sudo -H "$@"
        fi
    fi
}

function lk_elevate_if_error() {
    local EXIT_STATUS=0
    LK_SUDO=0 "$@" || {
        EXIT_STATUS=$?
        [ "$EUID" -ne 0 ] || return "$EXIT_STATUS"
        if [ "$(type -t "$1")" != function ]; then
            ! lk_can_sudo "$1" ||
                {
                    EXIT_STATUS=0
                    sudo -H "$@" || EXIT_STATUS=$?
                }
        else
            EXIT_STATUS=0
            LK_SUDO=1 "$@" || EXIT_STATUS=$?
        fi
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

function lk_me() {
    lk_maybe_sudo id -un
}

function lk_rm() {
    if lk_command_exists trash-put; then
        lk_maybe_sudo trash-put "$@"
    else
        lk_maybe_sudo rm "$@"
    fi
}

# - lk_install [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
# - lk_install -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY...
#
# Create or set permissions and ownership on each FILE or DIRECTORY.
function lk_install() {
    local OPTIND OPTARG OPT LK_USAGE _USER LK_SUDO=${LK_SUDO:-} \
        DIR MODE OWNER GROUP VERBOSE DEST STAT REGEX ARGS=()
    LK_USAGE="\
Usage: $(lk_myself -f) [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
   or: $(lk_myself -f) -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY..."
    while getopts ":dm:o:g:v" OPT; do
        case "$OPT" in
        d)
            DIR=1
            ARGS+=(-d)
            ;;
        m)
            MODE=$OPTARG
            ARGS+=(-m "$MODE")
            ;;
        o)
            OWNER=$(id -un "$OPTARG") &&
                _USER=$(id -un) || return
            ARGS+=(-o "$OWNER")
            [ "$OWNER" != "$_USER" ] ||
                unset OWNER
            ;;
        g)
            [[ ! $OPTARG =~ ^[0-9]+$ ]] ||
                lk_warn "invalid group: $OPTARG" || return
            GROUP=$OPTARG
            ARGS+=(-g "$GROUP")
            ;;
        v)
            VERBOSE=1
            ARGS+=(-v)
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -gt 0 ] || lk_usage || return
    [ -z "${OWNER:-}" ] &&
        { [ -z "${GROUP:-}" ] || lk_user_in_group "$GROUP"; } ||
        LK_SUDO=1
    if lk_is_true DIR; then
        lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} "$@"
    else
        for DEST in "$@"; do
            if lk_maybe_sudo test ! -e "$DEST" 2>/dev/null; then
                lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} /dev/null "$DEST"
            else
                STAT=$(lk_file_security "$DEST" 2>/dev/null) || return
                [ -z "${MODE:-}" ] ||
                    { [[ $MODE =~ ^0*([0-7]+)$ ]] &&
                        REGEX=" 0*${BASH_REMATCH[1]}\$" &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_maybe_sudo chmod \
                        ${VERBOSE:+-v} "$MODE" "$DEST" ||
                    return
                [ -z "${OWNER:-}${GROUP:-}" ] ||
                    { REGEX='[-a-z0-9_]+\$?' &&
                        REGEX="^${OWNER:-$REGEX}:${GROUP:-$REGEX} " &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_elevate chown \
                        ${VERBOSE:+-v} "${OWNER:-}${GROUP:+:$GROUP}" "$DEST" ||
                    return
            fi
        done
    fi
}

# lk_symlink [-f] TARGET LINK
#
# Safely add a symbolic link to TARGET from LINK. If -f is set, delete a file or
# directory at LINK instead of moving it to LINK.orig.
function lk_symlink() {
    local TARGET LINK LINK_DIR CURRENT_TARGET NO_ORIG v='' vv=''
    [ "${1:-}" != -f ] || { NO_ORIG=1 && shift; }
    [ $# -eq 2 ] || lk_usage "\
Usage: $(lk_myself -f) [-f] TARGET LINK"
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
    LK_SYMLINK_NO_CHANGE=${LK_SYMLINK_NO_CHANGE:-1}
    if lk_maybe_sudo test -L "$LINK"; then
        CURRENT_TARGET=$(lk_maybe_sudo readlink -- "$LINK") || return
        [ "$CURRENT_TARGET" != "$TARGET" ] ||
            return 0
        lk_maybe_sudo rm -f"$vv" -- "$LINK" || return
    elif lk_maybe_sudo test -e "$LINK"; then
        if ! lk_is_true NO_ORIG; then
            lk_maybe_sudo \
                mv -f"$v" -- "$LINK" "$LINK.orig" || return
        else
            lk_rm -Rf"$v" -- "$LINK" || return
        fi
    elif lk_maybe_sudo test ! -d "$LINK_DIR"; then
        lk_maybe_sudo \
            install -d"$v" -- "$LINK_DIR" || return
    fi
    lk_maybe_sudo ln -s"$v" -- "$TARGET" "$LINK" &&
        LK_SYMLINK_NO_CHANGE=0
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
    id "$1" &>/dev/null || return
}

# lk_user_groups [USER]
function lk_user_groups() {
    eval "$(lk_get_regex LINUX_USERNAME_REGEX)"
    groups ${1+"$1"} | sed 's/^.*:[[:blank:]]*//' |
        grep -Eo "$LINUX_USERNAME_REGEX"
}

# lk_user_in_group GROUP [USER]
function lk_user_in_group() {
    lk_user_groups ${2+"$2"} | grep -Fx "$1" >/dev/null
}

function lk_test_many() {
    local TEST=$1
    [ -n "$TEST" ] || lk_warn "no test command" || return
    shift
    [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        eval "$TEST \"\$1\"" || return
        shift
    done
}

function lk_paths_exist() {
    lk_test_many "lk_maybe_sudo test -e" "$@"
}

function lk_files_exist() {
    lk_test_many "lk_maybe_sudo test -f" "$@"
}

function lk_dirs_exist() {
    lk_test_many "lk_maybe_sudo test -d" "$@"
}

function lk_files_not_empty() {
    lk_test_many "lk_maybe_sudo test -s" "$@"
}

# lk_dir_parents [-u UNTIL] DIR...
function lk_dir_parents() {
    local UNTIL=/
    [ "${1:-}" != -u ] || {
        UNTIL=$(realpath "$2") || return
        shift 2
    }
    realpath "$@" | awk -v "u=$UNTIL" 'BEGIN {
    l = length(u) + 1
}
substr($0 "/", 1, l) == u "/" {
    split(substr($0, l), a, "/")
    d = u
    for(i in a) {
        d = d (a[i] ? "/" a[i] : "")
        print d
    }
}' | lk_filter 'test -d'
}

# lk_remove_false TEST ARRAY
#
# Reduce ARRAY to each element where evaluating TEST returns true after
# replacing the string '{}' with the element's value. Array indices are not
# preserved.
function lk_remove_false() {
    local _LK_TEMP_ARRAY _LK_TEST _LK_VAL _lk_i=0
    _lk_array_fill_temp "$2" || return
    _LK_TEST="$(lk_replace '{}' '$_LK_VAL' "$1")"
    eval "$2=()"
    for _LK_VAL in ${_LK_TEMP_ARRAY[@]+"${_LK_TEMP_ARRAY[@]}"}; do
        ! eval "$_LK_TEST" || eval "$2[$((_lk_i++))]=\$_LK_VAL"
    done
}

# lk_remove_missing ARRAY
#
# Remove paths to missing files from ARRAY.
function lk_remove_missing() {
    lk_remove_false 'lk_maybe_sudo test -e "{}" -o -L "{}"' "$1"
}

# lk_resolve_files ARRAY
#
# Resolve paths in ARRAY to absolute file names and remove any duplicates.
function lk_resolve_files() {
    local _LK_TEMP_ARRAY
    _lk_array_fill_temp "$1" || return
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            gnu_realpath -zm "${_LK_TEMP_ARRAY[@]}" | sort -zu
    )
}

# lk_expand_path [-z] [PATH]
#
# Perform quote removal, tilde expansion and glob expansion on PATH, then print
# each result. If -z is set, output NUL instead of newline after each result.
# The globstar shell option must be enabled with `shopt -s globstar` for **
# globs to be expanded.
function lk_expand_path() {
    local LK_Z=${LK_Z-} EXIT_STATUS _PATH SHOPT DELIM q g ARR
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    [ -n "${1:-}" ] || lk_warn "no path" || return
    _PATH=$1
    SHOPT=$(shopt -p nullglob) || true
    shopt -s nullglob
    DELIM=${LK_Z:+'\0'}
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
    _lk_array_fill_temp "$1" || return
    lk_mapfile -z "$1" <(
        [ ${#_LK_TEMP_ARRAY[@]} -eq 0 ] ||
            lk_expand_path -z "${_LK_TEMP_ARRAY[@]}"
    )
}

# lk_pretty_path [-z] [PATH...]
function lk_pretty_path() {
    local LK_Z=${LK_Z-} _LK_NUL_READ=(-d '') DELIM
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    DELIM=${LK_Z:+'\0'}
    # Piping to `while` creates a subshell, so we don't need to declare locals
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        while IFS= read -r ${LK_Z:+"${_LK_NUL_READ[@]}"} _PATH; do
            __PATH=$_PATH
            [ "$_PATH" = "${_PATH#~}" ] || __PATH="~${_PATH#~}"
            [ "$PWD" = / ] || [ "$PWD" = "$_PATH" ] || [[ $PWD = ~ ]] ||
                [ "$_PATH" = "${_PATH#$PWD}" ] || __PATH=.${_PATH#$PWD}
            printf "%s${DELIM:-\\n}" "$__PATH"
        done
}

function lk_basename() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        sed -E 's/.*\/([^/]+)\/*$/\1/'
}

function lk_filter() {
    local LK_Z=${LK_Z-} EXIT_STATUS TEST DELIM
    [ "${1:-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 1 "$@" || return "$EXIT_STATUS"
    TEST=$1
    [ -n "$TEST" ] || lk_warn "no test command" || return
    shift
    DELIM=${LK_Z:+'\0'}
    ! eval "$TEST \"\$1\"" || printf "%s${DELIM:-\\n}" "$1"
}

function lk_is_declared() {
    declare -p "$1" &>/dev/null
}

function lk_is_readonly() {
    (unset "$1" 2>/dev/null) || return 0
    false
}

# lk_version_at_least INSTALLED_VERSION MINIMUM_VERSION
function lk_version_at_least() {
    local MIN
    MIN=$(lk_echo_args "$@" | sort -V | head -n1) &&
        [ "$MIN" = "$2" ]
}

function lk_jq() {
    jq -L "$LK_BASE/lib/jq" "${@:1:$#-1}" 'include "core";'"${*: -1}"
}

# lk_jq_get_array ARRAY [FILTER]
#
# Apply FILTER (default: ".[]") to the input and populate ARRAY with the
# JSON-encoded value of each result.
function lk_jq_get_array() {
    local SH
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    SH="$1=($(jq -r "${2:-.[]} | tostring | @sh"))" &&
        eval "$SH"
}

# lk_jq_get_shell_var [--arg NAME VALUE]... VAR FILTER [VAR FILTER]...
function lk_jq_get_shell_var() {
    local JQ ARGS=()
    while [ "${1:-}" = --arg ]; do
        [ $# -ge 5 ] || lk_warn "invalid arguments" || return
        ARGS+=("${@:1:3}")
        shift 3
    done
    [ $# -gt 0 ] && ! (($# % 2)) || lk_warn "invalid arguments" || return
    JQ=$(printf '"%s":(%s),' "$@")
    JQ='{'${JQ%,}'} | to_sh($_lk_var_prefix)'
    lk_jq -r \
        ${ARGS[@]+"${ARGS[@]}"} \
        --arg _lk_var_prefix "$(_lk_var_prefix)" \
        "$JQ"
}

function lk_json_from_xml_schema() {
    [ $# -gt 0 ] && [ $# -le 2 ] && lk_files_exist "$@" || lk_usage "\
Usage: $(lk_myself -f) XSD_FILE [XML_FILE]" || return
    "$LK_BASE/lib/python/json_from_xml_schema.py" "$@"
}

if lk_is_macos; then
    function lk_tty() {
        # "-t 0" is equivalent to "-f" on Linux (immediately flush output after
        # each write)
        script -q -t 0 /dev/null "$@"
    }
else
    function lk_tty() {
        script -eqfc "$(lk_quote_args "$@")" /dev/null
    }
fi

function lk_hash() {
    local COMMAND
    COMMAND=$(lk_command_first_existing \
        xxh128sum xxh64sum xxh32sum xxhsum sha256sum shasum md5sum md5) ||
        lk_warn "command not found: md5" || return
    if [ $# -gt 0 ]; then
        printf '%s\0' "$@" | "$COMMAND"
    else
        "$COMMAND"
    fi | awk '{print $1}'
} #### Reviewed: 2021-03-25

# lk_random_hex BYTES
function lk_random_hex() {
    [ $# -gt 0 ] && [[ $1 =~ ^[0-9]+$ ]] ||
        lk_warn "invalid arguments" || return
    [ "$1" -lt 1 ] ||
        printf '%02x' $(for i in $(seq 1 "$1"); do echo $((RANDOM % 256)); done)
}

# lk_random_password [LENGTH]
function lk_random_password() {
    local LENGTH=${1:-16} PASSWORD=
    LK_RANDOM_ITERATIONS=0
    while [ ${#PASSWORD} -lt "$LENGTH" ]; do
        ((++LK_RANDOM_ITERATIONS))
        # Increase BYTES by 10% to compensate for removal of 'look-alike'
        # characters, reducing chance of 2+ iterations from >50% to <2%
        PASSWORD=$PASSWORD$(openssl rand -base64 \
            $((BITS = LENGTH * 6, BYTES = BITS / 8 + (BITS % 8 ? 1 : 0), BYTES * 11 / 10)) |
            sed -E 's/[lIO01\n]+//g') || return
        PASSWORD=${PASSWORD//$'\n'/}
    done
    printf '%s' "${PASSWORD:0:$LENGTH}"
}

# lk_base64 [-d]
function lk_base64() {
    local DECODE
    [ "${1:-}" != -d ] || DECODE=1
    if lk_command_exists openssl &&
        openssl base64 &>/dev/null </dev/null; then
        # OpenSSL's implementation is ubiquitous and well-behaved
        openssl base64 ${DECODE:+-d}
    elif lk_command_exists base64 &&
        base64 --version 2>/dev/null </dev/null | grep -i gnu >/dev/null; then
        # base64 on BSD and some legacy systems (e.g. RAIDiator 4.x) doesn't
        # wrap lines by default
        base64 ${DECODE:+--decode}
    else
        false
    fi
}

if ! lk_is_macos || lk_gnu_check stat sed; then
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

if ! lk_is_macos || lk_gnu_check stat; then
    function lk_file_modified() {
        lk_maybe_sudo gnu_stat -c '%Y' -- "$@"
    }
    function lk_file_owner() {
        lk_maybe_sudo gnu_stat -c '%U' -- "$@"
    }
    function lk_file_group() {
        lk_maybe_sudo gnu_stat -c '%G' -- "$@"
    }
    function lk_file_mode() {
        lk_maybe_sudo gnu_stat -c '%04a' -- "$@"
    }
    function lk_file_security() {
        lk_maybe_sudo gnu_stat -c '%U:%G %04a' -- "$@"
    }
else
    function lk_file_modified() {
        lk_maybe_sudo stat -t '%s' -f '%Sm' -- "$@"
    }
    function lk_file_owner() {
        lk_maybe_sudo stat -f '%Su' -- "$@"
    }
    function lk_file_group() {
        lk_maybe_sudo stat -f '%Sg' -- "$@"
    }
    function lk_file_mode() {
        # Output octal (O) file mode (p) twice, first for the suid, sgid, and
        # sticky bits (M), then with zero-padding (03) for the user, group, and
        # other bits (L)
        lk_maybe_sudo stat -f '%OMp%03OLp' -- "$@"
    }
    function lk_file_security() {
        lk_maybe_sudo stat -f '%Su:%Sg %OMp%03OLp' -- "$@"
    }
fi

# lk_file_age FILE
#
# Output the number of seconds since FILE was last modified.
function lk_file_age() {
    local MODIFIED
    MODIFIED=$(lk_file_modified "$1") &&
        echo $(($(lk_timestamp) - MODIFIED))
}

function lk_file_summary() {
    local IFS=$'\t' f
    # e.g. "-rwxrwxr-x  lina    adm     19162   1608099521"
    if ! lk_is_macos || lk_gnu_check stat; then
        f=($(lk_maybe_sudo gnu_stat -L --printf '%A\t%U\t%G\t%s\t%Y' -- "$1"))
    else
        f=($(lk_maybe_sudo stat -L -t '%s' -f '%Sp%t%Su%t%Sg%t%z%t%Sm' -- "$1"))
    fi
    f[3]="${f[3]} bytes"
    if ! lk_maybe_sudo test -f "$1"; then
        f[3]=
    elif lk_maybe_sudo test -L "$1"; then
        f[3]="target: ${f[3]}"
    fi
    f[4]=$(lk_date "%-d %b %Y %H:%M%z" "${f[4]}")
    f[4]=${f[4]/"$(lk_date " %Y ")"/ }
    echo "${f[3]:+${f[3]}, }modified ${f[4]}, ${f[0]} ${f[1]} ${f[2]}"
}

if ! lk_is_macos || lk_gnu_check date; then
    function lk_timestamp_readable() {
        gnu_date -Rd "@$1"
    }
else
    function lk_timestamp_readable() {
        date -Rjf '%s' "$1"
    }
fi

# lk_file_get_text FILE VAR
#
# Read the entire FILE into variable VAR, adding a newline at the end unless
# FILE has zero bytes or its last byte is a newline.
function lk_file_get_text() {
    lk_maybe_sudo test -e "$1" || lk_warn "file not found: $1" || return
    lk_is_identifier "$2" || lk_warn "not a valid identifier: $2" || return
    eval "$2=\$(lk_maybe_sudo cat \"\$1\" && printf .)" &&
        eval "$2=\${$2%.}" &&
        { [ -z "${!2:+1}" ] ||
            eval "$2=\${$2%\$'\\n'}\$'\\n'"; }
}

# lk_file_keep_original FILE
function lk_file_keep_original() {
    local v=
    ! lk_verbose || v=v
    while [ $# -gt 0 ]; do
        ! lk_maybe_sudo test -s "$1" ||
            lk_maybe_sudo test -e "$1.orig" ||
            lk_maybe_sudo cp -naL"$v" "$1" "$1.orig" || return
        shift
    done
}

# lk_file_get_backup_suffix [TIMESTAMP]
function lk_file_get_backup_suffix() {
    echo ".lk-bak-$(lk_date "%Y%m%dT%H%M%SZ" ${1+"$1"})"
}

# lk_file_backup [-m] FILE...
#
# Copy each FILE to FILE.lk-bak-TIMESTAMP, where TIMESTAMP is the file's last
# modified time in UTC (e.g. 20201202T095515Z). If -m is set, copy FILE to
# LK_BASE/var/backup if elevated, or ~/.lk-platform/backup if not elevated.
function lk_file_backup() {
    local MOVE=${LK_FILE_MOVE_BACKUP:-} FILE OWNER OWNER_HOME DEST GROUP \
        MODIFIED SUFFIX TZ=UTC s vv=
    [ "${1:-}" != -m ] || { MOVE=1 && shift; }
    ! lk_verbose 2 || vv=v
    export TZ
    while [ $# -gt 0 ]; do
        if lk_maybe_sudo test -e "$1"; then
            lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
            lk_maybe_sudo test -s "$1" || return 0
            ! lk_is_true MOVE || {
                FILE=$(lk_maybe_sudo realpath "$1") || return
                {
                    OWNER=$(lk_file_owner "$FILE") &&
                        OWNER_HOME=$(lk_expand_path "~$OWNER") &&
                        OWNER_HOME=$(lk_maybe_sudo realpath "$OWNER_HOME")
                } 2>/dev/null || OWNER_HOME=
                if lk_will_elevate && [ "${FILE#$OWNER_HOME}" = "$FILE" ]; then
                    lk_install -d \
                        -m "$([ -g "$LK_BASE" ] && echo 02775 || echo 00755)" \
                        "${LK_INST:-$LK_BASE}/var" || return
                    DEST=${LK_INST:-$LK_BASE}/var/backup
                    unset OWNER
                elif lk_will_elevate; then
                    DEST=$OWNER_HOME/.lk-platform/backup
                    GROUP=$(id -gn "$OWNER") &&
                        lk_install -d -m 00755 \
                            -o "$OWNER" -g "$GROUP" "$OWNER_HOME/.lk-platform" ||
                        return
                else
                    DEST=~/.lk-platform/backup
                    unset OWNER
                fi
                lk_install -d -m 00700 \
                    ${OWNER:+-o "$OWNER" -g "$GROUP"} "$DEST" || return
                s=/
                DEST=$DEST/${FILE//"$s"/__}
            }
            MODIFIED=$(lk_file_modified "$1") &&
                SUFFIX=$(lk_file_get_backup_suffix "$MODIFIED") &&
                lk_maybe_sudo cp -naL"$vv" "$1" "${DEST:-$1}$SUFFIX"
        fi
        shift
    done
}

# lk_file_prepare_temp [-n] FILE
function lk_file_prepare_temp() {
    local DIR TEMP NO_COPY MODE vv=
    [ "${1:-}" != -n ] || { NO_COPY=1 && shift; }
    DIR=${1%/*}
    [ "$DIR" != "$1" ] || DIR=$PWD
    ! lk_verbose 2 || vv=v
    TEMP=$(lk_maybe_sudo mktemp -- "${DIR%/}/.${1##*/}.XXXXXXXXXX") || return
    ! lk_maybe_sudo test -f "$1" ||
        if lk_is_true NO_COPY; then
            MODE=$(lk_file_mode "$1") &&
                lk_maybe_sudo chmod "$(lk_pad_zero 5 "$MODE")" -- "$TEMP"
        else
            lk_maybe_sudo cp -aL"$vv" -- "$1" "$TEMP"
        fi >&2 || return
    echo "$TEMP"
}

# lk_file_add_newline [-b|-m] FILE
#
# Add a newline to FILE if its last byte is not a newline. If -b is set, back up
# FILE before changing it. If -m is set, back up FILE to a separate location
# before changing it.
function lk_file_add_newline() {
    local BACKUP=${LK_FILE_TAKE_BACKUP:-} MOVE=${LK_FILE_MOVE_BACKUP:-} \
        WC TEMP vv=
    [ "${1:-}" != -b ] || { BACKUP=1 && shift; }
    [ "${1:-}" != -m ] || { BACKUP=1 && MOVE=1 && shift; }
    ! lk_verbose 2 || vv=v
    if lk_maybe_sudo test -e "$1"; then
        lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
        # If the last byte is a newline, `wc -l` will return 1
        WC=$(lk_maybe_sudo tail -c1 "$1" | wc -l) || return
        if lk_maybe_sudo test -s "$1" && [ "$WC" -eq 0 ]; then
            ! lk_is_true BACKUP ||
                lk_file_backup ${MOVE:+-m} "$1" || return
            TEMP=$(lk_file_prepare_temp "$1") &&
                lk_delete_on_exit "$TEMP" &&
                echo | lk_maybe_sudo tee -a "$TEMP" >/dev/null &&
                lk_maybe_sudo mv -f"$vv" "$TEMP" "$1" || return
            ! lk_verbose ||
                lk_console_detail "Added newline to end of file:" "$1"
        fi
    fi
}

# lk_file_replace [OPTIONS] TARGET [CONTENT]
function lk_file_replace() {
    local OPTIND OPTARG OPT LK_USAGE IFS SOURCE= IGNORE= FILTER= ASK= \
        LINK BACKUP=${LK_FILE_TAKE_BACKUP:-} MOVE=${LK_FILE_MOVE_BACKUP:-} \
        NEW=1 VERB=Created CONTENT PREVIOUS TEMP vv=
    unset IFS PREVIOUS
    LK_USAGE="\
Usage: $(lk_myself -f) [OPTIONS] TARGET [CONTENT]

If TARGET differs from input or CONTENT, replace TARGET.

Options:
  -f SOURCE     read CONTENT from SOURCE
  -i PATTERN    ignore lines matching the regular expression when comparing
  -s SCRIPT     filter lines through \`sed -E SCRIPT\` when comparing
  -l            if TARGET is a symbolic link, replace the linked file
  -b            back up TARGET before replacing it
  -m            use a separate location when backing up (-b is implied)
  -p            prompt before replacing TARGET"
    while getopts ":f:i:s:lbmp" OPT; do
        case "$OPT" in
        b)
            BACKUP=1
            MOVE=
            ;;
        m)
            BACKUP=1
            MOVE=1
            ;;
        l)
            LINK=1
            ;;
        i)
            IGNORE=$OPTARG
            ;;
        s)
            FILTER=$OPTARG
            ;;
        f)
            SOURCE=$OPTARG
            lk_file_get_text "$SOURCE" CONTENT ||
                return
            ;;
        p)
            ASK=1
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    [ $# -gt 0 ] || lk_usage || return
    if [ $# -ge 2 ]; then
        CONTENT=$2
    elif [ -z "$SOURCE" ]; then
        CONTENT=$(cat && printf .) || return
        CONTENT=${CONTENT%.}
    fi
    ! lk_verbose 2 || vv=v
    LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE:-1}
    LK_FILE_REPLACE_DECLINED=0
    if lk_maybe_sudo test -e "$1"; then
        ! lk_is_true LINK || {
            TEMP=$(realpath "$1") || return
            set -- "$TEMP"
        }
        lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
        ! lk_maybe_sudo test -s "$1" || unset NEW VERB
        lk_maybe_sudo test -L "$1" || ! diff -q \
            <(TARGET=$1 _lk_maybe_filter "$IGNORE" "$FILTER" \
                lk_maybe_sudo cat "\"\$TARGET\"") \
            <([ -z "${CONTENT:+1}" ] || _lk_maybe_filter "$IGNORE" "$FILTER" \
                echo "\"\${CONTENT%\$'\\n'}\"") >/dev/null || {
            ! lk_verbose 2 || lk_console_detail "Not changed:" "$1"
            return 0
        }
        ! lk_is_true ASK || lk_is_true NEW || {
            lk_console_diff "$1" "" <<<"${CONTENT%$'\n'}" || return
            lk_confirm "Replace $1 as above?" Y || {
                LK_FILE_REPLACE_DECLINED=1
                return 1
            }
        }
        ! lk_verbose || lk_is_true LK_FILE_NO_DIFF ||
            lk_file_get_text "$1" PREVIOUS || return
        ! lk_is_true BACKUP ||
            lk_file_backup ${MOVE:+-m} "$1" || return
    fi
    TEMP=$(lk_file_prepare_temp "$1") &&
        lk_delete_on_exit "$TEMP" &&
        echo "${CONTENT%$'\n'}" | lk_maybe_sudo tee "$TEMP" >/dev/null &&
        lk_maybe_sudo mv -f"$vv" "$TEMP" "$1" &&
        LK_FILE_REPLACE_NO_CHANGE=0 || return
    ! lk_verbose || {
        if lk_is_true LK_FILE_NO_DIFF || lk_is_true ASK; then
            lk_console_detail "${VERB:-Updated}:" "$1"
        elif [ -n "${PREVIOUS+1}" ]; then
            echo -n "$PREVIOUS" | lk_console_detail_diff "" "$1"
        else
            lk_console_detail_file "$1"
        fi
    }
} #### Reviewed: 2021-03-26

# _lk_maybe_filter DELETE_PATTERN SED_SCRIPT QUOTED_COMMAND...
function _lk_maybe_filter() {
    case "${1:+g}${2:+s}" in
    g)
        eval "${*:3}" | grep -Ev "$1" || [ ${PIPESTATUS[1]} -eq 1 ]
        ;;
    s)
        eval "${*:3}" | sed -E "$2"
        ;;
    gs)
        { eval "${*:3}" | grep -Ev "$1" || [ ${PIPESTATUS[1]} -eq 1 ]; } |
            sed -E "$2"
        ;;
    *)
        eval "${*:3}"
        ;;
    esac
} #### Reviewed: 2021-03-26

function lk_exit_trap() {
    local EXIT_STATUS=$? DELETE_ARRAY="_LK_EXIT_DELETE_${BASH_SUBSHELL}[@]" i
    [ "$EXIT_STATUS" -eq 0 ] ||
        [[ ${FUNCNAME[1]:-} =~ ^_?lk_(die|usage|elevate)$ ]] ||
        { [[ $- == *i* ]] && [ "$BASH_SUBSHELL" -eq 0 ]; } ||
        lk_console_error \
            "$(_lk_caller "${_LK_ERR_TRAP_CONTEXT:-}"): unhandled error"
    for i in ${!DELETE_ARRAY+"${!DELETE_ARRAY}"}; do
        lk_elevate_if_error rm -Rf -- "$i" || true
    done
}

function lk_err_trap() {
    _LK_ERR_TRAP_CONTEXT=$(caller 0) || _LK_ERR_TRAP_CONTEXT=
}

function lk_delete_on_exit() {
    local ARRAY=_LK_EXIT_DELETE_$BASH_SUBSHELL
    [ -n "${!ARRAY+1}" ] || eval "$ARRAY=()"
    while [ $# -gt 0 ]; do
        eval "${ARRAY}[\${#${ARRAY}[@]}]=\$1"
        shift
    done
}

set -o pipefail

trap lk_exit_trap EXIT
trap lk_err_trap ERR

LK_ARGV=("$@")
readonly S="[[:blank:]]" 2>/dev/null || true
readonly NS="[^[:blank:]]" 2>/dev/null || true

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
LK_RESET=

lk_is_true LK_TTY_NO_COLOUR ||
    case "${TERM:-dumb}" in
    dumb | unknown)
        LK_BLACK=$'\E[30m'
        LK_RED=$'\E[31m'
        LK_GREEN=$'\E[32m'
        LK_YELLOW=$'\E[33m'
        LK_BLUE=$'\E[34m'
        LK_MAGENTA=$'\E[35m'
        LK_CYAN=$'\E[36m'
        LK_WHITE=$'\E[37m'
        LK_GREY=
        LK_BLACK_BG=$'\E[40m'
        LK_RED_BG=$'\E[41m'
        LK_GREEN_BG=$'\E[42m'
        LK_YELLOW_BG=$'\E[43m'
        LK_BLUE_BG=$'\E[44m'
        LK_MAGENTA_BG=$'\E[45m'
        LK_CYAN_BG=$'\E[46m'
        LK_WHITE_BG=$'\E[47m'
        LK_GREY_BG=
        LK_BOLD=$'\E[1m'
        LK_DIM=$'\E[2m'
        LK_RESET=$'\E[0m'
        unset TERM
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

_LK_INCLUDES=(core)

true || {
    env
}

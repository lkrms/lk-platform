#!/bin/bash
# shellcheck disable=SC1003,SC2015,SC2016,SC2034,SC2088,SC2120,SC2162,SC2207

function basename() {
    command basename -- "$@"
}

function _lk_caller() {
    local DIM CALLER=() SOURCE="${BASH_SOURCE[2]:-}" FUNC="${FUNCNAME[2]:-}"
    DIM="${LK_DIM:-$LK_GREY}"
    # include shell/script name if caller not in running shell script (or no
    # shell script running)
    if [ "$SOURCE" != "$0" ] || [ "$SOURCE" = "main" ]; then
        CALLER=("$LK_BOLD$(basename "${0#-}")$LK_RESET")
    fi
    # always include source filename and line number
    if [ -n "$SOURCE" ] && [ "$SOURCE" != "main" ]; then
        CALLER+=("$(
            if [ "$SOURCE" = "$0" ]; then
                echo "$LK_BOLD$(basename "$0")$LK_RESET"
            else
                lk_replace "$HOME/" "~/" "$SOURCE"
            fi
        )$DIM:${BASH_LINENO[1]}$LK_RESET")
    fi
    lk_is_false "${LK_DEBUG:-0}" ||
        [ "$FUNC" = "main" ] || CALLER+=(${FUNC:+"$FUNC$DIM()$LK_RESET"})
    lk_implode "$DIM->$LK_RESET" "${CALLER[@]}"
}

# lk_warn message
function lk_warn() {
    local EXIT_STATUS="$?"
    lk_console_warning "$(_lk_caller): $1"
    return "$EXIT_STATUS"
}

# lk_die [message]
#   Output optional MESSAGE to stderr and exit with a non-zero status.
function lk_die() {
    local EXIT_STATUS="$?"
    [ "$EXIT_STATUS" -ne "0" ] || EXIT_STATUS="1"
    [ "$#" -eq "0" ] || lk_console_error "$(_lk_caller): $1"
    lk_is_true "${LK_DIE_HAPPY:-0}" || exit "$EXIT_STATUS"
    exit 0
}

function lk_trap_exit() {
    function lk_exit_trap() {
        local EXIT_STATUS="$?" i
        [ "$EXIT_STATUS" -eq "0" ] ||
            [ "${FUNCNAME[1]:-}" = "lk_die" ] ||
            lk_console_error "$(_lk_caller): unhandled error"
        for i in ${LK_EXIT_DELETE[@]+"${LK_EXIT_DELETE[@]}"}; do
            rm -Rf -- "$i" || true
        done
    }
    LK_EXIT_DELETE=()
    trap 'lk_exit_trap' EXIT
}

function lk_delete_on_exit() {
    lk_variable_declared "LK_EXIT_DELETE" ||
        lk_trap_exit
    LK_EXIT_DELETE+=("$@")
}

function lk_mktemp_file() {
    gnu_mktemp -t "$(basename "$0").$(lk_timestamp).XXX"
}

function lk_mktemp_dir() {
    gnu_mktemp -dt "$(basename "$0").$(lk_timestamp).XXX"
}

function lk_mktemp_fifo() {
    local FIFO_PATH
    FIFO_PATH="$(lk_mktemp_dir)/fifo" &&
        mkfifo "$FIFO_PATH" &&
        echo "$FIFO_PATH"
}

function lk_commands_exist() {
    while [ "$#" -gt "0" ]; do
        type -P "$1" >/dev/null || return
        shift
    done
}

function lk_command_exists() {
    type -P "$1" >/dev/null
}

function lk_first_existing_command() {
    local COMMAND
    for COMMAND in "$@"; do
        if type -P "$COMMAND" >/dev/null; then
            echo "$COMMAND"
            return
        fi
    done
    false
}

function lk_first_existing_parent() {
    local FILE
    FILE="$(realpath --canonicalize-missing "$1")" || return
    while [ ! -e "$FILE" ]; do
        FILE="$(dirname "$FILE")"
    done
    echo "$FILE"
}

# lk_bash_at_least major [minor]
function lk_bash_at_least() {
    [ "${BASH_VERSINFO[0]}" -eq "$1" ] &&
        [ "${BASH_VERSINFO[1]}" -ge "${2:-0}" ] ||
        [ "${BASH_VERSINFO[0]}" -gt "$1" ]
}

if lk_bash_at_least 4 2; then
    function lk_date() {
        # take advantage of printf support for strftime in Bash 4.2+
        printf "%($1)T\n" -1
    }
else
    function lk_date() {
        date +"$1"
    }
fi

function lk_now() {
    lk_date "%Y-%m-%d %H:%M:%S %z"
}

function lk_date_log() {
    lk_date "%b %_d %H:%M:%S %z"
}

function lk_date_log_nano() {
    gnu_date +"%b %_d %H:%M:%S.%N %z"
}

function lk_date_ymdhms() {
    lk_date "%Y%m%d%H%M%S"
}

function lk_date_Ymd() {
    lk_date "%Y%m%d"
}

function lk_date_ymd() {
    lk_date "%y%m%d"
}

function lk_timestamp() {
    lk_date "%s"
}

if lk_bash_at_least 4 1; then
    function lk_pause() {
        read -sN 1 -p "${1:-Press any key to continue . . . }"
        echo
    }
else
    function lk_pause() {
        read -sp "${1:-Press return to continue . . . }"
        echo
    }
fi

function lk_is_root() {
    [ "$EUID" -eq "0" ]
}

function lk_is_yes() {
    [[ "$1" =~ ^[yY]$ ]]
}

function lk_is_no() {
    [[ "$1" =~ ^[nN]$ ]]
}

function lk_is_true() {
    [[ "$1" =~ ^([yY1])$ ]]
}

function lk_is_false() {
    [[ "$1" =~ ^([nN0])$ ]]
}

function lk_full_name() {
    getent passwd "${1:-$UID}" | cut -d: -f5 | cut -d, -f1
}

# [ESCAPE=escape_with] lk_escape string [escape_char1...]
function lk_escape() {
    local i=0 STRING="$1" ESCAPE="${ESCAPE:-\\}" SPECIAL SEARCH REPLACE
    shift
    SPECIAL=("$ESCAPE" "$@")
    [ "$ESCAPE" != "\\" ] || ESCAPE="\\\\"
    for REPLACE in "${SPECIAL[@]}"; do
        # ensure ESCAPE itself is only escaped once
        [ "$i" -eq "0" ] || [ "$REPLACE" != "${SPECIAL[0]}" ] || continue
        SEARCH="\\$REPLACE"
        [ "$REPLACE" != "\$" ] || REPLACE="\\\$"
        [ "$REPLACE" != "\`" ] || REPLACE="\\\`"
        [ "$REPLACE" != "\\" ] || REPLACE="\\\\"
        [ "$REPLACE" != "\"" ] || REPLACE="\\\""
        [ "$REPLACE" != "}" ] || REPLACE="\\}"
        [ "$REPLACE" != "'" ] || REPLACE="\\'"
        eval "STRING=\"\${STRING//$SEARCH/$ESCAPE$REPLACE}\""
        ((++i))
    done
    echo "$STRING"
}

# lk_esc STRING
#   POSIX-conformant implementation of `lk_escape_double_quotes`
function lk_esc() {
    echo "$1" | sed -Ee 's/\\/\\\\/g' -e 's/[$`"]/\\&/g'
}

# lk_esc_ere STRING
#   POSIX-conformant implementation of `lk_escape_ere`
function lk_esc_ere() {
    echo "$1" | sed -Ee 's/\\/\\\\/g' -e 's/[]$()*+./?[^{|}]/\\&/g'
}

function lk_escape_double_quotes() {
    lk_escape "$1" '$' '`' '\' '"'
}

function lk_escape_ere() {
    lk_escape "$1" '$' '(' ')' '*' '+' '.' '/' '?' '[' '\' ']' '^' '{' '|' '}'
}

function lk_escape_ere_replace() {
    lk_escape "$1" '&' '/' '\'
}

# lk_replace find replace_with [string]
#   Replace all occurrences of FIND in STRING with REPLACE_WITH. If STRING
#   is not specified, replace FIND in input.
function lk_replace() {
    local _LK_SEARCH="${_LK_SEARCH:-}"
    [ -n "$_LK_SEARCH" ] || {
        _LK_SEARCH="$(lk_escape "$1." '*' '?' '[' ']' '(')"
        _LK_SEARCH="${_LK_SEARCH%.}"
    }
    [ "$#" -gt "2" ] &&
        echo "${3//$_LK_SEARCH/$2}${_LK_APPEND:-}" ||
        lk_xargs lk_replace "$1" "$2"
}

# lk_in_string needle haystack
#   True if NEEDLE is a substring of HAYSTACK.
function lk_in_string() {
    [ "$(_LK_APPEND="." lk_replace "$1" "" "$2")" != "$2." ]
}

function lk_lower() {
    [ "$#" -gt "0" ] &&
        echo "$*" | tr '[:upper:]' '[:lower:]' ||
        tr '[:upper:]' '[:lower:]'
}

function lk_upper() {
    [ "$#" -gt "0" ] &&
        echo "$*" | tr '[:lower:]' '[:upper:]' ||
        tr '[:lower:]' '[:upper:]'
}

function lk_upper_first() {
    printf '%s%s\n' "$(lk_upper "${1:0:1}")" "$(lk_lower "${1:1}")"
}

function lk_trim() {
    [ "$#" -gt "0" ] &&
        echo "$1" | sed -Ee 's/^\s+//' -e 's/\s+$//' ||
        sed -Ee 's/^\s+//' -e 's/\s+$//'
}

# lk_ellipsis length [string]
function lk_ellipsis() {
    [ "$#" -gt "1" ] &&
        echo "$2" | sed -E "s/^(.{$(("$1" - 3))}).{4,}/\1.../" ||
        sed -E "s/^(.{$(("$1" - 3))}).{4,}/\1.../"
}

function lk_repeat() {
    eval "printf \"\$1%.s\" {1..$2}"
}

function lk_hostname() {
    hostname -s | lk_lower
}

function lk_safe_tput() {
    if lk_is_true "${LK_ON_TERMINAL:-1}" && tput "$@" >/dev/null 2>&1; then
        tput "$@"
    fi
}

function lk_get_colours() {
    local PREFIX="${1-LK_}"
    # foreground
    echo "${PREFIX}BLACK=\"\$(lk_safe_tput setaf 0)\""
    echo "${PREFIX}RED=\"\$(lk_safe_tput setaf 1)\""
    echo "${PREFIX}GREEN=\"\$(lk_safe_tput setaf 2)\""
    echo "${PREFIX}YELLOW=\"\$(lk_safe_tput setaf 3)\""
    echo "${PREFIX}BLUE=\"\$(lk_safe_tput setaf 4)\""
    echo "${PREFIX}MAGENTA=\"\$(lk_safe_tput setaf 5)\""
    echo "${PREFIX}CYAN=\"\$(lk_safe_tput setaf 6)\""
    echo "${PREFIX}WHITE=\"\$(lk_safe_tput setaf 7)\""
    echo "${PREFIX}GREY=\"\$(lk_safe_tput setaf 8)\""
    # background
    echo "${PREFIX}BLACK_BG=\"\$(lk_safe_tput setab 0)\""
    echo "${PREFIX}RED_BG=\"\$(lk_safe_tput setab 1)\""
    echo "${PREFIX}GREEN_BG=\"\$(lk_safe_tput setab 2)\""
    echo "${PREFIX}YELLOW_BG=\"\$(lk_safe_tput setab 3)\""
    echo "${PREFIX}BLUE_BG=\"\$(lk_safe_tput setab 4)\""
    echo "${PREFIX}MAGENTA_BG=\"\$(lk_safe_tput setab 5)\""
    echo "${PREFIX}CYAN_BG=\"\$(lk_safe_tput setab 6)\""
    echo "${PREFIX}WHITE_BG=\"\$(lk_safe_tput setab 7)\""
    echo "${PREFIX}GREY_BG=\"\$(lk_safe_tput setab 8)\""
    # other
    echo "${PREFIX}BOLD=\"\$(lk_safe_tput bold)\""
    echo "${PREFIX}DIM=\"\$(lk_safe_tput dim)\""
    echo "${PREFIX}STANDOUT=\"\$(lk_safe_tput smso)\""
    echo "${PREFIX}STANDOUT_OFF=\"\$(lk_safe_tput rmso)\""
    echo "${PREFIX}WRAP=\"\$(lk_safe_tput smam)\""
    echo "${PREFIX}WRAP_OFF=\"\$(lk_safe_tput rmam)\""
    echo "${PREFIX}RESET=\"\$(lk_safe_tput sgr0)\""
}

function lk_maybe_plural() {
    [ "$1" -eq "1" ] && echo "$2" || echo "$3"
}

function lk_echo_array() {
    printf '%s\n' "$@"
}

function lk_implode() {
    local DELIM="$1"
    DELIM="${DELIM//\\/\\\\}"
    DELIM="${DELIM//%/%%}"
    shift
    [ "$#" -eq "0" ] || {
        printf '%s' "$1"
        shift
    }
    [ "$#" -eq "0" ] ||
        printf "$DELIM%s" "$@"
}

# lk_in_array value array_name
#   True if VALUE exists in ARRAY_NAME.
#   Pattern matching is not applied.
function lk_in_array() {
    [ -n "$1" ] || return
    eval "[ \"\${#$2[@]}\" -gt \"0\" ]" || return
    eval "printf '%s\0' \"\${$2[@]}\"" | grep -zFx -- "$1" >/dev/null
}

# lk_array_search value array_name
#   Search ARRAY_NAME for VALUE and output the key at which it first appears.
#   False if VALUE is not matched.
#   Array values are compared with VALUE using Bash pattern matching.
function lk_array_search() {
    local KEYS KEY
    eval "KEYS=(\"\${!$2[@]}\")"
    for KEY in ${KEYS[@]+"${KEYS[@]}"}; do
        eval "[[ \"\${$2[\$KEY]}\" != \$1 ]]" || {
            echo "$KEY"
            return
        }
    done
    false
}

# lk_xargs command [arg...]
#   Analogous to xargs(1).
function lk_xargs() {
    local LINE
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        "$@" "$LINE"
    done
}

# lk_mapfile [-z] file_path array_name [ignore_pattern]
function lk_mapfile() {
    local READ_ARGS GREP_ARGS LINE
    if [ "${1:-}" = "-z" ]; then
        READ_ARGS+=(-d $'\0')
        GREP_ARGS+=(-z)
        shift
    fi
    [ -e "$1" ] || lk_warn "file not found: $1" || return
    lk_is_identifier "$2" || lk_warn "not a valid identifier: $2" || return
    eval "$2=()"
    while IFS= read -r ${READ_ARGS[@]+"${READ_ARGS[@]}"} LINE ||
        [ -n "$LINE" ]; do
        eval "$2+=(\"\$LINE\")"
    done < <(
        if [ -n "${3:-}" ]; then
            grep -Ev ${GREP_ARGS[@]+"${GREP_ARGS[@]}"} "$3" "$1" || true
        else
            cat "$1"
        fi
    )
}

# lk_echoc [-neE] message [colour_sequence...]
function lk_echoc() {
    local ECHO_ARGS=() MESSAGE IFS COLOUR
    while [[ "${1:-}" =~ ^-[neE]+$ ]]; do
        ECHO_ARGS+=("$1")
        shift
    done
    MESSAGE="${1:-}"
    shift || true
    if [ "$#" -gt "0" ] && [ -n "$LK_RESET" ]; then
        IFS=
        COLOUR="$*"
        unset IFS
        MESSAGE="$(lk_replace "$LK_RESET" "$LK_RESET$COLOUR" "$MESSAGE")"
    fi
    echo ${ECHO_ARGS[@]+"${ECHO_ARGS[@]}"} "${COLOUR:-}$MESSAGE$LK_RESET"
}

# lk_console_message message [[secondary_message] colour_sequence]
function lk_console_message() {
    local PREFIX="${LK_CONSOLE_PREFIX-==> }" MESSAGE="$1" MESSAGE2 SPACES COLOUR BOLD_COLOUR
    shift
    ! lk_in_string $'\n' "$MESSAGE" || {
        SPACES=$'\n'"$(lk_repeat " " "$((${#PREFIX}))")"
        MESSAGE="${MESSAGE//$'\n'/$SPACES}"
    }
    [ "$#" -le "1" ] || {
        MESSAGE2="$1"
        shift
        ! lk_in_string $'\n' "$MESSAGE2" &&
            MESSAGE2=" $MESSAGE2" || {
            SPACES=$'\n'"$(lk_repeat " " "$((${#PREFIX} + 2))")"
            MESSAGE2="$SPACES${MESSAGE2//$'\n'/$SPACES}"
        }
    }
    COLOUR="${1-$LK_DEFAULT_CONSOLE_COLOUR}"
    BOLD_COLOUR="$(lk_in_string "$LK_BOLD" "$COLOUR" || echo "$LK_BOLD")$COLOUR"
    echo "$(
        # - atomic unless larger than buffer (smaller of PIPE_BUF, BUFSIZ)
        # - there's no portable way to determine buffer size
        # - writing <=512 bytes with echo or printf should be atomic on all
        #   platforms, but this can't be guaranteed
        lk_echoc -n "$PREFIX" "${LK_CONSOLE_PREFIX_COLOUR-$BOLD_COLOUR}"
        lk_echoc -n "$MESSAGE" "${LK_CONSOLE_MESSAGE_COLOUR-$LK_BOLD}"
        [ -z "${MESSAGE2:-}" ] || lk_echoc -n "$MESSAGE2" "${LK_CONSOLE_SECONDARY_COLOUR-$COLOUR}"
    )" >&2
}

function lk_console_detail() {
    local LK_CONSOLE_PREFIX="${LK_CONSOLE_PREFIX-   -> }" \
        LK_CONSOLE_MESSAGE_COLOUR
    LK_CONSOLE_MESSAGE_COLOUR=""
    lk_console_message "$1" "${2:-}" "${3-$LK_YELLOW}"
}

function lk_console_detail_list() {
    local LK_CONSOLE_PREFIX="${LK_CONSOLE_PREFIX-   -> }" \
        LK_CONSOLE_MESSAGE_COLOUR
    LK_CONSOLE_MESSAGE_COLOUR=""
    if [ "$#" -le "2" ]; then
        lk_console_list "$1" "${2-$LK_YELLOW}"
    else
        lk_console_list "${@:1:3}" "${4-$LK_YELLOW}"
    fi
}

function _lk_console() {
    local LK_CONSOLE_PREFIX="${LK_CONSOLE_PREFIX-:: }" \
        LK_CONSOLE_MESSAGE_COLOUR LK_CONSOLE_PREFIX_COLOUR
    LK_CONSOLE_MESSAGE_COLOUR="$(
        lk_in_string "$LK_BOLD" "$1" || echo "$LK_BOLD"
    )$2"
    LK_CONSOLE_PREFIX_COLOUR="$LK_BOLD$2"
    lk_console_message "$1"
}

function lk_console_log() {
    _lk_console "$1" "$LK_DEFAULT_CONSOLE_COLOUR"
}

function lk_console_warning() {
    _lk_console "$1" "$LK_WARNING_COLOUR"
}

function lk_console_error() {
    _lk_console "$1" "$LK_ERROR_COLOUR"
}

# lk_console_item message item [colour_sequence]
function lk_console_item() {
    lk_console_message "$1" "$2" "${3-$LK_DEFAULT_CONSOLE_COLOUR}"
}

# lk_console_list message [single_noun plural_noun] [colour_sequence]
function lk_console_list() {
    local MESSAGE SINGLE_NOUN PLURAL_NOUN COLOUR ITEMS LIST SPACES \
        LK_CONSOLE_PREFIX="${LK_CONSOLE_PREFIX-==> }"
    MESSAGE="$1"
    shift
    [ "$#" -le "1" ] || {
        SINGLE_NOUN="$1"
        PLURAL_NOUN="$2"
        shift 2
    }
    COLOUR="${1-$LK_DEFAULT_CONSOLE_COLOUR}"
    lk_mapfile /dev/stdin ITEMS
    lk_console_message "$MESSAGE" "$COLOUR"
    LIST="$(lk_echo_array "${ITEMS[@]}" |
        COLUMNS="${COLUMNS+$((COLUMNS - ${#LK_CONSOLE_PREFIX} - 2))}" \
            column -s $'\n' | expand)"
    SPACES="$(lk_repeat " " "$((${#LK_CONSOLE_PREFIX} + 2))")"
    lk_echoc "$SPACES${LIST//$'\n'/$'\n'$SPACES}" "$COLOUR" >&2
    [ -z "${SINGLE_NOUN:-}" ] ||
        LK_CONSOLE_PREFIX="$SPACES" lk_console_detail "(${#ITEMS[@]} $(
            lk_maybe_plural "${#ITEMS[@]}" "$SINGLE_NOUN" "$PLURAL_NOUN"
        ))" "" ""
}

# lk_console_read prompt [default [read_arg...]]
function lk_console_read() {
    local PROMPT=("$1") DEFAULT="${2:-}" VALUE
    [ -z "$DEFAULT" ] || PROMPT+=("[$DEFAULT]")
    read -rep "$LK_BOLD${LK_CONSOLE_PREFIX_COLOUR-$LK_DEFAULT_CONSOLE_COLOUR}:: $LK_RESET$LK_BOLD${PROMPT[*]}$LK_RESET " "${@:3}" VALUE || return
    [ -n "$VALUE" ] || VALUE="$DEFAULT"
    echo "$VALUE"
}

# lk_console_read_secret prompt [read_arg...]
function lk_console_read_secret() {
    lk_console_read "$1" "" -s "${@:2}" && echo >&2
}

# lk_confirm prompt [default [read_arg...]]
function lk_confirm() {
    local PROMPT=("$1") DEFAULT="${2:-}" VALUE
    if lk_is_true "$DEFAULT"; then
        PROMPT+=("[Y/n]")
        DEFAULT=Y
    elif lk_is_false "$DEFAULT"; then
        PROMPT+=("[y/N]")
        DEFAULT=N
    else
        PROMPT+=("[y/n]")
        DEFAULT=
    fi
    while ! [[ "${VALUE:-}" =~ ^(Y|YES|N|NO)$ ]]; do
        read -rep "$LK_BOLD${LK_CONSOLE_PREFIX_COLOUR-$LK_DEFAULT_CONSOLE_COLOUR}:: $LK_RESET$LK_BOLD${PROMPT[*]}$LK_RESET " "${@:3}" VALUE || VALUE="$DEFAULT"
        [ -n "$VALUE" ] &&
            VALUE="$(lk_upper "$VALUE")" ||
            VALUE="$DEFAULT"
    done
    [[ "$VALUE" =~ ^(Y|YES)$ ]]
}

function lk_no_input() {
    [ ! -t 0 ] ||
        lk_is_true "${LK_NO_INPUT:-}"
}

# lk_add_file_suffix file_path suffix [ext]
#   Add SUFFIX to FILE_PATH without changing FILE_PATH's extension.
#   Use EXT for special extensions like ".tar.gz".
function lk_add_file_suffix() {
    local BASENAME
    BASENAME="$(basename "$1")"
    if [ -z "${3:-}" ] && [[ "$BASENAME" =~ .+\..+ ]]; then
        echo "${1%.*}${2}.${1##*.}"
    elif [ -n "${3:-}" ] && eval "[[ \"$BASENAME\" =~ .+${3//./\\.}\$ ]]"; then
        echo "${1%$3}${2}${3}"
    else
        echo "${1}${2}"
    fi
}

# lk_next_backup_file file_path
#   Output FILE_PATH with suffix "_backup" or "_backup.N", where N is 2 or
#   greater, after finding the first that doesn't already exist.
function lk_next_backup_file() {
    local BACKUP i=1
    BACKUP="$(lk_add_file_suffix "$1" "_backup")"
    while [ -e "$BACKUP" ]; do
        ((++i))
        BACKUP="$(lk_add_file_suffix "$1" "_backup.$i")"
    done
    echo "$BACKUP"
}

# lk_maybe_add_extension file_path ext
#   Output ${FILE_PATH}${EXT} unless FILE_PATH already ends with EXT.
function lk_maybe_add_extension() {
    [ -n "$1" ] || lk_warn "no filename" || return
    [[ "$(lk_lower "$1")" =~ $(lk_escape_ere "$(lk_lower "$2")")$ ]] &&
        echo "$1" ||
        echo "$1$2"
}

function lk_mime_type() {
    [ -e "$1" ] || lk_warn "file not found: $1" || return
    file --brief --mime-type "$1"
}

function lk_is_pdf() {
    local MIME_TYPE
    MIME_TYPE="$(lk_mime_type "$1")" &&
        [ "$MIME_TYPE" = "application/pdf" ]
}

# lk_is_uri uri
#   True if URI is a valid Uniform Resource Identifier with explicit scheme
#   and authority components ("scheme://host" at minimum).
#   See https://en.wikipedia.org/wiki/Uniform_Resource_Identifier
function lk_is_uri() {
    local URI_REGEX='^(([a-zA-Z][-a-zA-Z0-9+.]*):)(//(([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+)(:([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]*))?@)?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+|\[([0-9a-fA-F:]+)\])(:([0-9]+))?)([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@/]+)?(\?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]+))?(#([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]*))?$'
    [[ "$1" =~ $URI_REGEX ]]
}

# lk_uri_parts uri uri_component...
#   Output _KEY="VALUE" for each URI_COMPONENT in URI. URI_COMPONENT must be
#   one of the following (case insensitive, leading underscores accepted):
#     scheme
#     username
#     password
#     host
#       Brackets are included for IPv6 addresses.
#     ipv6_address
#     port
#     path
#     query
#     fragment
function lk_uri_parts() {
    local FORMAT EXPRESSION KEY PART VALUE \
        URI_REGEX='^(([a-zA-Z][-a-zA-Z0-9+.]*):)?(\/\/(([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+)(:([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]*))?@)?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+|\[([0-9a-fA-F:]+)\])(:([0-9]+))?)?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@/]+)?(\?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]+))?(#([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]*))?$'
    FORMAT=()
    EXPRESSION=()
    KEY=()
    for PART in "${@:2}"; do
        FORMAT+=('%s')
        KEY+=("$(lk_upper "_${PART#_}")")
        PART="$(lk_lower "${PART#_}")"
        case "$PART" in
        scheme)
            EXPRESSION+=("a[2]")
            ;;
        username)
            EXPRESSION+=("a[5]")
            ;;
        password)
            EXPRESSION+=("a[7]")
            ;;
        host)
            EXPRESSION+=("a[8]")
            ;;
        ipv6_address)
            EXPRESSION+=("a[9]")
            ;;
        port)
            EXPRESSION+=("a[11]")
            ;;
        path)
            EXPRESSION+=("a[12]")
            ;;
        query)
            EXPRESSION+=("a[14]")
            ;;
        fragment)
            EXPRESSION+=("a[16]")
            ;;
        *)
            lk_warn "unknown URI component '$PART'"
            return 1
            ;;
        esac
    done
    for PART in "${KEY[@]}"; do
        IFS= read -r VALUE || VALUE=
        echo "$PART=\"$(lk_escape_double_quotes "$VALUE")\""
    done < <(gnu_awk "{match(\$0,/$URI_REGEX/,a);printf \"$(lk_implode '\n' "${FORMAT[@]}")\n\",$(lk_implode ',' "${EXPRESSION[@]}")}" <<<"$1")
}

# lk_get_uris [file_path...]
#   Match and output URIs ("scheme://host" at minimum) in standard input or
#   each FILE_PATH.
function lk_get_uris() {
    local EXIT_STATUS=0 \
        URI_REGEX='\b(([a-zA-Z][-a-zA-Z0-9+.]*):)(//(([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+)(:([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]*))?@)?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=]+|\[([0-9a-fA-F:]+)\])(:([0-9]+))?)([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@/]+)?(\?([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]+))?(#([-a-zA-Z0-9._~%!$&'"'"'()*+,;=:@?/]*))?\b'
    grep -Eo "$URI_REGEX" "$@" || EXIT_STATUS="$?"
    # exit 0 unless there's an actual error
    [ "$EXIT_STATUS" -eq 0 ] || [ "$EXIT_STATUS" -eq 1 ]
}

# lk_wget_uris url
#   Match and output URIs ("scheme://host" at minimum) in the file downloaded
#   from URL. URIs are converted during download using `wget --convert-links`.
function lk_wget_uris() {
    local TEMP_FILE
    # without --output-document, --convert-links doesn't work
    TEMP_FILE="$(lk_mktemp_file)" &&
        lk_delete_on_exit "$TEMP_FILE" &&
        wget --quiet --convert-links --output-document "$TEMP_FILE" "$1" ||
        return
    lk_get_uris "$TEMP_FILE"
}

function lk_decode_uri() {
    echo -e "${1//%/\\x}"
}

# lk_download file_uri...
#   Download each FILE_URI to the current directory unless an up-to-date
#   version already exists.
#
#   Add "|filename.ext" after each FILE_URI that doesn't include a filename,
#   or call with IGNORE_FILENAMES=1 to use the server-specified filename.
#   If IGNORE_FILENAMES=1, existing downloads are ignored and/or overwritten.
function lk_download() {
    local IGNORE_FILENAMES="${IGNORE_FILENAMES:-0}" CURL_VERSION URI FILENAME \
        DOWNLOAD_ONE DOWNLOAD_ARGS _PATH FILENAMES=() ONE_DOWNLOAD_ARGS=() MANY_DOWNLOAD_ARGS=() \
        CURL_ARGS=(--location --remote-time) ARGS
    CURL_VERSION="$(curl --version | grep -Eo '\b[0-9]+(\.[0-9]+){1,2}\b' | head -n1)" ||
        lk_warn "curl version unknown" || return
    lk_is_false "$IGNORE_FILENAMES" || {
        # TODO: download to a temporary directory and move to $PWD only if successful
        lk_version_at_least "$CURL_VERSION" "7.26.0" ||
            lk_warn "installed version of curl too old to output effective filename" || return
        CURL_ARGS+=(--remote-header-name --write-out "%{filename_effective}\n")
    }
    ! lk_version_at_least "$CURL_VERSION" "7.66.0" ||
        CURL_ARGS+=(--parallel)
    while IFS='|' read -r URI FILENAME; do
        [ -n "$URI" ] || continue
        lk_is_uri "$URI" || lk_warn "not a URI: $URI" || return
        DOWNLOAD_ONE=0
        DOWNLOAD_ARGS=()
        if lk_is_true "$IGNORE_FILENAMES"; then
            DOWNLOAD_ARGS+=(--remote-name)
        else
            [ -n "$FILENAME" ] || {
                eval "$(lk_uri_parts "$URI" "_PATH")"
                FILENAME="${_PATH##*/}"
            }
            [ -n "$FILENAME" ] || lk_warn "no filename in '$URI'" || return
            [ ! -f "$FILENAME" ] || {
                DOWNLOAD_ONE=1
                DOWNLOAD_ARGS+=(--time-cond "$(date -Rd "$(gnu_stat --printf '%y' "$FILENAME")")")
            }
            DOWNLOAD_ARGS+=(--output "$FILENAME")
            FILENAMES+=("$FILENAME")
        fi
        DOWNLOAD_ARGS+=("$URI")
        if lk_is_true "$DOWNLOAD_ONE"; then
            ONE_DOWNLOAD_ARGS+=("$(declare -p DOWNLOAD_ARGS)")
        else
            MANY_DOWNLOAD_ARGS+=("${DOWNLOAD_ARGS[@]}")
        fi
    done < <(
        [ "$#" -gt "0" ] &&
            printf '%s\n' "$@" ||
            cat
    )
    [ "${#MANY_DOWNLOAD_ARGS[@]}" -eq "0" ] ||
        curl "${CURL_ARGS[@]}" "${MANY_DOWNLOAD_ARGS[@]}" || return
    [ "${#ONE_DOWNLOAD_ARGS[@]}" -eq "0" ] ||
        for ARGS in "${ONE_DOWNLOAD_ARGS[@]}"; do
            eval "$ARGS"
            curl "${CURL_ARGS[@]}" "${DOWNLOAD_ARGS[@]}" || return
        done
    lk_is_true "$IGNORE_FILENAMES" ||
        lk_echo_array "${FILENAMES[@]}"
}

function lk_can_sudo() {
    local ERROR
    lk_command_exists sudo && {
        ERROR="$(sudo -nv 2>&1)" ||
            # "sudo: a password is required" means the user can sudo
            grep -i password <<<"$ERROR" >/dev/null
    }
}

# SUDO_OR_NOT=<1|0|Y|N> lk_maybe_sudo command [arg1...]
function lk_maybe_sudo() {
    if lk_is_true "${SUDO_OR_NOT:-0}"; then
        lk_elevate "$@"
    else
        "$@"
    fi
}

function lk_elevate() {
    if [ "$EUID" -eq "0" ]; then
        "$@"
    else
        sudo -H -E "$@"
    fi
}

function lk_maybe_elevate() {
    if [ "$EUID" -eq "0" ] || ! lk_can_sudo; then
        "$@"
    else
        sudo -H -E "$@"
    fi
}

# lk_safe_symlink target_path link_path [use_sudo [try_default]]
function lk_safe_symlink() {
    local TARGET LINK LINK_DIR CURRENT_TARGET \
        SUDO_OR_NOT="${3:-${SUDO_OR_NOT:-0}}" TRY_DEFAULT="${4:-0}"
    TARGET="$1"
    LINK="$2"
    [ -n "$LINK" ] || return
    [ -e "$TARGET" ] || {
        lk_is_true "$TRY_DEFAULT" &&
            TARGET="$(lk_add_file_suffix "$TARGET" "-default")" &&
            [ -e "$TARGET" ] || return
    }
    LINK_DIR="$(dirname "$LINK")"
    LK_SAFE_SYMLINK_NO_CHANGE=
    if lk_maybe_sudo test -L "$LINK"; then
        CURRENT_TARGET="$(lk_maybe_sudo readlink "$LINK")" || return
        [ "$CURRENT_TARGET" != "$TARGET" ] || {
            LK_SAFE_SYMLINK_NO_CHANGE=1
            return
        }
        lk_maybe_sudo rm -f "$LINK" || return
    elif lk_maybe_sudo test -e "$LINK"; then
        lk_maybe_sudo mv -fv "$LINK" "$LINK${BACKUP_SUFFIX:-.orig}" || return
    elif lk_maybe_sudo test ! -d "$LINK_DIR"; then
        lk_maybe_sudo mkdir -pv "$LINK_DIR" || return
    fi
    lk_maybe_sudo ln -sv "$TARGET" "$LINK"
}

function _lk_get_gnu_command() {
    case "$1" in
    awk)
        echo "gawk"
        ;;
    *)
        echo "$PREFIX$1"
        ;;
    esac
}

function _lk_register_gnu_commands() {
    local PREFIX="g" COMMAND
    lk_is_macos || PREFIX=
    for COMMAND in "$@"; do
        eval "function gnu_$COMMAND() { $(_lk_get_gnu_command "$COMMAND") \"\$@\"; }"
    done
    LK_GNU_COMMANDS=($(printf '%s\n' ${LK_GNU_COMMANDS[@]+"${LK_GNU_COMMANDS[@]}"} "$@" | sort | uniq))
}

function lk_install_gnu_commands() {
    local PREFIX="g" GNU_PATH="${GNU_PATH:-/usr/local/bin}" COMMAND GCOMMAND COMMAND_PATH \
        COMMANDS=("$@") EXIT_STATUS=0
    lk_is_macos || PREFIX=
    [ ! -e "$GNU_PATH" ] ||                                     # GNU_PATH does not exist; or
        [ -d "$GNU_PATH" ] ||                                   # is a directory
        lk_warn "not a directory: $GNU_PATH" || return          # ...
    [ -w "$GNU_PATH" ] ||                                       # it's also writable; or
        lk_is_true "${SUDO_OR_NOT:-0}" ||                       # will be installed as superuser; or
        { [ ! -e "$GNU_PATH" ] &&                               # does not exist but the
            PARENT="$(lk_first_existing_parent "$GNU_PATH")" && # first existing parent dir
            [ -w "$PARENT" ]; } ||                              # is writable; or
        { [ "$GNU_PATH" = "/usr/local/bin" ] &&                 # has not been customised and
            [ -n "${HOME:-}" ] &&                               # HOME is set, so
            GNU_PATH="$HOME/.local/bin"; } ||                   # $HOME/.local/bin is suitable
        lk_warn "cannot write to directory: $GNU_PATH" || return
    [ "$#" -gt "0" ] || COMMANDS=(${LK_GNU_COMMANDS[@]+"${LK_GNU_COMMANDS[@]}"})
    for COMMAND in ${COMMANDS[@]+"${COMMANDS[@]}"}; do
        GCOMMAND="$(_lk_get_gnu_command "$COMMAND")"
        { lk_command_exists "$GCOMMAND" ||
            lk_warn "$GCOMMAND not found"; } &&
            COMMAND_PATH="$(type -P "$GCOMMAND")" &&
            lk_safe_symlink "$COMMAND_PATH" "$GNU_PATH/gnu_$COMMAND" ||
            EXIT_STATUS="$?"
    done
    return "$EXIT_STATUS"
}

function lk_check_gnu_commands() {
    local COMMANDS=("$@") SUDO_OR_NOT="${SUDO_OR_NOT:-0}"
    [ "$#" -gt "0" ] || COMMANDS=(${LK_GNU_COMMANDS[@]+"${LK_GNU_COMMANDS[@]}"})
    if [ "${#COMMANDS[@]}" -gt "0" ]; then
        lk_commands_exist "${COMMANDS[@]/#/gnu_}" || {
            ! lk_can_sudo || SUDO_OR_NOT=1
            lk_install_gnu_commands
        }
    fi
}

function lk_users_exist() {
    while [ "$#" -gt "0" ]; do
        id "$1" >/dev/null 2>&1 || return
        shift
    done
}

function lk_test_many() {
    local TEST="$1" VALUE
    shift
    for VALUE in "$@"; do
        test "$TEST" "$VALUE" || return
    done
}

function lk_paths_exist() {
    [ "$#" -gt "0" ] && lk_test_many "-e" "$@"
}

function lk_files_exist() {
    [ "$#" -gt "0" ] && lk_test_many "-f" "$@"
}

function lk_dirs_exist() {
    [ "$#" -gt "0" ] && lk_test_many "-d" "$@"
}

function lk_remove_false() {
    local _LK_KEYS _LK_KEY _LK_TEST
    eval "_LK_KEYS=(\"\${!$2[@]}\")" &&
        _LK_TEST="$(lk_replace "{}" "\${$2[\$_LK_KEY]}" "$1")" || return
    for _LK_KEY in ${_LK_KEYS[@]+"${_LK_KEYS[@]}"}; do
        eval "$_LK_TEST" || unset "$2[$_LK_KEY]"
    done
}

# lk_remove_missing ARRAY
#   Reduce ARRAY to elements that are paths to existing files or directories.
function lk_remove_missing() {
    lk_remove_false "[ -e \"{}\" ]" "$1"
}

# lk_resolve_files ARRAY
#   Remove paths to missing files from ARRAY, then resolve remaining paths to
#   absolute file names and remove any duplicates.
function lk_resolve_files() {
    local _LK_TEMP_FILE
    lk_is_identifier "$1" || lk_warn "not a valid identifier: $1" || return
    lk_remove_missing "$1" &&
        _LK_TEMP_FILE="$(lk_mktemp_file)" &&
        lk_delete_on_exit "$_LK_TEMP_FILE" &&
        eval "realpath -ez \"\${$1[@]}\"" | sort -zu >"$_LK_TEMP_FILE" &&
        lk_mapfile -z /dev/stdin "$1" <"$_LK_TEMP_FILE"
}

function lk_sort_paths_by_date() {
    gnu_stat --printf '%Y :%n\0' "$@" | sort -zn | sed -zE 's/^[0-9]+ ://' | xargs -0 printf '%s\n'
}

function lk_is_identifier() {
    [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

function lk_variable_declared() {
    declare -p "$1" >/dev/null 2>&1
}

# lk_version_at_least installed_version minimum_version
function lk_version_at_least() {
    local MIN
    MIN="$(gnu_sort --version-sort <(printf '%s\n' "$1" "$2") | head -n1 || lk_warn "error sorting versions")" &&
        [ "$MIN" = "$2" ]
}

function lk_return_cached() {
    lk_variable_declared "$1" || {
        eval "$1=0;{ $2;}||$1=\"\$?\""
    }
    return "${!1}"
}

function lk_is_macos() {
    lk_return_cached LK_IS_MACOS '[ "$(uname -s)" = "Darwin" ]'
}

function lk_is_linux() {
    lk_return_cached LK_IS_LINUX '[ "$(uname -s)" = "Linux" ]'
}

function lk_is_wsl() {
    lk_return_cached LK_IS_WSL 'lk_is_linux && grep -qi microsoft /proc/version >/dev/null 2>&1'
}

function lk_is_arch() {
    lk_return_cached LK_IS_ARCH 'lk_is_linux && [ -f "/etc/arch-release" ]'
}

function lk_is_ubuntu() {
    lk_return_cached LK_IS_UBUNTU 'lk_is_linux && lk_command_exists lsb_release && [ "$(lsb_release -si)" = "Ubuntu" ]'
}

function lk_is_ubuntu_lts() {
    lk_return_cached LK_IS_UBUNTU_LTS 'lk_is_ubuntu && lk_command_exists ubuntu-distro-info && ubuntu-distro-info --supported-esm | grep -Fx "$(lsb_release -sc)" >/dev/null 2>&1'
}

function lk_ubuntu_at_least() {
    lk_is_ubuntu && lk_version_at_least "$(lsb_release -sr)" "$1"
}

function lk_is_desktop() {
    lk_return_cached LK_IS_DESKTOP 'lk_is_macos || lk_command_exists X'
}

function lk_is_server() {
    ! lk_is_desktop
}

function lk_is_virtual() {
    lk_return_cached LK_IS_VIRTUAL 'lk_is_linux && grep -Eq "^flags\\s*:.*\\shypervisor(\\s|\$)" /proc/cpuinfo'
}

function lk_is_qemu() {
    lk_return_cached LK_IS_QEMU 'lk_is_virtual && grep -Eiq qemu /sys/devices/virtual/dmi/id/*_vendor'
}

function lk_ssl_client() {
    local HOST="${1:-}" PORT="${2:-}" SERVER_NAME="${3:-${1:-}}"
    [ -n "$HOST" ] || lk_warn "no hostname" || return
    [ -n "$PORT" ] || lk_warn "no port" || return
    openssl s_client -connect "$HOST":"$PORT" -servername "$SERVER_NAME"
}

# lk_grep_ipv4
#   Print each input line that is a valid dotted-decimal IPv4 address or CIDR.
function lk_grep_ipv4() {
    local OCTET='(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])'
    grep -E "^($OCTET\.){3}$OCTET(/(3[0-2]|[12][0-9]|[1-9]))?\$"
}

# lk_grep_ipv6
#   Print each input line that is a valid 8-hextet IPv6 address or CIDR.
function lk_grep_ipv6() {
    local HEXTET='[0-9a-fA-F]{1,4}' \
        PREFIX='/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9])'
    grep -E \
        "^(:|($HEXTET:)+)((:$HEXTET)+|$HEXTET|:)($PREFIX)?\$" |
        grep -E "^(($HEXTET)?:){1,7}($HEXTET)?($PREFIX)?\$"
}

# lk_resolve_hosts host...
function lk_resolve_hosts() {
    local HOSTS IP_ADDRESSES
    IP_ADDRESSES=($({
        lk_echo_array "$@" | lk_grep_ipv4 || :
        lk_echo_array "$@" | lk_grep_ipv6 || :
    }))
    HOSTS=($(comm -23 <(lk_echo_array "$@" | sort | uniq) \
        <(lk_echo_array "${IP_ADDRESSES[@]}" | sort | uniq)))
    IP_ADDRESSES+=($(eval \
        "dig +short ${HOSTS[*]/%/ A} ${HOSTS[*]/%/ AAAA}" |
        sed -E '/\.$/d')) || return
    lk_echo_array "${IP_ADDRESSES[@]}" | sort | uniq
}

# lk_start_or_restart command [arg1...]
#   Kill any running COMMAND processes, then run COMMAND in the
#   background and disown it.
function lk_start_or_restart() {
    local COMMAND
    COMMAND="$(basename "$1")"
    lk_is_root ||
        ! pgrep -xu "$USER" "$COMMAND" >/dev/null || # limit to processes owned by $USER
        pkill -xu "$USER" "$COMMAND"                 #
    ! lk_is_root ||                                  #
        ! pgrep -x "$COMMAND" >/dev/null ||          # ...unless we're running as root
        pkill -x "$COMMAND"
    ! lk_command_exists "$1" || {
        nohup "$@" </dev/null >/dev/null 2>&1 &
        disown
    }
}

function lk_keep_original() {
    [ ! -e "$1" ] ||
        lk_maybe_sudo cp -nav "$1" "$1${BACKUP_SUFFIX:-.orig}"
}

# lk_maybe_sed sed_arg... input_file
function lk_maybe_sed() {
    local ARGS=("$@") FILE="${*: -1:1}"
    [ -f "$FILE" ] && [ ! -L "$FILE" ] ||
        lk_warn "file not found: $FILE" || return
    lk_remove_false "[[ ! \"{}\" =~ ^(-i|--in-place(=|\$)) ]]" ARGS
    diff -q \
        <(lk_maybe_sudo cat "$FILE") \
        <(lk_maybe_sudo sed "${ARGS[@]}") >/dev/null || {
        lk_keep_original "$FILE" &&
            sed -i "${ARGS[@]}"
    }
}

# lk_apply_setting file_path setting_name setting_value [delimiter] [comment_chars] [space_chars]
#   Set value of SETTING_NAME to SETTING_VALUE in FILE_PATH.
#   DELIMITER defaults to "=".
#   To uncomment an existing SETTING_NAME assignment first, use COMMENT_CHARS
#   to specify which characters can be removed from the beginning of lines.
#   Use SPACE_CHARS to specify whitespace characters considered legal before
#   and after SETTING_NAME, SETTING_VALUE and DELIMITER.
function lk_apply_setting() {
    local FILE_PATH="$1" SETTING_NAME="$2" SETTING_VALUE="$3" DELIMITER="${4:-=}" \
        COMMENT_PATTERN SPACE_PATTERN NAME_ESCAPED VALUE_ESCAPED DELIMITER_ESCAPED CHECK_PATTERN SEARCH_PATTERN REPLACE REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    COMMENT_PATTERN="${5:+[$(lk_escape_ere "$5")]*}"
    SPACE_PATTERN="${6:+[$(lk_escape_ere "$6")]*}"
    NAME_ESCAPED="$(lk_escape_ere "$SETTING_NAME")"
    VALUE_ESCAPED="$(lk_escape_ere "$SETTING_VALUE")"
    DELIMITER_ESCAPED="$(sed -Ee "s/^$SPACE_PATTERN//" -e "s/$SPACE_PATTERN\$//" <<<"$DELIMITER")"
    [ -n "$DELIMITER_ESCAPED" ] || DELIMITER_ESCAPED="$DELIMITER"
    DELIMITER_ESCAPED="$(lk_escape_ere "$DELIMITER_ESCAPED")"
    CHECK_PATTERN="^$SPACE_PATTERN$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED$SPACE_PATTERN$VALUE_ESCAPED$SPACE_PATTERN\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        REPLACE="$SETTING_NAME$DELIMITER$SETTING_VALUE"
        # try to replace an uncommented value first
        SEARCH_PATTERN="^($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        # failing that, try for a commented one
        grep -Eq "$CHECK_PATTERN" <<<"$REPLACED" || {
            SEARCH_PATTERN="^($SPACE_PATTERN)$COMMENT_PATTERN($SPACE_PATTERN)$NAME_ESCAPED$SPACE_PATTERN$DELIMITER_ESCAPED.*\$"
            REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\\1\\2$(lk_escape_ere_replace "$REPLACE")/}" "$FILE_PATH")" || return
        }
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$REPLACE"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}

# EXPAND_WHITESPACE=<1|0|Y|N> lk_enable_entry file_path entry [comment_chars] [trailing_pattern]
#   Add ENTRY to FILE_PATH if not already present.
#   To uncomment an existing ENTRY line first, use COMMENT_CHARS to specify
#   which characters can be removed from the beginning of lines.
#   Use TRAILING_PATTERN to provide a regular expression matching existing text
#   to retain if it appears after ENTRY. The default is to keep whitespace and
#   comments.
#   EXPAND_WHITESPACE is enabled by default. It allows one or more whitespace
#   characters in ENTRY to match one or more whitespace characters in
#   FILE_PATH. If EXPAND_WHITESPACE is enabled, escaped whitespace characters
#   in ENTRY are unescaped without expansion.
function lk_enable_entry() {
    local FILE_PATH="$1" ENTRY="$2" OPTIONAL_COMMENT_PATTERN COMMENT_PATTERN TRAILING_PATTERN \
        ENTRY_ESCAPED SPACE_PATTERN CHECK_PATTERN SEARCH_PATTERN REPLACED
    lk_maybe_sudo test -f "$FILE_PATH" || lk_warn "$FILE_PATH must exist" || return
    OPTIONAL_COMMENT_PATTERN="${3:+[$(lk_escape_ere "$3")]*}"
    COMMENT_PATTERN="${3:+$(lk_trim "$3")}"
    COMMENT_PATTERN="${COMMENT_PATTERN:+[$(lk_escape_ere "$COMMENT_PATTERN")]+}"
    TRAILING_PATTERN="${4-\\s+${COMMENT_PATTERN:+(${COMMENT_PATTERN}.*)?}}"
    ENTRY_ESCAPED="$(lk_escape_ere "$ENTRY")"
    SPACE_PATTERN=
    lk_is_false "${EXPAND_WHITESPACE:-1}" || {
        ENTRY_ESCAPED="$(sed -Ee 's/(^|[^\])\s+/\1\\s+/g' -e 's/\\\\(\s)/\1/g' <<<"$ENTRY_ESCAPED")"
        SPACE_PATTERN='\s*'
    }
    CHECK_PATTERN="^$SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?}\$"
    grep -Eq "$CHECK_PATTERN" "$FILE_PATH" || {
        # try to replace a commented entry
        SEARCH_PATTERN="^($SPACE_PATTERN)$OPTIONAL_COMMENT_PATTERN($SPACE_PATTERN$ENTRY_ESCAPED${TRAILING_PATTERN:+($TRAILING_PATTERN)?})\$"
        REPLACED="$(sed -E "0,/$SEARCH_PATTERN/{s/$SEARCH_PATTERN/\1\2/}" "$FILE_PATH")" || return
        lk_keep_original "$FILE_PATH" || return
        if grep -Eq "$CHECK_PATTERN" <<<"$REPLACED"; then
            lk_maybe_sudo tee "$FILE_PATH" <<<"$REPLACED" >/dev/null || return
        else
            {
                echo "$REPLACED"
                echo "$ENTRY"
            } | lk_maybe_sudo tee "$FILE_PATH" >/dev/null || return
        fi
    }
}

# lk_user_in_group username groupname...
#   True if USERNAME belongs to at least one of GROUPNAME.
function lk_user_in_group() {
    [ "$(comm -12 <(groups "$1" | sed -E 's/^.*://' | grep -Eo '[^[:space:]]+' | sort) <(lk_echo_array "${@:2}" | sort | uniq) | wc -l)" -gt "0" ]
}

# lk_make_iso path...
#  Add each PATH to a new ISO image in the current directory. The .iso file
#  is named after the first file or directory specified.
function lk_make_iso() {
    local ISOFILE
    lk_paths_exist "$@" || lk_warn "all paths must exist" || return
    ISOFILE="$(basename "$1").iso"
    [ ! -e "$ISOFILE" ] || lk_warn "$ISOFILE already exists" || return
    mkisofs -V "$(lk_date "%y%m%d")$(basename "$1")" -J -r -hfs -o "$ISOFILE" "$@"
}

set -o pipefail

# coreutils
#   [ arch b2sum base32 base64 basename cat chcon chgrp chmod chown
#   chroot cksum comm cp csplit cut date dd df dir dircolors dirname du
#   echo env expand expr factor false fmt fold groups head hostid id
#   install join link ln logname ls md5sum md5sum.textutils mkdir mkfifo
#   mknod mktemp mv nice nl nohup nproc numfmt od paste pathchk pinky pr
#   printenv printf ptx pwd readlink realpath rm rmdir runcon seq
#   sha1sum sha224sum sha256sum sha384sum sha512sum shred shuf sleep
#   sort split stat stdbuf stty sum sync tac tail tee test timeout touch
#   tr true truncate tsort tty uname unexpand uniq unlink users vdir wc
#   who whoami yes
_lk_register_gnu_commands chgrp chmod chown date ln mktemp sort stat

# gawk, findutils, grep, netcat, sed, tar
_lk_register_gnu_commands awk find grep nc sed tar xargs

eval "$(lk_get_colours)"

LK_DEFAULT_CONSOLE_COLOUR="$LK_CYAN"
LK_WARNING_COLOUR="$LK_YELLOW"
LK_ERROR_COLOUR="$LK_RED"

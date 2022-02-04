#!/bin/bash

export -n BASH_XTRACEFD SHELLOPTS

USER=${USER:-$(id -un)} &&
    { [ "${S-}" = "[[:blank:]]" ] || readonly S="[[:blank:]]"; } &&
    { [ "${NS-}" = "[^[:blank:]]" ] || readonly NS="[^[:blank:]]"; } || return

_LK_ARGV=("$@")
_LK_PROVIDED=core

# lk_bash_at_least MAJOR [MINOR]
function lk_bash_at_least() {
    [ "${BASH_VERSINFO[0]}" -eq "$1" ] &&
        [ "${BASH_VERSINFO[1]}" -ge "${2:-0}" ] ||
        [ "${BASH_VERSINFO[0]}" -gt "$1" ]
}

function lk_is_arm() {
    [[ $MACHTYPE =~ ^(arm|aarch)64- ]]
}

function lk_is_macos() {
    [[ $OSTYPE == darwin* ]]
}

# lk_is_apple_silicon
#
# Return true if running natively on Apple Silicon, otherwise return false.
# Returns false when running as a translated Intel binary on Apple Silicon.
function lk_is_apple_silicon() {
    lk_is_macos && lk_is_arm
}

# lk_is_system_apple_silicon
#
# Return true if running on Apple Silicon, whether natively or as a translated
# Intel binary.
function lk_is_system_apple_silicon() {
    lk_is_macos && { lk_is_arm ||
        [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ]; }
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
    lk_is_linux && grep -iq Microsoft /proc/version &>/dev/null
}

function lk_is_virtual() {
    lk_is_linux && grep -Eq '^flags[[:blank:]]*:.*\<hypervisor\>' /proc/cpuinfo
}

function lk_is_qemu() {
    lk_is_virtual &&
        grep -iq QEMU /sys/devices/virtual/dmi/id/*_vendor 2>/dev/null
}

# lk_command_exists COMMAND...
function lk_command_exists() {
    [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        type -P "$1" >/dev/null || return
        shift
    done
}

# lk_version_at_least INSTALLED MINIMUM
function lk_version_at_least() {
    printf '%s\n' "$@" | sort -V | head -n1 | grep -Fx "$2" >/dev/null
}

# lk_script_running
#
# Return true if a script file is running. If reading commands from a named pipe
# (e.g. `bash <(list)`), the standard input (`bash -i` or `list | bash`), or the
# command line (`bash -c "string"`), return false.
function lk_script_running() {
    [ "${BASH_SOURCE+${BASH_SOURCE[*]: -1}}" = "$0" ] && [ -f "$0" ]
}

# lk_verbose [LEVEL]
#
# Return true if LK_VERBOSE [default: 0] is at least LEVEL [default: 1].
function lk_verbose() {
    [ "${LK_VERBOSE:-0}" -ge "${1-1}" ]
}

# lk_debug
#
# Return true if LK_DEBUG is set.
function lk_debug() {
    [ "${LK_DEBUG-}" = Y ]
}

# lk_root
#
# Return true if running as the root user.
function lk_root() {
    [ "$EUID" -eq 0 ]
}

# lk_dry_run
#
# Return true if LK_DRY_RUN is set.
function lk_dry_run() {
    [ "${LK_DRY_RUN:-0}" -eq 1 ]

}

# lk_true VAR
#
# Return true if VAR or ${!VAR} is 'Y', 'yes', '1', 'true', or 'on' (not
# case-sensitive).
function lk_true() {
    local REGEX='^([yY]([eE][sS])?|1|[tT][rR][uU][eE]|[oO][nN])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

# lk_false VAR
#
# Return true if VAR or ${!VAR} is 'N', 'no', '0', 'false', or 'off' (not
# case-sensitive).
function lk_false() {
    local REGEX='^([nN][oO]?|0|[fF][aA][lL][sS][eE]|[oO][fF][fF])$'
    [[ $1 =~ $REGEX ]] || [[ ${1:+${!1-}} =~ $REGEX ]]
}

# lk_test TEST [VALUE...]
#
# Return true if every VALUE passes TEST, otherwise return false. If there are
# no VALUE arguments, return false.
function lk_test() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [ -n "${COMMAND+1}" ] && [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        "${COMMAND[@]}" "$1" || break
        shift
    done
    [ $# -eq 0 ]
}

# lk_test_any TEST [VALUE...]
#
# Return true if at least one VALUE passes TEST, otherwise return false.
function lk_test_any() {
    local IFS=$' \t\n' COMMAND
    COMMAND=($1)
    shift
    [ -n "${COMMAND+1}" ] && [ $# -gt 0 ] || return
    while [ $# -gt 0 ]; do
        ! "${COMMAND[@]}" "$1" || break
        shift
    done
    [ $# -gt 0 ]
}

function lk_paths_exist() { lk_test "lk_sudo test -e" "$@"; }

function lk_files_exist() { lk_test "lk_sudo test -f" "$@"; }

function lk_dirs_exist() { lk_test "lk_sudo test -d" "$@"; }

function lk_files_not_empty() { lk_test "lk_sudo test -s" "$@"; }

# lk_pass [-STATUS] COMMAND [ARG...]
#
# Run COMMAND without changing the previous command's exit status, or run
# COMMAND and return STATUS.
function lk_pass() {
    local STATUS=$?
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { STATUS=${1:1} && shift; }
    "$@" || true
    return "$STATUS"
}

# lk_err MESSAGE
function lk_err() {
    lk_pass echo "${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-${0##*/}}: $1" >&2
}

# lk_script_name [STACK_DEPTH]
function lk_script_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    lk_script_running ||
        NAME=${FUNCNAME[1 + DEPTH]+"${FUNCNAME[*]: -1}"}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_caller_name [STACK_DEPTH]
function lk_caller_name() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) NAME
    NAME=${FUNCNAME[2 + DEPTH]-}
    [[ ! ${NAME-} =~ ^(source|main)$ ]] || NAME=
    echo "${NAME:-${0##*/}}"
}

# lk_first_command [COMMAND...]
#
# Print the first executable COMMAND in PATH or return false if no COMMAND was
# found. To allow the inclusion of arguments, word splitting is performed on
# each COMMAND after resetting IFS.
function lk_first_command() {
    local IFS CMD
    unset IFS
    while [ $# -gt 0 ]; do
        CMD=($1)
        ! type -P "${CMD[0]}" >/dev/null || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_first_file [FILE...]
#
# Print the first FILE that exists or return false if no FILE was found.
function lk_first_file() {
    while [ $# -gt 0 ]; do
        [ ! -e "$1" ] || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_first_open [PATH...]
#
# Print the first PATH that is a writable character special file, or return
# false if no such PATH was found.
function lk_first_open() {
    while [ $# -gt 0 ]; do
        { [ ! -c "$1" ] || ! : >"$1"; } 2>/dev/null || break
        shift
    done
    [ $# -gt 0 ] && echo "$1"
}

# lk_get_tty
#
# Print "/dev/tty" if Bash has a controlling terminal, otherwise print
# "/dev/console" if it is open for writing, or return false.
function lk_get_tty() {
    lk_first_open /dev/tty /dev/console
}

# lk_plural [-v] VALUE SINGLE [PLURAL]
#
# Print SINGLE if VALUE is 1 or the name of an array with 1 element, PLURAL
# otherwise. If PLURAL is omitted, print "${SINGLE}s" instead. If -v is set,
# include VALUE in the output.
function lk_plural() {
    local VALUE
    [ "${1-}" != -v ] || { VALUE=1 && shift; }
    local COUNT=$1
    [[ ! $1 =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || eval "COUNT=\${#$1[@]}" || return
    VALUE="${VALUE:+$COUNT }"
    [ "$COUNT" = 1 ] && echo "$VALUE$2" || echo "$VALUE${3-$2s}"
}

# lk_assign VAR
#
# Read standard input until EOF or NUL and assign it to VAR.
#
# Example:
#
#     lk_assign SQL <<"SQL"
#     SELECT id, name FROM table;
#     SQL
function lk_assign() {
    IFS= read -rd '' "$1" || true
}

# lk_x_off [STATUS_VAR]
#
# Output Bash commands that disable xtrace temporarily, prevent themselves from
# appearing in trace output, and assign the previous command's exit status to
# _lk_x_status or STATUS_VAR.
#
# Recommended usage, if FD 2 or FD 4 may already be receiving trace output:
#
#     function quiet() {
#         { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
#         # Can also be used in a && or || list
#         eval "$_lk_x_return"
#     }
#
# Or, outside of a function:
#
#     { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
#     eval "$_lk_x_restore"
function lk_x_off() {
    echo 'eval "{ declare '"${1:-_lk_x_status}=$?"' _lk_x_restore= _lk_x_return=\"return \\\$?\"; [ \"\${-/x/}\" = \"\$-\" ] || { _lk_x_restore=\"set -x\"; _lk_x_return=\"eval \\\"{ local _lk_x_status=\\\\\\\$?; set -x; return \\\\\\\$_lk_x_status; } \\\${BASH_XTRACEFD:-2}>/dev/null\\\"\"; set +x; }; } ${BASH_XTRACEFD:-2}>/dev/null"'
}

function lk_x_no_off() {
    function lk_x_off() {
        echo 'declare '"${1:-_lk_x_status}=$?"' _lk_x_restore= _lk_x_return="return \$?"'
    }
    export _LK_NO_X_OFF=1
}

[ -z "${_LK_NO_X_OFF-}" ] || lk_x_no_off

function _lk_sudo_check() {
    local LK_SUDO_ON_FAIL=${LK_SUDO_ON_FAIL-} LK_EXEC=${LK_EXEC-} SHIFT=0 \
        _LK_STACK_DEPTH=1
    [ "${1-}" != -f ] || { LK_SUDO_ON_FAIL=1 && ((++SHIFT)) && shift; }
    [ "${1-}" != exec ] || { LK_EXEC=1 && ((++SHIFT)) && shift; }
    [ "${LK_EXEC:+e}${LK_SUDO_ON_FAIL:+f}" != ef ] ||
        lk_err "LK_EXEC and LK_SUDO_ON_FAIL are mutually exclusive" || return
    [ -z "$LK_SUDO_ON_FAIL" ] || [ $# -gt 0 ] ||
        lk_err "command required if LK_SUDO_ON_FAIL is set" || return
    declare -p LK_EXEC LK_SUDO_ON_FAIL
    ((!SHIFT)) || printf 'shift %s\n' "$SHIFT"
}

# lk_elevate [-f] [exec] [COMMAND [ARG...]]
#
# If Bash is running as root, run COMMAND, otherwise use `sudo` to run it as the
# root user. If COMMAND is not found in PATH and is a function, run it with
# LK_SUDO set. If no COMMAND is specified and Bash is not running as root, run
# the current script, with its original arguments, as the root user. If -f is
# set, attempt without `sudo` first and only run as root if the first attempt
# fails.
function lk_elevate() {
    local _SH _COMMAND _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    _SH=$(_lk_sudo_check "$@") && eval "$_SH" || return
    if [ "$EUID" -eq 0 ]; then
        [ $# -eq 0 ] ||
            ${LK_EXEC:+exec} "$@"
    elif [ $# -eq 0 ]; then
        ${LK_EXEC:+exec} sudo -H "$0" ${_LK_ARGV+"${_LK_ARGV[@]}"}
    elif ! _COMMAND=$(type -P "$1") && [ "$(type -t "$1")" = "function" ]; then
        LK_SUDO=
        if [ -n "$LK_SUDO_ON_FAIL" ] && "$@" 2>/dev/null; then
            return 0
        fi
        LK_SUDO=1
        "$@"
    elif [ -n "$_COMMAND" ]; then
        shift
        if [ -n "$LK_SUDO_ON_FAIL" ] && "$_COMMAND" "$@" 2>/dev/null; then
            return 0
        fi
        ${LK_EXEC:+exec} sudo -H "$_COMMAND" "$@"
    else
        lk_err "invalid command: $1"
        false
    fi
}

# lk_sudo [-f] [exec] COMMAND [ARG...]
#
# If Bash is running as root or LK_SUDO is empty or unset, run COMMAND,
# otherwise use `sudo` to run it as the root user. If -f is set and `sudo` will
# be used, attempt without `sudo` first and only run as root if the first
# attempt fails.
function lk_sudo() {
    local _SH _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    _SH=$(_lk_sudo_check "$@") && eval "$_SH" || return
    if [ -n "${LK_SUDO-}" ]; then
        lk_elevate "$@"
    else
        ${LK_EXEC:+exec} "$@"
    fi
}

# lk_will_elevate
#
# Return true if commands invoked with lk_sudo will run as the root user, even
# if sudo will not be used.
function lk_will_elevate() {
    [ "$EUID" -eq 0 ] || [ -n "${LK_SUDO-}" ]
}

# lk_will_sudo
#
# Return true if sudo will be used to run commands invoked with lk_sudo. Return
# false if Bash is already running with root privileges or LK_SUDO is not set.
function lk_will_sudo() {
    [ "$EUID" -ne 0 ] && [ -n "${LK_SUDO-}" ]
}

# lk_run_as USER COMMAND [ARG...]
function lk_run_as() {
    [ $# -ge 2 ] || lk_err "invalid arguments" || return
    local _USER
    _USER=$(id -u "$1" 2>/dev/null) || lk_err "user not found: $1" || return
    shift
    if [[ $EUID -eq $_USER ]]; then
        "$@"
    elif lk_is_linux; then
        _USER=$(id -un "$_USER")
        lk_elevate runuser -u "$_USER" -- "$@"
    else
        sudo -u "#$_USER" -- "$@"
    fi
}

# Define wrapper functions (e.g. `gnu_find`) to invoke the GNU version of
# certain commands (e.g. `gfind`) when standard utilities are not compatible
# with their GNU counterparts, e.g. on BSD/macOS
if ! lk_is_macos; then
    function gnu_awk() { lk_sudo gawk "$@"; }
    function gnu_chgrp() { lk_sudo chgrp "$@"; }
    function gnu_chmod() { lk_sudo chmod "$@"; }
    function gnu_chown() { lk_sudo chown "$@"; }
    function gnu_cp() { lk_sudo cp "$@"; }
    function gnu_date() { lk_sudo date "$@"; }
    function gnu_dd() { lk_sudo dd "$@"; }
    function gnu_df() { lk_sudo df "$@"; }
    function gnu_diff() { lk_sudo diff "$@"; }
    function gnu_du() { lk_sudo du "$@"; }
    function gnu_find() { lk_sudo find "$@"; }
    function gnu_getopt() { lk_sudo getopt "$@"; }
    function gnu_grep() { lk_sudo grep "$@"; }
    function gnu_ln() { lk_sudo ln "$@"; }
    function gnu_mktemp() { lk_sudo mktemp "$@"; }
    function gnu_mv() { lk_sudo mv "$@"; }
    function gnu_realpath() { lk_sudo realpath "$@"; }
    function gnu_sed() { lk_sudo sed "$@"; }
    function gnu_sort() { lk_sudo sort "$@"; }
    function gnu_stat() { lk_sudo stat "$@"; }
    function gnu_tar() { lk_sudo tar "$@"; }
    function gnu_uniq() { lk_sudo uniq "$@"; }
    function gnu_xargs() { lk_sudo xargs "$@"; }
else
    lk_is_apple_silicon &&
        _LK_HOMEBREW_PREFIX=/opt/homebrew ||
        _LK_HOMEBREW_PREFIX=/usr/local
    function gnu_awk() { lk_sudo gawk "$@"; }
    function gnu_chgrp() { lk_sudo gchgrp "$@"; }
    function gnu_chmod() { lk_sudo gchmod "$@"; }
    function gnu_chown() { lk_sudo gchown "$@"; }
    function gnu_cp() { lk_sudo gcp "$@"; }
    function gnu_date() { lk_sudo gdate "$@"; }
    function gnu_dd() { lk_sudo gdd "$@"; }
    function gnu_df() { lk_sudo gdf "$@"; }
    function gnu_diff() { lk_sudo "${HOMEBREW_PREFIX:-$_LK_HOMEBREW_PREFIX}/opt/diffutils/bin/diff" "$@"; }
    function gnu_du() { lk_sudo gdu "$@"; }
    function gnu_find() { lk_sudo gfind "$@"; }
    function gnu_getopt() { lk_sudo "${HOMEBREW_PREFIX:-$_LK_HOMEBREW_PREFIX}/opt/gnu-getopt/bin/getopt" "$@"; }
    function gnu_grep() { lk_sudo ggrep "$@"; }
    function gnu_ln() { lk_sudo gln "$@"; }
    function gnu_mktemp() { lk_sudo gmktemp "$@"; }
    function gnu_mv() { lk_sudo gmv "$@"; }
    function gnu_realpath() { lk_sudo grealpath "$@"; }
    function gnu_sed() { lk_sudo gsed "$@"; }
    function gnu_sort() { lk_sudo gsort "$@"; }
    function gnu_stat() { lk_sudo gstat "$@"; }
    function gnu_tar() { lk_sudo gtar "$@"; }
    function gnu_uniq() { lk_sudo guniq "$@"; }
    function gnu_xargs() { lk_sudo gxargs "$@"; }
fi

# lk_mapfile [-z] ARRAY [FILE]
#
# Read lines from FILE or input into ARRAY. If -z is set, input is
# NUL-delimited.
function lk_mapfile() {
    local _ARGS=()
    [ "${1-}" != -z ] || { _ARGS=(-d '') && shift; }
    [ -n "${2+1}" ] || set -- "$1" /dev/stdin
    [ -r "$2" ] || lk_err "not readable: $2" || return
    if lk_bash_at_least 4 4 ||
        { [ -z "${_ARGS+1}" ] && lk_bash_at_least 4 0; }; then
        mapfile -t ${_ARGS+"${_ARGS[@]}"} "$1" <"$2"
    else
        eval "$1=()" || return
        local _LINE
        while IFS= read -r ${_ARGS+"${_ARGS[@]}"} _LINE ||
            [ -n "${_LINE:+1}" ]; do
            eval "$1[\${#$1[@]}]=\$_LINE"
        done <"$2"
    fi
}

# lk_set_bashpid
#
# Unless Bash version is 4 or higher, set BASHPID to the process ID of the
# running (sub)shell.
function lk_set_bashpid() {
    lk_bash_at_least 4 ||
        BASHPID=$(exec sh -c 'echo "$PPID"')
}

# lk_sed_i SUFFIX SED_ARG...
#
# Run `sed` with the correct arguments to edit files in-place on the detected
# platform.
function lk_sed_i() {
    if ! lk_is_macos; then
        local IFS
        unset IFS
        lk_sudo sed -i"${1-}" "${@:2}"
    else
        lk_sudo sed -i "$@"
    fi
}

function _lk_realpath() {
    local FILE=$1 i=0 COMPONENT LN RESOLVED=
    lk_sudo test -e "$FILE" || return
    [ "${FILE:0:1}" = / ] || FILE=${PWD%/}/$FILE
    while [ -n "$FILE" ]; do
        ((i++)) || {
            # 1. Replace "/./" with "/"
            # 2. Replace subsequent "/"s with one "/"
            # 3. Remove trailing "/"
            FILE=$(sed -E 's#/\./#/#g; s#/+#/#g; s#/$##' <<<"$FILE") || return
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
        ! lk_sudo test -L "$RESOLVED" || {
            LN=$(lk_sudo readlink "$RESOLVED") || return
            [ "${LN:0:1}" = / ] || LN=${RESOLVED%/*}/$LN
            FILE=$LN${FILE:+/$FILE}
            RESOLVED=
            i=0
        }
    done
    echo "$RESOLVED"
}

# lk_realpath FILE...
#
# Print the resolved absolute path of each FILE.
function lk_realpath() {
    local STATUS=0
    if lk_command_exists realpath; then
        lk_sudo realpath "$@"
    else
        while [ $# -gt 0 ]; do
            _lk_realpath "$1" || STATUS=$?
            shift
        done
        return "$STATUS"
    fi
}

# lk_unbuffer [exec] COMMAND [ARG...]
#
# Run COMMAND with unbuffered input and line-buffered output (if supported by
# the command and platform).
function lk_unbuffer() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    local CMD=$1
    shift
    case "$CMD" in
    sed | gsed | gnu_sed)
        set -- "$CMD" -u "$@"
        ;;
    grep | ggrep | gnu_grep)
        set -- "$CMD" --line-buffered "$@"
        ;;
    *)
        if [ "$CMD" = tr ] && lk_is_macos; then
            set -- "$CMD" -u "$@"
        else
            # TODO: reinstate unbuffer after resolving LF -> CRLF issue
            case "$(lk_first_command stdbuf)" in
            stdbuf)
                set -- stdbuf -i0 -oL -eL "$CMD" "$@"
                ;;
            unbuffer)
                set -- unbuffer -p "$CMD" "$@"
                ;;
            esac
        fi
        ;;
    esac
    lk_sudo "$@"
}

# lk_grep_regex [-GREP_ARG] REGEX
function lk_grep_regex() {
    local ARG SH
    [[ ${1-} != -* ]] || { ARG=${1#-} && shift; }
    [ $# -eq 1 ] || lk_err "invalid arguments" || return 2
    SH=$(lk_get_regex "$1") && eval "$SH" || return 2
    grep -"${ARG-}E" "${!1}"
}

# lk_is_regex REGEX [VALUE...]
#
# Return true if every VALUE is a match for REGEX.
#
# Returns false if there are no values to check.
function lk_is_regex() {
    [ $# -gt 1 ] || return
    local REGEX=$1 SH
    SH=$(lk_get_regex "$1") && eval "$SH" || return 2
    while [ $# -gt 1 ]; do
        shift
        [[ $1 =~ ^${!REGEX}$ ]] || return
    done
}

# lk_is_cidr VALUE...
#
# Return true if every VALUE is a valid IP address or CIDR.
function lk_is_cidr() {
    lk_is_regex IP_OPT_PREFIX_REGEX "$@"
}

# lk_is_fqdn VALUE...
#
# Return true if every VALUE is a valid domain name.
function lk_is_fqdn() {
    lk_is_regex DOMAIN_NAME_REGEX "$@"
}

# lk_is_tld VALUE...
#
# Return true if every VALUE is a valid top-level domain.
function lk_is_tld() {
    lk_is_regex TOP_LEVEL_DOMAIN_REGEX "$@"
}

# lk_is_email VALUE...
#
# Return true if every VALUE is a valid email address.
function lk_is_email() {
    lk_is_regex EMAIL_ADDRESS_REGEX "$@"
}

# lk_is_uri VALUE...
#
# Return true if every VALUE is a valid URI with a scheme and host.
function lk_is_uri() {
    lk_is_regex URI_REGEX_REQ_SCHEME_HOST "$@"
}

# lk_is_identifier VALUE...
#
# Return true if every VALUE is a valid Bash identifier.
function lk_is_identifier() {
    lk_is_regex IDENTIFIER_REGEX "$@"
}

# lk_filter_ipv4 [-v]
#
# Print each input line that is a valid dotted-decimal IPv4 address or CIDR. If
# -v is set, print each line that is not valid.
function lk_filter_ipv4() {
    _LK_STACK_DEPTH=1 lk_grep_regex "-x${1:+${1#-}}" IPV4_OPT_PREFIX_REGEX || true
}

# lk_filter_ipv6 [-v]
#
# Print each input line that is a valid 8-hextet IPv6 address or CIDR. If -v is
# set, print each line that is not valid.
function lk_filter_ipv6() {
    _LK_STACK_DEPTH=1 lk_grep_regex "-x${1:+${1#-}}" IPV6_OPT_PREFIX_REGEX || true
}

# lk_filter_cidr [-v]
#
# Print each input line that is a valid IP address or CIDR. If -v is set, print
# each line that is not valid.
function lk_filter_cidr() {
    _LK_STACK_DEPTH=1 lk_grep_regex "-x${1:+${1#-}}" IP_OPT_PREFIX_REGEX || true
}

# lk_filter_fqdn [-v]
#
# Print each input line that is a valid domain name. If -v is set, print each
# line that is not valid.
function lk_filter_fqdn() {
    _LK_STACK_DEPTH=1 lk_grep_regex "-x${1:+${1#-}}" DOMAIN_NAME_REGEX || true
}

# lk_get_regex [REGEX...]
#
# Print a Bash variable assignment for each REGEX. If no REGEX is specified,
# print all available regular expressions.
function lk_get_regex() {
    [ $# -gt 0 ] || set -- DOMAIN_PART_REGEX DOMAIN_NAME_REGEX EMAIL_ADDRESS_REGEX DOMAIN_PART_LOWER_REGEX DOMAIN_NAME_LOWER_REGEX TOP_LEVEL_DOMAIN_REGEX IPV4_REGEX IPV4_OPT_PREFIX_REGEX IPV6_REGEX IPV6_OPT_PREFIX_REGEX IP_REGEX IP_OPT_PREFIX_REGEX HOST_NAME_REGEX HOST_REGEX HOST_OPT_PREFIX_REGEX URI_REGEX URI_REGEX_REQ_SCHEME_HOST HTTP_HEADER_NAME LINUX_USERNAME_REGEX MYSQL_USERNAME_REGEX DPKG_SOURCE_REGEX IDENTIFIER_REGEX PHP_SETTING_NAME_REGEX PHP_SETTING_REGEX READLINE_NON_PRINTING_REGEX CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX NON_PRINTING_REGEX IPV4_PRIVATE_FILTER_REGEX IPV6_PRIVATE_FILTER_REGEX IP_PRIVATE_FILTER_REGEX BACKUP_TIMESTAMP_FINDUTILS_REGEX
    local STATUS=0
    while [ $# -gt 0 ]; do
        printf 'declare '
        case "$1" in
        DOMAIN_PART_REGEX)
            printf '%s=%q\n' DOMAIN_PART_REGEX '[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?'
            ;;
        DOMAIN_NAME_REGEX)
            printf '%s=%q\n' DOMAIN_NAME_REGEX '[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)+'
            ;;
        EMAIL_ADDRESS_REGEX)
            printf '%s=%q\n' EMAIL_ADDRESS_REGEX '[-a-zA-Z0-9!#$%&'\''*+/=?^_`{|}~]([-a-zA-Z0-9.!#$%&'\''*+/=?^_`{|}~]{,62}[-a-zA-Z0-9!#$%&'\''*+/=?^_`{|}~])?@[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)+'
            ;;
        DOMAIN_PART_LOWER_REGEX)
            printf '%s=%q\n' DOMAIN_PART_LOWER_REGEX '[a-z0-9]([-a-z0-9]*[a-z0-9])?'
            ;;
        DOMAIN_NAME_LOWER_REGEX)
            printf '%s=%q\n' DOMAIN_NAME_LOWER_REGEX '[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+'
            ;;
        TOP_LEVEL_DOMAIN_REGEX)
            printf '%s=%q\n' TOP_LEVEL_DOMAIN_REGEX '(aaa|aarp|abarth|abb|abbott|abbvie|abc|able|abogado|abudhabi|ac|academy|accenture|accountant|accountants|aco|actor|ad|adac|ads|adult|ae|aeg|aero|aetna|af|afl|africa|ag|agakhan|agency|ai|aig|airbus|airforce|airtel|akdn|al|alfaromeo|alibaba|alipay|allfinanz|allstate|ally|alsace|alstom|am|amazon|americanexpress|americanfamily|amex|amfam|amica|amsterdam|analytics|android|anquan|anz|ao|aol|apartments|app|apple|aq|aquarelle|ar|arab|aramco|archi|army|arpa|art|arte|as|asda|asia|associates|at|athleta|attorney|au|auction|audi|audible|audio|auspost|author|auto|autos|avianca|aw|aws|ax|axa|az|azure|ba|baby|baidu|banamex|bananarepublic|band|bank|bar|barcelona|barclaycard|barclays|barefoot|bargains|baseball|basketball|bauhaus|bayern|bb|bbc|bbt|bbva|bcg|bcn|bd|be|beats|beauty|beer|bentley|berlin|best|bestbuy|bet|bf|bg|bh|bharti|bi|bible|bid|bike|bing|bingo|bio|biz|bj|black|blackfriday|blockbuster|blog|bloomberg|blue|bm|bms|bmw|bn|bnpparibas|bo|boats|boehringer|bofa|bom|bond|boo|book|booking|bosch|bostik|boston|bot|boutique|box|br|bradesco|bridgestone|broadway|broker|brother|brussels|bs|bt|budapest|bugatti|build|builders|business|buy|buzz|bv|bw|by|bz|bzh|ca|cab|cafe|cal|call|calvinklein|cam|camera|camp|cancerresearch|canon|capetown|capital|capitalone|car|caravan|cards|care|career|careers|cars|casa|case|cash|casino|cat|catering|catholic|cba|cbn|cbre|cbs|cc|cd|center|ceo|cern|cf|cfa|cfd|cg|ch|chanel|channel|charity|chase|chat|cheap|chintai|christmas|chrome|church|ci|cipriani|circle|cisco|citadel|citi|citic|city|cityeats|ck|cl|claims|cleaning|click|clinic|clinique|clothing|cloud|club|clubmed|cm|cn|co|coach|codes|coffee|college|cologne|com|comcast|commbank|community|company|compare|computer|comsec|condos|construction|consulting|contact|contractors|cooking|cookingchannel|cool|coop|corsica|country|coupon|coupons|courses|cpa|cr|credit|creditcard|creditunion|cricket|crown|crs|cruise|cruises|cu|cuisinella|cv|cw|cx|cy|cymru|cyou|cz|dabur|dad|dance|data|date|dating|datsun|day|dclk|dds|de|deal|dealer|deals|degree|delivery|dell|deloitte|delta|democrat|dental|dentist|desi|design|dev|dhl|diamonds|diet|digital|direct|directory|discount|discover|dish|diy|dj|dk|dm|dnp|do|docs|doctor|dog|domains|dot|download|drive|dtv|dubai|dunlop|dupont|durban|dvag|dvr|dz|earth|eat|ec|eco|edeka|edu|education|ee|eg|email|emerck|energy|engineer|engineering|enterprises|epson|equipment|er|ericsson|erni|es|esq|estate|et|etisalat|eu|eurovision|eus|events|exchange|expert|exposed|express|extraspace|fage|fail|fairwinds|faith|family|fan|fans|farm|farmers|fashion|fast|fedex|feedback|ferrari|ferrero|fi|fiat|fidelity|fido|film|final|finance|financial|fire|firestone|firmdale|fish|fishing|fit|fitness|fj|fk|flickr|flights|flir|florist|flowers|fly|fm|fo|foo|food|foodnetwork|football|ford|forex|forsale|forum|foundation|fox|fr|free|fresenius|frl|frogans|frontdoor|frontier|ftr|fujitsu|fun|fund|furniture|futbol|fyi|ga|gal|gallery|gallo|gallup|game|games|gap|garden|gay|gb|gbiz|gd|gdn|ge|gea|gent|genting|george|gf|gg|ggee|gh|gi|gift|gifts|gives|giving|gl|glass|gle|global|globo|gm|gmail|gmbh|gmo|gmx|gn|godaddy|gold|goldpoint|golf|goo|goodyear|goog|google|gop|got|gov|gp|gq|gr|grainger|graphics|gratis|green|gripe|grocery|group|gs|gt|gu|guardian|gucci|guge|guide|guitars|guru|gw|gy|hair|hamburg|hangout|haus|hbo|hdfc|hdfcbank|health|healthcare|help|helsinki|here|hermes|hgtv|hiphop|hisamitsu|hitachi|hiv|hk|hkt|hm|hn|hockey|holdings|holiday|homedepot|homegoods|homes|homesense|honda|horse|hospital|host|hosting|hot|hoteles|hotels|hotmail|house|how|hr|hsbc|ht|hu|hughes|hyatt|hyundai|ibm|icbc|ice|icu|id|ie|ieee|ifm|ikano|il|im|imamat|imdb|immo|immobilien|in|inc|industries|infiniti|info|ing|ink|institute|insurance|insure|int|international|intuit|investments|io|ipiranga|iq|ir|irish|is|ismaili|ist|istanbul|it|itau|itv|jaguar|java|jcb|je|jeep|jetzt|jewelry|jio|jll|jm|jmp|jnj|jo|jobs|joburg|jot|joy|jp|jpmorgan|jprs|juegos|juniper|kaufen|kddi|ke|kerryhotels|kerrylogistics|kerryproperties|kfh|kg|kh|ki|kia|kim|kinder|kindle|kitchen|kiwi|km|kn|koeln|komatsu|kosher|kp|kpmg|kpn|kr|krd|kred|kuokgroup|kw|ky|kyoto|kz|la|lacaixa|lamborghini|lamer|lancaster|lancia|land|landrover|lanxess|lasalle|lat|latino|latrobe|law|lawyer|lb|lc|lds|lease|leclerc|lefrak|legal|lego|lexus|lgbt|li|lidl|life|lifeinsurance|lifestyle|lighting|like|lilly|limited|limo|lincoln|linde|link|lipsy|live|living|lk|llc|llp|loan|loans|locker|locus|loft|lol|london|lotte|lotto|love|lpl|lplfinancial|lr|ls|lt|ltd|ltda|lu|lundbeck|luxe|luxury|lv|ly|ma|macys|madrid|maif|maison|makeup|man|management|mango|map|market|marketing|markets|marriott|marshalls|maserati|mattel|mba|mc|mckinsey|md|me|med|media|meet|melbourne|meme|memorial|men|menu|merckmsd|mg|mh|miami|microsoft|mil|mini|mint|mit|mitsubishi|mk|ml|mlb|mls|mm|mma|mn|mo|mobi|mobile|moda|moe|moi|mom|monash|money|monster|mormon|mortgage|moscow|moto|motorcycles|mov|movie|mp|mq|mr|ms|msd|mt|mtn|mtr|mu|museum|music|mutual|mv|mw|mx|my|mz|na|nab|nagoya|name|natura|navy|nba|nc|ne|nec|net|netbank|netflix|network|neustar|new|news|next|nextdirect|nexus|nf|nfl|ng|ngo|nhk|ni|nico|nike|nikon|ninja|nissan|nissay|nl|no|nokia|northwesternmutual|norton|now|nowruz|nowtv|np|nr|nra|nrw|ntt|nu|nyc|nz|obi|observer|office|okinawa|olayan|olayangroup|oldnavy|ollo|om|omega|one|ong|onl|online|ooo|open|oracle|orange|org|organic|origins|osaka|otsuka|ott|ovh|pa|page|panasonic|paris|pars|partners|parts|party|passagens|pay|pccw|pe|pet|pf|pfizer|pg|ph|pharmacy|phd|philips|phone|photo|photography|photos|physio|pics|pictet|pictures|pid|pin|ping|pink|pioneer|pizza|pk|pl|place|play|playstation|plumbing|plus|pm|pn|pnc|pohl|poker|politie|porn|post|pr|pramerica|praxi|press|prime|pro|prod|productions|prof|progressive|promo|properties|property|protection|pru|prudential|ps|pt|pub|pw|pwc|py|qa|qpon|quebec|quest|racing|radio|re|read|realestate|realtor|realty|recipes|red|redstone|redumbrella|rehab|reise|reisen|reit|reliance|ren|rent|rentals|repair|report|republican|rest|restaurant|review|reviews|rexroth|rich|richardli|ricoh|ril|rio|rip|ro|rocher|rocks|rodeo|rogers|room|rs|rsvp|ru|rugby|ruhr|run|rw|rwe|ryukyu|sa|saarland|safe|safety|sakura|sale|salon|samsclub|samsung|sandvik|sandvikcoromant|sanofi|sap|sarl|sas|save|saxo|sb|sbi|sbs|sc|sca|scb|schaeffler|schmidt|scholarships|school|schule|schwarz|science|scot|sd|se|search|seat|secure|security|seek|select|sener|services|ses|seven|sew|sex|sexy|sfr|sg|sh|shangrila|sharp|shaw|shell|shia|shiksha|shoes|shop|shopping|shouji|show|showtime|si|silk|sina|singles|site|sj|sk|ski|skin|sky|skype|sl|sling|sm|smart|smile|sn|sncf|so|soccer|social|softbank|software|sohu|solar|solutions|song|sony|soy|spa|space|sport|spot|sr|srl|ss|st|stada|staples|star|statebank|statefarm|stc|stcgroup|stockholm|storage|store|stream|studio|study|style|su|sucks|supplies|supply|support|surf|surgery|suzuki|sv|swatch|swiss|sx|sy|sydney|systems|sz|tab|taipei|talk|taobao|target|tatamotors|tatar|tattoo|tax|taxi|tc|tci|td|tdk|team|tech|technology|tel|temasek|tennis|teva|tf|tg|th|thd|theater|theatre|tiaa|tickets|tienda|tiffany|tips|tires|tirol|tj|tjmaxx|tjx|tk|tkmaxx|tl|tm|tmall|tn|to|today|tokyo|tools|top|toray|toshiba|total|tours|town|toyota|toys|tr|trade|trading|training|travel|travelchannel|travelers|travelersinsurance|trust|trv|tt|tube|tui|tunes|tushu|tv|tvs|tw|tz|ua|ubank|ubs|ug|uk|unicom|university|uno|uol|ups|us|uy|uz|va|vacations|vana|vanguard|vc|ve|vegas|ventures|verisign|versicherung|vet|vg|vi|viajes|video|vig|viking|villas|vin|vip|virgin|visa|vision|viva|vivo|vlaanderen|vn|vodka|volkswagen|volvo|vote|voting|voto|voyage|vu|vuelos|wales|walmart|walter|wang|wanggou|watch|watches|weather|weatherchannel|webcam|weber|website|wed|wedding|weibo|weir|wf|whoswho|wien|wiki|williamhill|win|windows|wine|winners|wme|wolterskluwer|woodside|work|works|world|wow|ws|wtc|wtf|xbox|xerox|xfinity|xihuan|xin|xn--11b4c3d|xn--1ck2e1b|xn--1qqw23a|xn--2scrj9c|xn--30rr7y|xn--3bst00m|xn--3ds443g|xn--3e0b707e|xn--3hcrj9c|xn--3pxu8k|xn--42c2d9a|xn--45br5cyl|xn--45brj9c|xn--45q11c|xn--4dbrk0ce|xn--4gbrim|xn--54b7fta0cc|xn--55qw42g|xn--55qx5d|xn--5su34j936bgsg|xn--5tzm5g|xn--6frz82g|xn--6qq986b3xl|xn--80adxhks|xn--80ao21a|xn--80aqecdr1a|xn--80asehdb|xn--80aswg|xn--8y0a063a|xn--90a3ac|xn--90ae|xn--90ais|xn--9dbq2a|xn--9et52u|xn--9krt00a|xn--b4w605ferd|xn--bck1b9a5dre4c|xn--c1avg|xn--c2br7g|xn--cck2b3b|xn--cckwcxetd|xn--cg4bki|xn--clchc0ea0b2g2a9gcd|xn--czr694b|xn--czrs0t|xn--czru2d|xn--d1acj3b|xn--d1alf|xn--e1a4c|xn--eckvdtc9d|xn--efvy88h|xn--fct429k|xn--fhbei|xn--fiq228c5hs|xn--fiq64b|xn--fiqs8s|xn--fiqz9s|xn--fjq720a|xn--flw351e|xn--fpcrj9c3d|xn--fzc2c9e2c|xn--fzys8d69uvgm|xn--g2xx48c|xn--gckr3f0f|xn--gecrj9c|xn--gk3at1e|xn--h2breg3eve|xn--h2brj9c|xn--h2brj9c8c|xn--hxt814e|xn--i1b6b1a6a2e|xn--imr513n|xn--io0a7i|xn--j1aef|xn--j1amh|xn--j6w193g|xn--jlq480n2rg|xn--jlq61u9w7b|xn--jvr189m|xn--kcrx77d1x4a|xn--kprw13d|xn--kpry57d|xn--kput3i|xn--l1acc|xn--lgbbat1ad8j|xn--mgb9awbf|xn--mgba3a3ejt|xn--mgba3a4f16a|xn--mgba7c0bbn0a|xn--mgbaakc7dvf|xn--mgbaam7a8h|xn--mgbab2bd|xn--mgbah1a3hjkrd|xn--mgbai9azgqp6j|xn--mgbayh7gpa|xn--mgbbh1a|xn--mgbbh1a71e|xn--mgbc0a9azcg|xn--mgbca7dzdo|xn--mgbcpq6gpa1a|xn--mgberp4a5d4ar|xn--mgbgu82a|xn--mgbi4ecexp|xn--mgbpl2fh|xn--mgbt3dhd|xn--mgbtx2b|xn--mgbx4cd0ab|xn--mix891f|xn--mk1bu44c|xn--mxtq1m|xn--ngbc5azd|xn--ngbe9e0a|xn--ngbrx|xn--node|xn--nqv7f|xn--nqv7fs00ema|xn--nyqy26a|xn--o3cw4h|xn--ogbpf8fl|xn--otu796d|xn--p1acf|xn--p1ai|xn--pgbs0dh|xn--pssy2u|xn--q7ce6a|xn--q9jyb4c|xn--qcka1pmc|xn--qxa6a|xn--qxam|xn--rhqv96g|xn--rovu88b|xn--rvc1e0am3e|xn--s9brj9c|xn--ses554g|xn--t60b56a|xn--tckwe|xn--tiq49xqyj|xn--unup4y|xn--vermgensberater-ctb|xn--vermgensberatung-pwb|xn--vhquv|xn--vuq861b|xn--w4r85el8fhu5dnra|xn--w4rs40l|xn--wgbh1c|xn--wgbl6a|xn--xhq521b|xn--xkc2al3hye2a|xn--xkc2dl3a5ee0h|xn--y9a3aq|xn--yfro4i67o|xn--ygbi2ammx|xn--zfr164b|xxx|xyz|yachts|yahoo|yamaxun|yandex|ye|yodobashi|yoga|yokohama|you|youtube|yt|yun|za|zappos|zara|zero|zip|zm|zone|zuerich|zw)'
            ;;
        IPV4_REGEX)
            printf '%s=%q\n' IPV4_REGEX '((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])'
            ;;
        IPV4_OPT_PREFIX_REGEX)
            printf '%s=%q\n' IPV4_OPT_PREFIX_REGEX '((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])(/(3[0-2]|[12][0-9]|[1-9]))?'
            ;;
        IPV6_REGEX)
            printf '%s=%q\n' IPV6_REGEX '(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7}))'
            ;;
        IPV6_OPT_PREFIX_REGEX)
            printf '%s=%q\n' IPV6_OPT_PREFIX_REGEX '(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7}))(/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9]))?'
            ;;
        IP_REGEX)
            printf '%s=%q\n' IP_REGEX '(((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])|(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7})))'
            ;;
        IP_OPT_PREFIX_REGEX)
            printf '%s=%q\n' IP_OPT_PREFIX_REGEX '(((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])(/(3[0-2]|[12][0-9]|[1-9]))?|(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7}))(/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9]))?)'
            ;;
        HOST_NAME_REGEX)
            printf '%s=%q\n' HOST_NAME_REGEX '([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)*)'
            ;;
        HOST_REGEX)
            printf '%s=%q\n' HOST_REGEX '(((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])|(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7}))|([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)*))'
            ;;
        HOST_OPT_PREFIX_REGEX)
            printf '%s=%q\n' HOST_OPT_PREFIX_REGEX '(((25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|(1[0-9]|[1-9])?[0-9])(/(3[0-2]|[12][0-9]|[1-9]))?|(([0-9a-fA-F]{1,4}:){7}(:|[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){6}(:|:[0-9a-fA-F]{1,4})|([0-9a-fA-F]{1,4}:){5}(:|(:[0-9a-fA-F]{1,4}){1,2})|([0-9a-fA-F]{1,4}:){4}(:|(:[0-9a-fA-F]{1,4}){1,3})|([0-9a-fA-F]{1,4}:){3}(:|(:[0-9a-fA-F]{1,4}){1,4})|([0-9a-fA-F]{1,4}:){2}(:|(:[0-9a-fA-F]{1,4}){1,5})|[0-9a-fA-F]{1,4}:(:|(:[0-9a-fA-F]{1,4}){1,6})|:(:|(:[0-9a-fA-F]{1,4}){1,7}))(/(12[0-8]|1[01][0-9]|[1-9][0-9]|[1-9]))?|([a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)*))'
            ;;
        URI_REGEX)
            printf '%s=%q\n' URI_REGEX '(([a-zA-Z][-a-zA-Z0-9+.]*):)?(//(([-a-zA-Z0-9._~%!$&'\''()*+,;=]+)(:([-a-zA-Z0-9._~%!$&'\''()*+,;=]*))?@)?([-a-zA-Z0-9._~%!$&'\''()*+,;=]+|\[([0-9a-fA-F:]+)\])(:([0-9]+))?)?([-a-zA-Z0-9._~%!$&'\''()*+,;=:@/]+)?(\?([-a-zA-Z0-9._~%!$&'\''()*+,;=:@?/]+))?(#([-a-zA-Z0-9._~%!$&'\''()*+,;=:@?/]*))?'
            ;;
        URI_REGEX_REQ_SCHEME_HOST)
            printf '%s=%q\n' URI_REGEX_REQ_SCHEME_HOST '(([a-zA-Z][-a-zA-Z0-9+.]*):)(//(([-a-zA-Z0-9._~%!$&'\''()*+,;=]+)(:([-a-zA-Z0-9._~%!$&'\''()*+,;=]*))?@)?([-a-zA-Z0-9._~%!$&'\''()*+,;=]+|\[([0-9a-fA-F:]+)\])(:([0-9]+))?)([-a-zA-Z0-9._~%!$&'\''()*+,;=:@/]+)?(\?([-a-zA-Z0-9._~%!$&'\''()*+,;=:@?/]+))?(#([-a-zA-Z0-9._~%!$&'\''()*+,;=:@?/]*))?'
            ;;
        HTTP_HEADER_NAME)
            printf '%s=%q\n' HTTP_HEADER_NAME '[-a-zA-Z0-9!#$%&'\''*+.^_`|~]+'
            ;;
        LINUX_USERNAME_REGEX)
            printf '%s=%q\n' LINUX_USERNAME_REGEX '[a-z_]([-a-z0-9_]{0,31}|[-a-z0-9_]{0,30}\$)'
            ;;
        MYSQL_USERNAME_REGEX)
            printf '%s=%q\n' MYSQL_USERNAME_REGEX '[a-zA-Z0-9_]+'
            ;;
        DPKG_SOURCE_REGEX)
            printf '%s=%q\n' DPKG_SOURCE_REGEX '[a-z0-9][-a-z0-9+.]+'
            ;;
        IDENTIFIER_REGEX)
            printf '%s=%q\n' IDENTIFIER_REGEX '[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        PHP_SETTING_NAME_REGEX)
            printf '%s=%q\n' PHP_SETTING_NAME_REGEX '[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*'
            ;;
        PHP_SETTING_REGEX)
            printf '%s=%q\n' PHP_SETTING_REGEX '[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*=.*'
            ;;
        READLINE_NON_PRINTING_REGEX)
            printf '%s=%q\n' READLINE_NON_PRINTING_REGEX $'\001[^\002]*\002'
            ;;
        CONTROL_SEQUENCE_REGEX)
            printf '%s=%q\n' CONTROL_SEQUENCE_REGEX $'\E\\[[0-?]*[ -/]*[@-~]'
            ;;
        ESCAPE_SEQUENCE_REGEX)
            printf '%s=%q\n' ESCAPE_SEQUENCE_REGEX $'\E[ -/]*[0-~]'
            ;;
        NON_PRINTING_REGEX)
            printf '%s=%q\n' NON_PRINTING_REGEX $'(\001[^\002]*\002|\E(\\[[0-?]*[ -/]*[@-~]|[ -/]*[0-Z\\\\-~]))'
            ;;
        IPV4_PRIVATE_FILTER_REGEX)
            printf '%s=%q\n' IPV4_PRIVATE_FILTER_REGEX '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)'
            ;;
        IPV6_PRIVATE_FILTER_REGEX)
            printf '%s=%q\n' IPV6_PRIVATE_FILTER_REGEX '^([fF][cdCD]|[fF][eE]80::|::1(/128|$))'
            ;;
        IP_PRIVATE_FILTER_REGEX)
            printf '%s=%q\n' IP_PRIVATE_FILTER_REGEX '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|[fF][cdCD]|[fF][eE]80::|::1(/128|$))'
            ;;
        BACKUP_TIMESTAMP_FINDUTILS_REGEX)
            printf '%s=%q\n' BACKUP_TIMESTAMP_FINDUTILS_REGEX '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'
            ;;
        *)
            lk_err "regex not found: $1"
            STATUS=1
            ;;
        esac
        shift
    done
    return "$STATUS"
}

# lk_date FORMAT [TIMESTAMP]
function lk_date() {
    # Take advantage of printf support for strftime in Bash 4.2+
    if lk_bash_at_least 4 2; then
        function lk_date() {
            printf "%($1)T\n" "${2:--1}"
        }
    elif ! lk_is_macos; then
        function lk_date() {
            if [ $# -lt 2 ]; then
                date "+$1"
            else
                date -d "@$2" "+$1"
            fi
        }
    else
        function lk_date() {
            if [ $# -lt 2 ]; then
                date "+$1"
            else
                date -jf '%s' "$2" "+$1"
            fi
        }
    fi
    lk_date "$@"
}

# lk_date_log [TIMESTAMP]
function lk_date_log() { lk_date "%Y-%m-%d %H:%M:%S %z" "$@"; }

# lk_date_ymdhms [TIMESTAMP]
function lk_date_ymdhms() { lk_date "%Y%m%d%H%M%S" "$@"; }

# lk_date_ymd [TIMESTAMP]
function lk_date_ymd() { lk_date "%Y%m%d" "$@"; }

# lk_date_http [TIMESTAMP]
function lk_date_http() { TZ=UTC lk_date "%a, %d %b %Y %H:%M:%S %Z" "$@"; }

# lk_timestamp
function lk_timestamp() { lk_date "%s"; }

# _lk_stream_args COMMAND_ARGS COMMAND... [ARG...]
function _lk_stream_args() {
    local IFS
    unset IFS
    if (($# > $1 + 1)); then
        printf '%s\n' "${@:$1+2}" | "${@:2:$1}"
    else
        [ "$(type -t "$2")" = file ] || local LK_EXEC
        ${LK_EXEC:+exec} "${@:2:$1}"
    fi
}

# lk_uniq [STRING...]
function lk_uniq() {
    _lk_stream_args 2 awk '!seen[$0]++ { print }' "$@"
}

# lk_double_quote [-f] [STRING...]
#
# If -f is set, add double quotes even if STRING only contains letters, numbers
# and safe punctuation (i.e. + - . / @ _).
function lk_double_quote() {
    local FORCE
    unset FORCE
    [ "${1-}" != -f ] || { FORCE= && shift; }
    _lk_stream_args 3 sed -E \
        ${FORCE-$'/^[a-zA-Z0-9+./@_-]*$/b\n'}'s/["$\`]/\\&/g; s/.*/"&"/' "$@"
}

# lk_quote_args [ARG...]
#
# Use `printf %q` to print the arguments on a space-delimited line.
function lk_quote_args() {
    [ $# -eq 0 ] || { printf '%q' "$1" && shift; }
    [ $# -eq 0 ] || printf ' %q' "$@"
    printf '\n'
}

# lk_fold_quote_args [ARG...]
#
# Same as lk_quote_args, but print each argument on a new line.
function lk_fold_quote_args() {
    [ $# -eq 0 ] || { printf '%q' "$1" && shift; }
    [ $# -eq 0 ] || printf ' \\\n    %q' "$@"
    printf '\n'
}

# lk_implode_args GLUE [ARG...]
function lk_implode_args() {
    local IFS GLUE=${1//\\/\\\\}
    unset IFS
    GLUE=${GLUE//%/%%}
    [ $# -eq 1 ] || printf '%s' "$2"
    [ $# -le 2 ] || printf -- "$GLUE%s" "${@:3}"
    printf '\n'
}

# lk_implode_input GLUE
function lk_implode_input() {
    [ -z "${_LK_INPUT_DELIM+1}" ] ||
        local _LK_INPUT_DELIM=${_LK_INPUT_DELIM:-\\0}
    awk -v "OFS=$1" \
        -v "RS=${_LK_INPUT_DELIM-\\n}" \
        'NR > 1 { printf "%s", OFS } { printf "%s", $0 }'
}

function lk_ere_escape() {
    _lk_stream_args 3 sed -E 's/[]$()*+.?\^{|}[]/\\&/g' "$@"
}

# lk_ere_implode_input [-e]
#
# If -e is set, escape each input line.
function lk_ere_implode_input() {
    if [ "${1-}" != -e ]; then
        awk '
NR == 1 { first = $0; next }
NR == 2 { printf "(%s", first }
        { printf "|%s", $0 }
END     { if (NR > 1) { print ")" } else if (NR) { printf "%s\n", first } }'
    else
        lk_ere_escape | lk_ere_implode_input
    fi
}

# lk_ere_implode_args [-e] [--] [ARG...]
function lk_ere_implode_args() {
    local ARGS
    [ "${1-}" != -e ] || { ARGS=(-e) && shift; }
    [ "${1-}" != -- ] || shift
    [ $# -eq 0 ] ||
        printf '%s\n' "$@" | lk_ere_implode_input ${ARGS+"${ARGS[@]}"}
}

function lk_sed_escape() {
    _lk_stream_args 3 sed -E 's/[]$()*+./?\^{|}[]/\\&/g' "$@"
}

function lk_sed_escape_replace() {
    _lk_stream_args 3 sed -E 's/[&/\]/\\&/g' "$@"
}

function lk_strip_cr() {
    LC_ALL=C _lk_stream_args 3 sed -E $'s/.*\r(.)/\\1/' "$@"
}

# lk_strip_non_printing [-d DELETE] [STRING...]
#
# Remove escape sequences and non-printing characters from each STRING or input
# line, including carriage returns that aren't part of a CRLF line ending and
# any characters appearing before them on the same line. Use -d to specify
# additional characters to remove (DELETE is passed directly to `tr -d`).
function lk_strip_non_printing() {
    local DELETE
    [ "${1-}" != -d ] || { DELETE=$2 && shift 2; }
    eval "$(lk_get_regex NON_PRINTING_REGEX)"
    LC_ALL=C _lk_stream_args 3 \
        sed -Eu "s/$NON_PRINTING_REGEX//g; "$'s/.*\r(.)/\\1/' "$@" |
        lk_unbuffer tr -d '\0-\10\16-\37\177'"${DELETE-}"
}

# lk_string_sort [[SORT_ARGS] STRING]
function lk_string_sort() {
    local IFS=${IFS:- } ARGS
    [ $# -le 1 ] || { ARGS=$1 && shift; }
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" '\0' |
        sort -z ${ARGS:+"$ARGS"} | tr '\0' "${IFS::1}" |
        awk -v "RS=${IFS::1}" '
NR == 1 {next}
        {printf "%s%s", (i++ ? RS : ""), $0}
END     {printf "\n"}'
}

# lk_string_remove [STRING [REMOVE...]]
function lk_string_remove() {
    local IFS=${IFS:- } REGEX
    REGEX=$(unset IFS && [ $# -le 1 ] ||
        printf '%s\n' "${@:2}" | lk_ere_implode_input -e)
    printf '%s' "${IFS::1}$1${IFS::1}" | tr -s "$IFS" "${IFS::1}" |
        awk -v "RS=${IFS::1}" -v "regex=^${REGEX//\\/\\\\}\$" '
NR == 1     {next}
$0 !~ regex {printf "%s%s", (i++ ? RS : ""), $0}
END         {printf "\n"}'
}

# lk_arr [-COMMAND] [ARRAY...]
function lk_arr() {
    local _CMD="printf '%s\n'" _sh _SH=
    [[ ${1-} != -* ]] || { _CMD=${1#-} && shift; }
    while [ $# -gt 0 ]; do
        _sh=" \"\${$1[@]}\""
        _SH+=${!1+$_sh}
        shift
    done
    # Print nothing if no array members were found
    [ -z "${_SH:+1}" ] || eval "$_CMD$_SH"
}

# lk_in_array VALUE ARRAY...
function lk_in_array() {
    local IFS=$' \t\n'
    lk_arr "${@:2}" | grep -Fx -- "$1" >/dev/null
}

# lk_quote_arr [ARRAY...]
function lk_quote_arr() {
    lk_arr -lk_quote_args "$@"
}

# lk_implode_arr GLUE [ARRAY...]
function lk_implode_arr() {
    local GLUE=$1
    shift
    lk_arr -"printf '%s\0'" "$@" | _LK_INPUT_DELIM= lk_implode_input "$GLUE"
}

# lk_ere_implode_arr [-e] [ARRAY...]
function lk_ere_implode_arr() {
    local ARGS
    [ "${1-}" != -e ] || { ARGS=(-e) && shift; }
    lk_arr "$@" | lk_ere_implode_input ${ARGS+"${ARGS[@]}"}
}

# lk_arr_remove ARRAY VALUE
function lk_arr_remove() {
    local _SH
    _SH=$(eval "for _i in \${$1+\"\${!$1[@]}\"}; do
    [ \"\${$1[_i]}\" != \"\$2\" ] || echo \"unset \\\"$1[\$_i]\\\"\"
done") && eval "$_SH"
}

function _lk_caller() {
    local CALLER
    CALLER=("$(lk_script_name 2)")
    CALLER[0]=$LK_BOLD$CALLER$LK_RESET
    lk_verbose || {
        echo "$CALLER"
        return
    }
    local REGEX='^([0-9]*) [^ ]* (.*)$' SOURCE LINE
    if [[ ${1-} =~ $REGEX ]]; then
        SOURCE=${BASH_REMATCH[2]}
        LINE=${BASH_REMATCH[1]}
    else
        SOURCE=${BASH_SOURCE[2]-}
        LINE=${BASH_LINENO[3]-}
    fi
    [ -z "$SOURCE" ] || [ "$SOURCE" = main ] || [ "$SOURCE" = "$0" ] ||
        CALLER+=("$(lk_tty_path "$SOURCE")")
    [ -z "$LINE" ] || [ "$LINE" -eq 1 ] ||
        CALLER[${#CALLER[@]} - 1]+=$LK_DIM:$LINE$LK_UNDIM
    lk_implode_arr "$LK_DIM->$LK_UNDIM" CALLER
}

# lk_warn [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as a warning and return the most recent exit status.
function lk_warn() {
    lk_pass -$? \
        lk_tty_warning "$(LK_VERBOSE= _lk_caller): ${1-command failed}"
}

# lk_die [MESSAGE]
#
# Print "<CALLER>: MESSAGE" as an error and return or exit non-zero with the
# most recent exit status or 1. If MESSAGE is the empty string, suppress output.
function lk_die() {
    local STATUS=$?
    ((STATUS)) || STATUS=1
    [ "${1+1}${1:+2}" = 1 ] ||
        lk_tty_error "$(_lk_caller): ${1:-command failed}"
    if [[ $- != *i* ]]; then
        exit "$STATUS"
    else
        return "$STATUS"
    fi
}

function lk_mktemp() {
    local TMPDIR=${TMPDIR:-/tmp} FUNC=${FUNCNAME[1 + ${_LK_STACK_DEPTH:-0}]-}
    mktemp "$@" ${_LK_MKTEMP_ARGS-} \
        "${TMPDIR%/}/${0##*/}${FUNC:+-$FUNC}${_LK_MKTEMP_EXT-}.XXXXXXXXXX"
}

# lk_mktemp_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary file that will be deleted when the (sub)shell exits, assign
# its path to VAR, and return after invoking COMMAND (if given) and redirecting
# its output to the file. If VAR is already set to the path of an existing
# file and -r ("reuse") is set, proceed without creating a new file.
function lk_mktemp_with() {
    local _REUSE= _DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [ "${1-}" != -r ] || { _REUSE=1 && shift; }
    [ $# -ge 1 ] || lk_err "invalid arguments" || return
    local _VAR=$1
    shift
    [ -n "${_REUSE-}" ] && [ -e "${!_VAR-}" ] ||
        { eval "$_VAR=\$(_LK_STACK_DEPTH=\$_DEPTH lk_mktemp)" &&
            lk_delete_on_exit "${!_VAR}"; } || return
    [ $# -eq 0 ] || "$@" >"${!_VAR}"
}

# lk_mktemp_dir_with [-r] VAR [COMMAND [ARG...]]
#
# Create a temporary directory that will be deleted when the (sub)shell exits,
# assign its path to VAR, and return after invoking COMMAND (if given) in the
# directory. If VAR is already set to the path of an existing directory and -r
# ("reuse") is set, proceed without creating a new directory.
function lk_mktemp_dir_with() {
    local _ARGS=() _DEPTH=$((1 + ${_LK_STACK_DEPTH:-0}))
    [ -z "${1+1}" ] || _ARGS[0]=$1
    [ "${1-}" != -r ] || [ -z "${2+1}" ] || _ARGS[1]=$2
    _LK_STACK_DEPTH=$_DEPTH _LK_MKTEMP_ARGS=-d \
        lk_mktemp_with ${_ARGS+"${_ARGS[@]}"} || return
    local _VAR=${_ARGS[1]-${_ARGS[0]}}
    shift "${#_ARGS[@]}"
    [ $# -eq 0 ] || (cd "${!_VAR}" && "$@")
}

# lk_trap_add SIGNAL COMMAND [ARG...]
function lk_trap_add() {
    [ $# -ge 2 ] ||
        lk_usage "Usage: $FUNCNAME SIGNAL COMMAND [ARG...]" || return
    local IFS
    unset IFS
    [ $# -eq 2 ] ||
        set -- "$1" "$2$(printf ' %q' "${@:3}")"
    _LK_TRAPS=(${_LK_TRAPS+"${_LK_TRAPS[@]}"})
    local i TRAPS=()
    for ((i = 0; i < ${#_LK_TRAPS[@]}; i += 3)); do
        ((_LK_TRAPS[i] == BASH_SUBSHELL)) &&
            [[ ${_LK_TRAPS[i + 1]} == "$1" ]] || continue
        TRAPS[${#TRAPS[@]}]=${_LK_TRAPS[i + 2]}
        [[ ${_LK_TRAPS[i + 2]} != "${2-}" ]] ||
            set -- "$1"
    done
    [ $# -eq 1 ] || {
        TRAPS[${#TRAPS[@]}]=$2
        _LK_TRAPS+=("$BASH_SUBSHELL" "$1" "$2")
    }
    trap -- "$(
        printf '{ %s; }' "$TRAPS"
        [ "${#TRAPS[@]}" -lt 2 ] || printf ' && { %s; }' "${TRAPS[@]:1}"
    )" "$1"
}

function _lk_cleanup_on_exit() {
    local ARRAY=$1 COMMAND=$2
    shift 2
    [ -n "${!ARRAY+1}" ] ||
        { COMMAND="{ [ -z \"\${${ARRAY}+1}\" ] ||
    $COMMAND \"\${${ARRAY}[@]}\" || [ \"\$EUID\" -eq 0 ] ||
    sudo $COMMAND \"\${${ARRAY}[@]}\" || true; } 2>/dev/null" &&
            eval "$ARRAY=()" &&
            lk_trap_add EXIT "$COMMAND" || return; }
    eval "$ARRAY+=(\"\$@\")"
}

function lk_kill_on_exit() {
    _lk_cleanup_on_exit "_LK_EXIT_KILL_$BASH_SUBSHELL" "kill" "$@"
}

function lk_delete_on_exit() {
    _lk_cleanup_on_exit "_LK_EXIT_DELETE_$BASH_SUBSHELL" "rm -Rf --" "$@"
}

# lk_delete_on_exit_withdraw FILE...
function lk_delete_on_exit_withdraw() {
    while [ $# -gt 0 ]; do
        lk_arr_remove "_LK_EXIT_DELETE_$BASH_SUBSHELL" "$1" || return
        shift
    done
}

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

# - lk_tty_list - [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]
# - lk_tty_list @ [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]] [-- [ARG...]]
# - lk_tty_list [ARRAY [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]]
function lk_tty_list() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    [ "${1-}" != @ ] || {
        local IFS=' ' _ITEMS=()
        for ((i = 2; i <= $#; i++)); do
            [ "${!i}" = -- ] || continue
            _ITEMS=("${@:i+1}")
            set -- "${@:1:i-1}"
            break
        done
    }
    local _ARRAY=${1:--} _MESSAGE=${2-List:} _SINGLE _PLURAL _COLOUR \
        _PREFIX=${_LK_TTY_PREFIX-${_LK_TTY_PREFIX1-==> }} \
        _ITEMS _INDENT _COLUMNS _LIST=
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
    elif [ "$_ARRAY" != @ ]; then
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
    [ -z "${_ITEMS+1}" ] || {
        _LIST=$(printf '\n%s' "${_ITEMS[@]}")
        ! lk_command_exists column expand ||
            _LIST=$'\n'$(COLUMNS=$((_COLUMNS > 0 ? _COLUMNS : 0)) \
                column <<<"$_LIST" | expand) || eval "$_lk_x_return"
    }
    echo "$(
        _LK_FD=1
        ${_LK_TTY_COMMAND:-lk_tty_print} \
            "$_MESSAGE" "$_LIST" ${!_COLOUR+"${!_COLOUR}"}
        [ -z "${_SINGLE:+${_PLURAL:+1}}" ] ||
            _LK_TTY_PREFIX=$(printf "%$((_INDENT > 0 ? _INDENT : 0))s") \
                lk_tty_detail "($(lk_plural -v _ITEMS "$_SINGLE" "$_PLURAL"))"
    )" >&"${_LK_FD-2}"
    eval "$_lk_x_return"
}

# - lk_tty_list_detail - [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]]
# - lk_tty_list_detail @ [MESSAGE [SINGLE_NOUN PLURAL_NOUN] [COLOUR]] [-- [ARG...]]
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
        [[ -z ${BASH_REMATCH[2]} ]] &&
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
    local IFS=${IFS:-$'\t'} LF COLOUR ARGS= _IFS TEMP LEN KEY VALUE
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
        _IFS=$(LF=${LF:-\\0} && printf "%s${LF//%/%%}" "$IFS" |
            awk -v "RS=$LF" '
{ FS = ORS = RS
  gsub(/./, "&" RS)
  for (i = 1; i < NF; i++) {
    if ($i == "-") { last = "-" }
    else if ($i == "]") { first = "]" }
    else { middle = middle $i } }
  printf("%s%s%s.\n", first, middle, last) }') && IFS=${_IFS%.} ||
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
    local STATUS=${_lk_x_status:-$?} BOLD= IFS=' ' \
        _LK_TTY_PREFIX=${_LK_TTY_PREFIX-$1} \
        _LK_TTY_MESSAGE_COLOUR=$2 _LK_TTY_COLOUR2=${_LK_TTY_COLOUR2-}
    shift 2
    [ "${1-}" = -r ] && shift || STATUS=0
    [ "${1-}" = -n ] && shift || BOLD=1
    local MESSAGE=${1-} MESSAGE2=${2-}
    [ -z "${MESSAGE:+1}" ] || _lk_tty_format -b MESSAGE
    [ -z "${MESSAGE2:+$BOLD}" ] || _lk_tty_format -b MESSAGE2
    lk_tty_print "$MESSAGE" "$MESSAGE2${3+ ${*:3}}" "$_LK_TTY_MESSAGE_COLOUR"
    return "$STATUS"
}

# lk_tty_success [-r] [-n] MESSAGE [MESSAGE2...]
function lk_tty_success() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _lk_tty_log " // " "$_LK_SUCCESS_COLOUR" "$@"
    eval "$_lk_x_return"
}

# lk_tty_log [-r] [-n] MESSAGE [MESSAGE2...]
function lk_tty_log() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _lk_tty_log " :: " "${_LK_TTY_COLOUR-$_LK_COLOUR}" "$@"
    eval "$_lk_x_return"
}

# lk_tty_warning [-r] [-n] MESSAGE [MESSAGE2...]
function lk_tty_warning() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _lk_tty_log "  ! " "$_LK_WARNING_COLOUR" "$@"
    eval "$_lk_x_return"
}

# lk_tty_error [-r] [-n] MESSAGE [MESSAGE2...]
function lk_tty_error() {
    { eval "$(lk_x_off)"; } 2>/dev/null 4>&2
    _lk_tty_log " !! " "$_LK_ERROR_COLOUR" "$@"
    eval "$_lk_x_return"
}

# _lk_var [STACK_DEPTH]
#
# Print 'declare ' if the command that called the caller belongs to a function.
# In this context, declarations printed for `eval` should create local variables
# rather than globals.
function _lk_var() {
    local DEPTH=${1:-0} _LK_STACK_DEPTH=${_LK_STACK_DEPTH:-0}
    ((DEPTH += _LK_STACK_DEPTH, _LK_STACK_DEPTH < 0 || DEPTH < 0)) ||
        [[ ${FUNCNAME[DEPTH + 2]-} =~ ^(^|source|main)$ ]] ||
        printf 'declare '
}

# lk_var_sh [-a] [VAR...]
#
# Print a variable assignment statement for each declared VAR. If -a is set,
# include undeclared variables.
function lk_var_sh() {
    local __ALL=0
    [ "${1-}" != -a ] || { __ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        if [ -n "${!1+1}" ]; then
            printf '%s=%s\n' "$1" "$(lk_double_quote "${!1-}")"
        elif ((__ALL)); then
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_var_sh_q [-a] [VAR...]
#
# Print Bash-compatible assignment statements for each declared VAR. If -a is
# set, include undeclared variables.
function lk_var_sh_q() {
    local __ALL=0
    [ "${1-}" != -a ] || { __ALL=1 && shift; }
    while [ $# -gt 0 ]; do
        _lk_var
        if lk_var_array "$1"; then
            printf '%s=(%s)\n' "$1" "$(lk_quote_arr "$1")"
        elif [ -n "${!1:+1}" ]; then
            printf '%s=%q\n' "$1" "${!1}"
        elif ((__ALL)) || [ -n "${!1+1}" ]; then
            printf '%s=\n' "$1"
        fi
        shift
    done
}

# lk_var_env VAR
#
# Print the original value of VAR if it was in the environment when Bash was
# invoked. Requires `_LK_ENV=$(declare -x)` at or near the top of the script.
function lk_var_env() { (
    [ -n "${_LK_ENV+1}" ] || lk_err "_LK_ENV not set" || return
    unset "$1" || return
    eval "$_LK_ENV" 2>/dev/null || true
    declare -p "$1" 2>/dev/null |
        awk 'NR == 1 && $2 ~ "x"' | grep . >/dev/null && echo "${!1-}"
); }

function lk_var_has_attr() {
    local REGEX="^declare -$NS*$2"
    [[ $(declare -p "$1" 2>/dev/null) =~ $REGEX ]]
}

function lk_var_declared() {
    declare -p "$1" &>/dev/null
}

function lk_var_array() {
    lk_var_has_attr "$1" a
}

function lk_var_exported() {
    lk_var_has_attr "$1" x
}

function lk_var_readonly() {
    lk_var_has_attr "$1" r
}

# lk_var_not_null VAR...
#
# Return false if any VAR is unset or set to the empty string.
function lk_var_not_null() {
    while [ $# -gt 0 ]; do
        [ -n "${!1:+1}" ] || return
        shift
    done
}

# lk_var_to_bool VAR [TRUE FALSE]
#
# If the value of VAR is 'Y', 'yes', '1', 'true' or 'on' (not case-sensitive),
# assign TRUE (default: Y) to VAR, otherwise assign FALSE (default: N).
function lk_var_to_bool() {
    [ $# -eq 3 ] || set -- "$1" Y N
    if lk_true "$1"; then
        eval "$1=\$2"
    else
        eval "$1=\$3"
    fi
}

# lk_var_to_int VAR [NULL]
#
# Convert the value of VAR to an integer. If VAR is unset, empty or invalid,
# assign NULL (default: 0).
function lk_var_to_int() {
    [ $# -eq 2 ] || set -- "$1" 0
    [[ ! ${!1-} =~ ^0*([0-9]+)(\.[0-9]*)?$ ]] || set -- "$1" "${BASH_REMATCH[1]}"
    eval "$1=\$2"
}

# lk_no_input
#
# Check LK_NO_INPUT and LK_FORCE_INPUT, and return true if user input should not
# be requested.
function lk_no_input() {
    if [ "${LK_FORCE_INPUT-}" = 1 ]; then
        { [ -t 0 ] || lk_err "/dev/stdin is not a terminal"; } && false
    else
        [ ! -t 0 ] || [ "${LK_NO_INPUT-}" = 1 ]
    fi
}

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
        read -rep "$(_lk_tty_prompt)" "${@:4}" "$2" 2>&"${_LK_FD-2}" || return
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
            read -rep "$PROMPT" "${@:3}" REPLY 2>&"${_LK_FD-2}" || return
            [ -n "$REPLY" ] || REPLY=$DEFAULT
            [[ ! $REPLY =~ ^$YES$ ]] || return 0
            [[ ! $REPLY =~ ^$NO$ ]] || return 1
        done
    fi
}

# lk_trace [MESSAGE]
function lk_trace() {
    [ "${LK_DEBUG-}" = Y ] || return 0
    local NOW
    NOW=$(gnu_date +%s.%N) || return 0
    _LK_TRACE_FIRST=${_LK_TRACE_FIRST:-$NOW}
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$NOW" \
        "$_LK_TRACE_FIRST" \
        "${_LK_TRACE_LAST:-$NOW}" \
        "${1+${1::30}}" \
        "${BASH_SOURCE[1]+${BASH_SOURCE[1]#$LK_BASE/}:${BASH_LINENO[0]}}" |
        awk -F'\t' -v "d=$LK_DIM" -v "u=$LK_UNDIM" \
            '{printf "%s%09.4f  +%.4f\t%-30s\t%s\n",d,$1-$2,$1-$3,$4,$5 u}' >&2
    _LK_TRACE_LAST=$NOW
}

# lk_stack_trace [FIRST_FRAME_DEPTH [ROWS [FIRST_FRAME]]]
function lk_stack_trace() {
    local DEPTH=$((${1:-0} + ${_LK_STACK_DEPTH:-0})) ROWS=${2:-0} FRAME=${3-} \
        _D=$((${#FUNCNAME[@]} - 1)) _R WIDTH ROW=0 FUNC FILE LINE \
        REGEX='^([0-9]*) ([^ ]*) (.*)$'
    # _D = maximum DEPTH, _R = maximum rows of output (DEPTH=0 is always skipped
    # to exclude lk_stack_trace)
    ((_R = _D - DEPTH, ROWS = ROWS ? (ROWS > _R ? _R : ROWS) : _R, ROWS)) ||
        lk_err "invalid arguments" || return
    WIDTH=${#_R}
    while ((ROW++ < ROWS)) && ((DEPTH++ < _D)); do
        FUNC=${FUNCNAME[DEPTH]-"{main}"}
        FILE=${BASH_SOURCE[DEPTH]-"{main}"}
        LINE=${BASH_LINENO[DEPTH - 1]-0}
        [[ ! ${FRAME-} =~ $REGEX ]] || {
            FUNC=${BASH_REMATCH[2]:-$FUNC}
            FILE=${BASH_REMATCH[3]:-$FILE}
            LINE=${BASH_REMATCH[1]:-$LINE}
            unset FRAME
        }
        ((ROWS == 1)) || printf "%${WIDTH}d. " "$ROW"
        printf "%s %s (%s:%s)\n" \
            "$( ((ROW > 1)) && echo at || echo in)" \
            "$LK_BOLD$FUNC$LK_RESET" "$FILE$LK_DIM" "$LINE$LK_UNDIM"
    done
}

function lk_require() {
    local FILE
    while [ $# -gt 0 ]; do
        [[ ,$_LK_PROVIDED, == *,$1,* ]] || {
            FILE=${_LK_INST:-$LK_BASE}/lib/bash/include/$1.sh
            [ -r "$FILE" ] || lk_err "file not found: $FILE" || return
            . "$FILE" || return
        }
        shift
    done
}

function lk_provide() {
    [[ ,$_LK_PROVIDED, == *,$1,* ]] ||
        _LK_PROVIDED=$_LK_PROVIDED,$1
}

# _lk_usage_format <CALLER>
function _lk_usage_format() {
    set -- "$(lk_sed_escape "${1-}")" \
        "$(lk_sed_escape_replace "$LK_BOLD")" \
        "$(lk_sed_escape_replace "$LK_RESET")"
    sed -E "
# Print the command name in bold
s/^($S*([uU]sage:|[oO]r:)?$S+(sudo )?)($1)($S|\$)/\1$2\4$3\5/
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

# lk_fifo_flush FIFO_PATH
function lk_fifo_flush() {
    [ -p "${1-}" ] || lk_err "not a FIFO: ${1-}" || return
    gnu_dd \
        if="$1" \
        of=/dev/null \
        iflag=nonblock \
        status=none &>/dev/null || true
}

# lk_ps_recurse_children [-p] PPID...
#
# Print the process ID of all processes descended from PPID. If -p is set,
# include PPID in the output.
function lk_ps_recurse_children() {
    [ "${1-}" != -p ] || {
        shift
        [ $# -eq 0 ] || printf '%s\n' "$@"
    }
    ps -eo pid=,ppid= | awk '
function recurse(p, _a, _i) { if (c[p]) {
    split(c[p], _a, ",")
    for (_i in _a) {
        print _a[_i]
        recurse(_a[_i])
    }
} }
BEGIN { for (i = 1; i < ARGC; i++) {
    ps[i] = ARGV[i]
    delete ARGV[i]
} }
{ c[$2] = (c[$2] ? c[$2] "," : "") $1 }
END { for (i in ps) {
    recurse(ps[i])
} }' "$@"
}

# lk_fd_is_open FD
function lk_fd_is_open() {
    [ -n "${1-}" ] && { : >&"$1"; } 2>/dev/null
}

# lk_fd_next
#
# In lieu of Bash 4.1's file descriptor variable syntax ({var}>, {var}<, etc.),
# output the number of the next available file descriptor greater than or equal
# to 10.
function lk_fd_next() {
    local USED FD=10 i=0
    [ -d /dev/fd ] &&
        USED=($(ls -1 /dev/fd/ | sort -n)) && [ ${#USED[@]} -ge 3 ] ||
        lk_err "not supported: /dev/fd" || return
    while ((i < ${#USED[@]})); do
        ((FD >= USED[i])) || break
        ((FD > USED[i])) || ((FD++))
        ((++i))
    done
    echo "$FD"
}

function _lk_log_install_file() {
    local GID
    if [ ! -w "$1" ]; then
        if [ ! -e "$1" ]; then
            local LOG_DIR=${1%"${1##*/}"}
            [ -d "${LOG_DIR:=$PWD}" ] ||
                install -d -m 00755 "$LOG_DIR" 2>/dev/null ||
                sudo install -d -m 01777 "$LOG_DIR" || return
            install -m 00600 /dev/null "$1" 2>/dev/null ||
                { GID=$(id -g) &&
                    sudo install -m 00600 -o "$UID" -g "$GID" /dev/null "$1"; }
        else
            chmod 00600 "$1" 2>/dev/null ||
                sudo chmod 0600 "$1" || return
            [ -w "$1" ] ||
                sudo chown "$UID" "$1"
        fi
    fi
}

# lk_dir_is_empty [DIR]
#
# Return true if DIR is empty.
function lk_dir_is_empty() {
    ! lk_sudo ls -A "$1" 2>/dev/null | grep . >/dev/null &&
        [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" = 01 ]
}

# lk_file_maybe_move OLD_PATH CURRENT_PATH
#
# If OLD_PATH exists and CURRENT_PATH doesn't, move OLD_PATH to CURRENT_PATH.
function lk_file_maybe_move() {
    lk_sudo -f test ! -e "$1" ||
        lk_sudo -f test -e "$2" || {
        lk_sudo mv -nv "$1" "$2" &&
            LK_FILE_NO_CHANGE=0
    }
}

# lk_file_list_duplicates [DIR]
#
# Print a list of files in DIR or the current directory that would be considered
# duplicates on a case-insensitive filesystem. Only useful on case-sensitive
# filesystems.
function lk_file_list_duplicates() {
    find "${1:-.}" -print0 | sort -zf | gnu_uniq -zDi | tr '\0' '\n'
}

# lk_hash [ARG...]
#
# Compute the hash of the arguments or input using the most efficient algorithm
# available (xxHash, SHA or MD5), joining multiple arguments to form one string
# with a space between each argument.
function lk_hash() {
    _LK_HASH_COMMAND=${_LK_HASH_COMMAND:-${LK_HASH_COMMAND:-$(
        lk_first_command xxhsum shasum md5sum md5
    )}} || lk_err "checksum command not found" || return
    if [ $# -gt 0 ]; then
        local IFS
        unset IFS
        printf '%s' "$*" | "$_LK_HASH_COMMAND"
    else
        "$_LK_HASH_COMMAND"
    fi | awk '{print $1}'
}

function lk_md5() {
    local _LK_HASH_COMMAND
    _LK_HASH_COMMAND=$(lk_first_command md5sum md5) ||
        lk_err "md5 command not found" || return
    lk_hash "$@"
}

# lk_maybe [-p] COMMAND [ARG...]
#
# Run COMMAND unless LK_DRY_RUN is set. If -p is set, print COMMAND if not
# running it.
function lk_maybe() {
    local PRINT
    [ "${1-}" != -p ] || { PRINT=1 && shift; }
    if lk_dry_run; then
        [ -z "${PRINT-}" ] && ! lk_verbose ||
            lk_tty_log \
                "${LK_YELLOW}[DRY RUN]${LK_RESET} Not running:" \
                "$(lk_quote_args "$@")"
    else
        "$@"
    fi
}

# lk_report_error [-q] COMMAND [ARG...]
#
# Run COMMAND and print an error message if it exits non-zero. If -q is set,
# discard output to stderr unless COMMAND fails.
function lk_report_error() {
    local QUIET STDERR
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    if [ -n "${QUIET-}" ]; then
        lk_mktemp_with STDERR || return
        "$@" 2>"$STDERR"
    else
        "$@"
    fi || {
        local STATUS=$? IFS=' '
        [ ! -s "${STDERR-}" ] || cat "$STDERR" >&2
        lk_tty_error "Exit status $STATUS:" "$*"
        return $STATUS
    }
}

# lk_faketty [exec] COMMAND [ARG...]
#
# Run COMMAND in a pseudo-terminal to satisfy tty checks even if output is being
# redirected.
function lk_faketty() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    if ! lk_is_macos; then
        SHELL=$BASH lk_sudo script -qfec "$(lk_quote_args "$@")" /dev/null
    else
        lk_sudo script -qt 0 /dev/null "$@"
    fi
}

# lk_keep_trying [-MAX_ATTEMPTS] COMMAND [ARG...]
#
# Execute COMMAND until its exit status is zero or MAX_ATTEMPTS have been made
# (default: 10). The delay between each attempt starts at 1 second and follows
# the Fibonnaci sequence (2 sec, 3 sec, 5 sec, 8 sec, 13 sec, etc.).
function lk_keep_trying() {
    local i=0 MAX_ATTEMPTS=10 WAIT=1 PREV=1 NEXT _IFS=${IFS-$' \t\n'}
    [[ ! ${1-} =~ ^-[0-9]+$ ]] || { MAX_ATTEMPTS=${1:1} && shift; }
    while :; do
        "$@" && return 0 || {
            local STATUS=$? IFS=' '
            ((++i < MAX_ATTEMPTS)) || break
            lk_tty_log "Failed (attempt $i of $MAX_ATTEMPTS):" "$*"
            lk_tty_detail "Trying again in $(lk_plural -v $WAIT second)"
            sleep "$WAIT"
            ((NEXT = WAIT + PREV, PREV = WAIT, WAIT = NEXT))
            lk_tty_print
            IFS=$_IFS
        }
    done
    return $STATUS
}

# lk_require_output [-q] COMMAND [ARG...]
#
# Return true if COMMAND writes output other than newlines and exits without
# error. If -q is set, suppress output.
function lk_require_output() { (
    unset QUIET
    [ "${1-}" != -q ] || { QUIET=1 && shift; }
    FILE=$(lk_mktemp) && lk_delete_on_exit "$FILE" &&
        if [ -z "${QUIET-}" ]; then
            "$@" | tee "$FILE"
        else
            "$@" >"$FILE"
        fi &&
        grep -Eq '^.+$' "$FILE"
); }

# lk_env_clean COMMAND [ARG...]
#
# Remove _LK_* variables from the environment of COMMAND.
function lk_env_clean() {
    local _UNSET=("${!_LK_@}")
    if [ -n "${_UNSET+1}" ]; then
        env "${_UNSET[@]/#/--unset=}" "$@"
    else
        "$@"
    fi
}

function lk_jq() {
    jq -L"$LK_BASE/lib"/{jq,json} "$@"
}

# lk_jq_var <JQ_ARG...> -- <VAR...>
#
# Run jq with the value of each VAR passed to the jq filter as a variable with
# the equivalent camelCase name.
#
# Example:
#
#     $ lk_jq_var -n '{$bashVersion,path:$path|split(":")}' -- BASH_VERSION PATH
#     {
#       "bashVersion": "5.1.16(1)-release",
#       "path": [
#         "/usr/local/bin",
#         "/usr/local/sbin",
#         "/usr/bin",
#         "/bin",
#         "/usr/sbin",
#         "/sbin"
#       ]
#     }
function lk_jq_var() {
    local _ARGS=() _VAR _ARG _CMD=()
    while [ $# -gt 0 ]; do
        [ "$1" = -- ] || { _ARGS[${#_ARGS[@]}]=$1 && shift && continue; }
        shift && break
    done
    while IFS=$'\t' read -r _VAR _ARG; do
        _CMD+=(--arg "$_ARG" "${!_VAR-}")
    done < <(((!$#)) || printf '%s\n' "$@" | awk -F_ '
{ l = $0; sub("^_+", ""); v = tolower($1)
  for(i = 2; i <= NF; i++)
    { v = v toupper(substr($i,1,1)) tolower(substr($i,2)) }
  print l "\t" v }')
    lk_jq ${_CMD+"${_CMD[@]}"} ${_ARGS+"${_ARGS[@]}"}
}

# lk_json_mapfile <ARRAY> [JQ_FILTER]
#
# Apply JQ_FILTER (default: '.[]') to the input and populate ARRAY with the
# output, using JSON encoding if necessary.
function lk_json_mapfile() {
    local IFS _SH
    unset IFS
    _SH="$1=($(lk_jq -r "${2:-.[]} | tostring | @sh"))" &&
        eval "$_SH"
}

# lk_json_sh (<VAR> <JQ_FILTER>)...
function lk_json_sh() {
    (($# && !($# % 2))) || lk_err "invalid arguments" || return
    local IFS
    unset IFS
    lk_jq -r --arg prefix "$(_lk_var)" 'include "core"; {'"$(
        printf '"%s":(%s)' "${@:1:2}"
        (($# < 3)) || printf ',"%s":(%s)' "${@:3}"
    )"'} | to_sh($prefix)'
}

# lk_uri_encode PARAMETER=VALUE...
function lk_uri_encode() {
    local ARGS=()
    while [ $# -gt 0 ]; do
        [[ $1 =~ ^([^=]+)=(.*) ]] || lk_err "invalid parameter: $1" || return
        ARGS+=(--arg "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
        shift
    done
    [ ${#ARGS[@]} -eq 0 ] ||
        jq -rn "${ARGS[@]}" \
            '[$ARGS.named|to_entries[]|"\(.key)=\(.value|@uri)"]|join("&")'
}

lk_confirm() { lk_tty_yn "$@"; }
lk_echo_array() { lk_arr "$@"; }
lk_escape_ere_replace() { lk_sed_escape_replace "$@"; }
lk_escape_ere() { lk_sed_escape "$@"; }
lk_first_existing() { lk_first_file "$@"; }
lk_is_false() { lk_false "$@"; }
lk_is_true() { lk_true "$@"; }
lk_jq_get_array() { lk_json_mapfile "$@"; }
lk_maybe_sudo() { lk_sudo "$@"; }
lk_mktemp_dir() { _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0})) lk_mktemp -d; }
lk_mktemp_file() { _LK_STACK_DEPTH=$((1 + ${_LK_STACK_DEPTH:-0})) lk_mktemp; }
lk_regex_implode() { lk_ere_implode_args -- "$@"; }
lk_test_many() { lk_test "$@"; }
lk_tty_detail_pairs() { lk_tty_pairs_detail "$@"; }

# lk_path_edit REMOVE_REGEX [MOVE_REGEX [PATH]]
function lk_path_edit() {
    [ $# -gt 0 ] || lk_usage "\
Usage: $FUNCNAME REMOVE_REGEX [MOVE_REGEX [PATH]]" || return
    awk \
        -v "remove=$1" \
        -v "move=${2-}" \
        'function p(v) { printf "%s%s", s, v; s = ":" }
BEGIN { RS = "[:\n]+" }
remove && $0 ~ remove { next }
move && $0 ~ move { a[i++] = $0; next }
{ p($0) }
END{ for (i = 0; i < length(a); i++) p(a[i]) }' <<<"${3-$PATH}"
}

# lk_check_pid PID
#
# Return true if a signal could be sent to the given process by the current
# user.
function lk_check_pid() {
    [ $# -eq 1 ] || return
    lk_maybe_sudo kill -0 "$1" 2>/dev/null
}

# lk_curl_config [--]ARG[=PARAM]...
#
# Output each ARG=PARAM pair formatted for use with `curl --config`.
function lk_curl_config() {
    awk 'BEGIN {
    for (i = 1; i < ARGC; i++) {
        if (ARGV[i] !~ /^(--)?[^-=[:blank:]][^=[:blank:]]*(=.*)?$/) {
            print "invalid argument: " ARGV[i] | "cat >&2"
            exit 1
        }
        name = value = ARGV[i]
        gsub(/(^--|=.*)/, "", name)
        sub(/^[^=]+/, "", value)
        if (!value) {
            printf "--%s\n", name
        } else {
            sub(/^=/, "", value)
            gsub(/["\\]/, "\\\\&", value)
            gsub(/\t/, "\\t", value)
            gsub(/\n/, "\\n", value)
            gsub(/\r/, "\\r", value)
            gsub(/\v/, "\\v", value)
            printf "--%s \"%s\"\n", name, value
        }
    }
}' "$@"
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
        l=${1:i:1}
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

# lk_regex_expand_whitespace [-o] [STRING...]
#
# Replace unquoted sequences of one or more whitespace characters in each STRING
# or input with "[[:blank:]]+". If -o is set, make whitespace optional by using
# "[[:blank:]]*" as the replacement string.
#
# Example:
#
#     $ lk_regex_expand_whitespace "message = 'Here\'s a message'"
#     message[[:blank:]]+=[[:blank:]]+'Here\'s a message'
function lk_regex_expand_whitespace() {
    local QUANTIFIER="+"
    [ "${1-}" != -o ] || { QUANTIFIER="*" && shift; }
    lk_replace_whitespace "[[:blank:]]$QUANTIFIER" "$@"
}

# lk_replace_whitespace REPLACE [STRING...]
function lk_replace_whitespace() {
    [ $# -ge 1 ] || lk_usage "Usage: $FUNCNAME REPLACE [STRING...]" || return
    if [ $# -gt 1 ]; then
        printf '%s\n' "${@:2}" | lk_replace_whitespace "$1"
    else
        awk -v "replace=$1" '
NR == 1 { s_in = $0; next }
        { s_in = s_in RS $0 }
END     {
    # \47 = single quote
    not_special    = "([^\47\"[:blank:]\\\\]|\\\\.)+"
    quoted_single  = "(\47\47|\47([^\47\\\\]|\\\\.)*\47)"
    quoted_double  = "(\"\"|\"([^\"\\\\]|\\\\.)*\")"
    not_whitespace = "^(" not_special "|" quoted_single "|" quoted_double ")*"
    while (length(s_in) && match(s_in, not_whitespace)) {
        l = RLENGTH
        s_out = s_out substr(s_in, 1, l) (l < length(s_in) ? replace : "")
        s_in = substr(s_in, l + 1)
        if (! sub(/[[:blank:]]+/, "", s_in) && l < length(s_in)) {
            print FILENAME ": unmatched \47 or \"" > "/dev/stderr"
            exit 1
        }
    }
    print s_out
}'
    fi
}

function lk_has_newline() {
    [ "${!1/$'\n'/}" != "${!1}" ]
}

function lk_var_list() {
    eval "printf '%s\n'$(printf ' "${!%s@}"' {a..z} {A..Z} _)"
}

# lk_expand_template [-e] [-q] [FILE]
#
# Replace each {{KEY}} in FILE or input with the value of variable KEY, and each
# {{"KEY"}} with the output of `printf %q "$KEY"`. If -e is set, also replace
# each ({:LIST:}) with the output of `eval LIST`. If -q is set, quote all
# replacement values.
function lk_expand_template() {
    local OPTIND OPTARG OPT EVAL QUOTE TEMPLATE KEYS i REPLACE KEY QUOTED
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
Usage: $FUNCNAME [-e] [-q] [FILE]"
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    TEMPLATE=$(cat ${1+"$1"} && printf .) || return
    ! lk_is_true EVAL || {
        lk_mapfile KEYS <(
            # Add a newline to guarantee $'...\n'
            printf '%q' "$TEMPLATE"$'\n' |
                grep -Eo '\(\{:([^:]*|:[^}]|:\}[^)])*:\}\)' |
                sort -u
        )
        [ ${#KEYS[@]} -eq 0 ] ||
            for i in $(seq 0 $((${#KEYS[@]} - 1))); do
                eval "KEYS[i]=\$'${KEYS[i]:3:$((${#KEYS[i]} - 6))}'"
                REPLACE=$(eval "${KEYS[i]}" && printf .) ||
                    lk_warn "error evaluating: ${KEYS[i]}" || return
                ! lk_is_true QUOTE ||
                    REPLACE=$(printf '%q.' "${REPLACE%.}")
                REPLACE=${REPLACE%.}
                TEMPLATE=${TEMPLATE//"({:${KEYS[i]}:})"/$REPLACE}
            done
    }
    KEYS=($(echo "$TEMPLATE" |
        grep -Eo '\{\{"?[a-zA-Z_][a-zA-Z0-9_]*"?\}\}' | sort -u |
        sed -E 's/^\{\{"?([a-zA-Z0-9_]+)"?\}\}$/\1/')) || true
    for KEY in ${KEYS[@]+"${KEYS[@]}"}; do
        [ -n "${!KEY+1}" ] ||
            lk_warn "variable not set: $KEY" || return
        REPLACE=${!KEY}
        QUOTED=$(printf '%q.' "$REPLACE")
        QUOTED=${QUOTED%.}
        ! lk_is_true QUOTE ||
            REPLACE=$QUOTED
        TEMPLATE=${TEMPLATE//"{{$KEY}}"/$REPLACE}
        TEMPLATE=${TEMPLATE//"{{\"$KEY\"}}"/$QUOTED}
    done
    TEMPLATE=${TEMPLATE%.}
    echo "${TEMPLATE%$'\n'}"
}

function lk_lower() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_lower
    else
        tr '[:upper:]' '[:lower:]'
    fi
}

function lk_upper() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_upper
    else
        tr '[:lower:]' '[:upper:]'
    fi
}

function lk_upper_first() {
    local EXIT_STATUS
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    printf '%s%s\n' "$(lk_upper "${1:0:1}")" "$(lk_lower "${1:1}")"
}

function lk_trim() {
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" | lk_trim
    else
        sed -E "s/^$S*(.*$NS)?$S*\$/\1/"
    fi
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

function lk_awk_dir() {
    local DIR=${LK_BASE:+$LK_BASE/lib/awk} FILE
    [ -d "$DIR" ] || {
        FILE=${BASH_SOURCE[1]:-$PWD/}
        DIR=${FILE%/*}
        [ "$DIR" != "$FILE" ] && [ -d "$DIR" ] || DIR=.
    }
    echo "$DIR"
}

function _lk_get_colour() {
    local SEQ
    while [ $# -ge 2 ]; do
        SEQ=$(tput $2) || SEQ=
        printf '%s%s=%q\n' "$PREFIX" "$1" "$SEQ"
        [ "$1" != DIM ] ||
            printf '%s%s=%q\n' "$PREFIX" UNDIM \
                "$([ "$SEQ" != $'\E[2m' ] || echo $'\E[22m')"
        shift 2
    done
}

# lk_get_colours [PREFIX]
function lk_get_colours() {
    local PREFIX
    PREFIX="declare ${1-LK_}"
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
        UL_ON "smul" \
        UL_OFF "rmul" \
        WRAP_OFF "rmam" \
        WRAP_ON "smam" \
        RESET "sgr0"
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

# lk_echo_args [-z] [ARG...]
function lk_echo_args() {
    local DELIM=${LK_Z:+'\0'}
    [ "${1-}" != -z ] || { DELIM='\0' && shift; }
    [ $# -eq 0 ] ||
        printf "%s${DELIM:-\\n}" "$@"
}

# lk_array_merge NEW_ARRAY [ARRAY...]
function lk_array_merge() {
    [ $# -ge 2 ] || return
    eval "$1=($(for i in "${@:2}"; do
        printf '${%s[@]+"${%s[@]}"}\n' "$i" "$i"
    done))"
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
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
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
    [ "${2-}" != -z ] || (($# - $1 - 2)) ||
        { LK_Z=1 && set -- "$1" "${@:3}"; }
    # Return false ASAP if there's exactly one value for the caller to process
    (($# - $1 - 2)) || return
    COMMAND=("${FUNCNAME[1]}" "${@:2:$1}")
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

function lk_has_arg() {
    lk_in_array "$1" _LK_ARGV
}

function _lk_cache_dir() {
    local VAR=_LK_OUTPUT_CACHE DIR SUBDIR=
    [ -z "${_LK_CACHE_NAMESPACE:+1}" ] || {
        VAR+=_$_LK_CACHE_NAMESPACE
        SUBDIR=/$_LK_CACHE_NAMESPACE
    }
    # "${!VAR:=...}" doesn't work in Bash 3.2
    DIR=${!VAR:-$(
        TMPDIR=${TMPDIR:-/tmp}
        DIR=${TMPDIR%/}/_lk_output_cache_$EUID$SUBDIR
        install -d -m 00700 "$DIR" && echo "$DIR"
    )} && eval "$VAR=\$DIR" && echo "$DIR"
}

# lk_cache [-t TTL] COMMAND [ARG...]
#
# Print output from a previous run if possible, otherwise execute the command
# line and cache its output in a transient per-process cache. If -t is set, use
# cached output for up to TTL seconds (default: 300). If TTL is 0, use cached
# output indefinitely.
function lk_cache() {
    local TTL=300 FILE AGE s=/
    [ "${1-}" != -t ] || { TTL=$2 && shift 2; }
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__} &&
        { [ ! -f "${FILE}_dirty" ] || rm -f -- "$FILE"*; } || return
    FILE+=_${FUNCNAME[1]}_$(lk_hash "$@") || return
    if [ -f "$FILE" ] &&
        { [ "$TTL" -eq 0 ] ||
            { AGE=$(lk_file_age "$FILE") &&
                [ "$AGE" -lt "$TTL" ]; }; }; then
        cat "$FILE"
    else
        "$@" >"$FILE" && cat -- "$FILE" || lk_pass rm -f -- "$FILE"
    fi
}

function lk_cache_mark_dirty() {
    local FILE s=/
    FILE=$(_lk_cache_dir)/${BASH_SOURCE[1]//"$s"/__}_dirty || return
    touch "$FILE"
}

# lk_get_outputs_of COMMAND [ARG...]
#
# Execute COMMAND, output Bash-compatible code that sets _STDOUT and _STDERR to
# COMMAND's respective outputs, and exit with COMMAND's exit status.
function lk_get_outputs_of() {
    local SH EXIT_STATUS
    SH=$(
        _LK_CAN_FAIL=1
        _LK_STDOUT=$(lk_mktemp_file) &&
            _LK_STDERR=$(lk_mktemp_file) &&
            lk_delete_on_exit "$_LK_STDOUT" "$_LK_STDERR" || exit
        unset _LK_FD
        "$@" >"$_LK_STDOUT" 2>"$_LK_STDERR" || EXIT_STATUS=$?
        for i in _LK_STDOUT _LK_STDERR; do
            printf 'declare %s=%q\n' "${i#_LK}" "$(cat "${!i}" |
                lk_strip_non_printing)"
        done
        exit "${EXIT_STATUS:-0}"
    ) || EXIT_STATUS=$?
    echo "$SH"
    return "${EXIT_STATUS:-0}"
}

function _lk_lock_check_args() {
    lk_is_linux || lk_command_exists flock || {
        [ "${FUNCNAME[1]-}" = lk_lock_drop ] ||
            lk_tty_warning "File locking is not supported on this platform"
        return 2
    }
    case $# in
    0 | 1)
        set -- LOCK_FILE LOCK_FD "${1-}"
        ;;
    2 | 3)
        set -- "$1" "$2" "${3-}"
        lk_test_many lk_is_identifier "${@:1:2}"
        ;;
    *)
        false
        ;;
    esac || lk_warn "invalid arguments" || return 1
    printf 'set -- %s\n' "$(lk_quote_args "$@")"
}

# lk_lock [-f LOCK_FILE] [-w] [LOCK_FILE_VAR LOCK_FD_VAR] [LOCK_NAME]
function lk_lock() {
    local _LK_FILE _LK_NONBLOCK=1 _LK_SH
    [ "${1-}" != -f ] || { _LK_FILE=${2-} && shift 2 || return; }
    [ "${1-}" != -w ] || { unset _LK_NONBLOCK && shift || return; }
    _LK_SH=$(_lk_lock_check_args "$@") ||
        { [ $? -eq 2 ] && return 0; } || return
    eval "$_LK_SH" || return
    unset "${@:1:2}"
    eval "$1=\${_LK_FILE:-/tmp/\${3:-.\${LK_PATH_PREFIX:-lk-}\$(lk_caller_name)}.lock}" &&
        eval "$2=\$(lk_fd_next)" &&
        eval "exec ${!2}>\"\$$1\"" || return
    flock ${_LK_NONBLOCK+-n} "${!2}" ||
        lk_warn "unable to acquire lock: ${!1}" || return
    lk_trap_add EXIT lk_lock_drop "$@"
}

# lk_lock_drop [LOCK_FILE_VAR LOCK_FD_VAR] [LOCK_NAME]
function lk_lock_drop() {
    local _LK_SH
    _LK_SH=$(_lk_lock_check_args "$@") ||
        { [ $? -eq 2 ] && return 0; } || return
    eval "$_LK_SH" || return
    if [ "${!1:+1}${!2:+1}" = 11 ]; then
        eval "exec ${!2}>&-" || lk_warn "unable to drop lock: ${!1}" || return
        rm -f -- "${!1}" 2>/dev/null || true
    fi
    unset "${@:1:2}"
}

function lk_pv() {
    lk_ignore_SIGINT && lk_log_bypass_stderr pv "$@"
}

function _lk_tee() {
    local PRESERVE
    [[ ! $1 =~ ^-[0-9]+$ ]] || { PRESERVE=${1#-} && shift; }
    lk_ignore_SIGINT && eval exec "$(_lk_log_close_fd ${PRESERVE-})" || return
    exec tee "$@"
}

# lk_log [PREFIX]
#
# Add PREFIX and a microsecond-resolution timestamp to the beginning of each
# line of input.
#
# Example:
#
#     $ echo "Hello, world." | lk_log '!!'
#     !!2021-05-13 18:01:53.860513 +1000 Hello, world.
function lk_log() {
    local PREFIX=${1-}
    lk_ignore_SIGINT && eval exec "$(_lk_log_close_fd)" || return
    PREFIX=${PREFIX//"%"/"%%"} exec perl -pe '$| = 1;
BEGIN {
    use POSIX qw{strftime};
    use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "$ENV{PREFIX}%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );
s/.*\r(.)/\1/;'
}

# lk_log_create_file [-e EXT] [DIR...]
function lk_log_create_file() {
    local OWNER=$UID GROUP EXT CMD LOG_DIRS=() LOG_DIR LOG_PATH
    GROUP=$(id -gn) || return
    [ "${1-}" != -e ] || { EXT=$2 && shift 2; }
    CMD=${_LK_LOG_CMDLINE:-$0}
    [ ! -d "${_LK_INST:-${LK_BASE-}}" ] ||
        [ -z "$(ls -A "${_LK_INST:-$LK_BASE}")" ] ||
        LOG_DIRS=("${_LK_INST:-$LK_BASE}/var/log")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS[@]+"${LOG_DIRS[@]}"}; do
        # Find the first LOG_DIR in which the user can write to LOG_FILE,
        # installing LOG_DIR (world-writable) and LOG_FILE (owner-only) if
        # needed, running commands via sudo only if they fail without it
        [ -d "$LOG_DIR" ] || lk_elevate -f \
            lk_install -d -m 01777 "$LOG_DIR" 2>/dev/null || continue
        LOG_PATH=$LOG_DIR/${_LK_LOG_BASENAME:-${CMD##*/}}-$UID.${EXT:-log}
        if [ -f "$LOG_PATH" ]; then
            [ -w "$LOG_PATH" ] || {
                lk_elevate -f chmod 00600 "$LOG_PATH" || continue
                [ -w "$LOG_PATH" ] ||
                    lk_elevate chown "$OWNER:$GROUP" "$LOG_PATH" || continue
            }
        else
            lk_elevate -f \
                lk_install -m 00600 -o "$OWNER" -g "$GROUP" "$LOG_PATH" ||
                continue
        fi 2>/dev/null
        echo "$LOG_PATH"
        return 0
    done
    false
}

function lk_start_trace() {
    # Don't interfere with an existing trace
    [[ $- != *x* ]] && lk_is_true LK_DEBUG || return 0
    local TRACE_PATH
    TRACE_PATH=${_LK_LOG_TRACE_PATH:-$(lk_log_create_file \
        -e "$(lk_date_ymdhms).trace" /tmp ~)} &&
        exec 4> >(lk_log >"$TRACE_PATH") || return
    if lk_bash_at_least 4 1; then
        BASH_XTRACEFD=4
    else
        # If BASH_XTRACEFD isn't supported, trace all output to stderr and send
        # lk_tty_* to the terminal
        exec 2>&4 &&
            { ! lk_log_is_open || _LK_TRACE_FD=4; } &&
            { [ "${_LK_FD-2}" -ne 2 ] ||
                { exec 3>/dev/tty && export _LK_FD=3; }; }
    fi || lk_warn "unable to open trace file" || return
    set -x
}

function _lk_log_close_fd() {
    local IFS i j=0 SH=()
    unset IFS
    for i in _LK_FD _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD _LK_LOG2_FD; do
        [ -z "${!i-}" ] || [ "${!i}" -lt 3 ] || [ "${!i}" -eq "${1:-0}" ] ||
            SH[j++]="${!i}>&-"
    done
    ((j)) || return 0
    echo "${SH[*]}"
}

# lk_log_start [TEMP_LOG_FILE]
function lk_log_start() {
    local ARG0 HEADER EXT _FILE FILE LOG_FILE OUT_FILE FIFO
    if [ "${LK_NO_LOG-}" = 1 ] || lk_log_is_open ||
        { [[ $- == *i* ]] && ! lk_script_running; }; then
        return
    fi
    ARG0=$(type -p "${_LK_LOG_CMDLINE:-$0}") &&
        ARG0=${ARG0:-${_LK_LOG_CMDLINE+"Bash $(type -t \
            "$_LK_LOG_CMDLINE") $_LK_LOG_CMDLINE"}} || ARG0=
    [ -n "${_LK_LOG_CMDLINE+1}" ] ||
        local _LK_LOG_CMDLINE=("$0" ${_LK_ARGV+"${_LK_ARGV[@]}"})
    _LK_LOG_CMDLINE[0]=${ARG0:-$_LK_LOG_CMDLINE}
    HEADER=$(
        printf '====> %s invoked' "$LK_BOLD$ARG0$LK_RESET"
        ! ((ARGC = ${#_LK_LOG_CMDLINE[@]} - 1)) || {
            printf ' with %s %s:' "$ARGC" \
                "$(lk_plural "$ARGC" argument arguments)"
            for ((i = 1; i <= ARGC; i++)); do
                printf '\n%s%3d%s %q' \
                    "$LK_BOLD" "$i" "$LK_RESET" "${_LK_LOG_CMDLINE[i]}"
            done
        }
    )
    if [[ ${1-} =~ (.+)(\.(log|out))?$ ]]; then
        set -- "${BASH_REMATCH[1]}"
    else
        set --
    fi
    for EXT in log out; do
        if [ -n "${_LK_LOG_FILE-}" ]; then
            if [ "$EXT" = log ]; then
                FILE=$_LK_LOG_FILE
                _lk_log_install_file "$FILE" || return
            else
                FILE=/dev/null
            fi
        elif [ $# -gt 0 ]; then
            _FILE=$1.$EXT
            if FILE=$(lk_log_create_file -e "$EXT"); then
                [ ! -e "$_FILE" ] ||
                    { lk_file_backup -m "$_FILE" "$FILE" &&
                        cat -- "$_FILE" >>"$FILE" &&
                        rm -f -- "$_FILE"; } || return
            else
                FILE=$_FILE
            fi
        else
            FILE=$(lk_log_create_file -e "$EXT" ~ /tmp) ||
                lk_warn "unable to create log file" || return
        fi
        eval "$(lk_upper "$EXT")_FILE=\$FILE"
    done
    FIFO=$(lk_mktemp_dir)/fifo &&
        lk_delete_on_exit "${FIFO%/*}" &&
        mkfifo "$FIFO" || return
    (lk_ignore_SIGINT &&
        LK_EXEC=1 lk_strip_non_printing <"$FIFO" >>"$OUT_FILE") &
    unset _LK_LOG2_FD
    [ -z "${_LK_SECONDARY_LOG_FILE-}" ] || { _LK_LOG2_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG2_FD"'>>"$_LK_SECONDARY_LOG_FILE"' &&
        export _LK_LOG2_FD; } || return
    _LK_TTY_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_OUT_FD>&1" &&
        _LK_TTY_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_ERR_FD>&2" &&
        _LK_LOG_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG_OUT_FD"'> >(lk_log ".." >"$FIFO")' &&
        _LK_LOG_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_LOG_ERR_FD"'> >(lk_log "!!" >"$FIFO")' &&
        _LK_LOG_FD=$(lk_fd_next) && { if [ -z "${_LK_LOG2_FD-}" ]; then
            eval "exec $_LK_LOG_FD"'> >(lk_log >>"$LOG_FILE")'
        else
            eval "exec $_LK_LOG_FD"'> >(lk_log > >(_lk_tee -a "$LOG_FILE" >&"$_LK_LOG2_FD"))'
        fi; } || return
    export _LK_FD _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD
    [ "${_LK_FD-2}" -ne 2 ] || {
        _LK_FD=3
        _LK_FD_LOGGED=1
    }
    lk_log_tty_on
    tee "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD" <<<"$HEADER"
    ! lk_verbose 2 || lk_echoc \
        "Output is being logged to $LK_BOLD$LOG_FILE$LK_RESET" "$LK_GREY" |
        lk_log_to_tty_stdout
    _LK_LOG_FILE_LOG=$LOG_FILE
    _LK_LOG_FILE_OUT=$OUT_FILE
}

function lk_log_is_open() {
    local FD
    for FD in _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD; do
        lk_fd_is_open "${!FD-}" || return
    done
}

# lk_log_close [-r]
#
# Close redirections opened by lk_log_start. If -r is set, reopen them for
# further logging (useful when closing a secondary log file).
function lk_log_close() {
    lk_log_is_open || lk_warn "no output log" || return
    if [ "${1-}" = -r ]; then
        [ -z "${_LK_LOG2_FD-}" ] || {
            eval "exec $_LK_LOG_FD"'> >(lk_log >>"$_LK_LOG_FILE_LOG")' &&
                { ! lk_fd_is_open "$_LK_LOG2_FD" ||
                    eval "exec $_LK_LOG2_FD>&-"; }
        } || return
        unset _LK_LOG2_FD
    else
        CLOSE=()
        [ -z "${_LK_FD_LOGGED-}" ] || CLOSE=(_LK_FD)
        CLOSE+=(
            _LK_LOG_FD
            _LK_LOG_ERR_FD
            _LK_LOG_OUT_FD
            _LK_TTY_ERR_FD
            _LK_TTY_OUT_FD
            _LK_LOG2_FD
        )
        exec >&"$_LK_TTY_OUT_FD" 2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}" &&
            eval "$(for i in "${CLOSE[@]}"; do
                [ -z "${!i-}" ] || printf 'exec %s>&-\n' "${!i-}"
            done)" &&
            unset "${CLOSE[@]}" _LK_{LOG,OUT}_FILE
    fi
}

# lk_log_tty_off -a
function lk_log_tty_off() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
        2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") &&
        { [ "${1-}" != -a ] || [ -z "${_LK_FD_LOGGED-}" ] ||
            eval "exec $_LK_FD"'> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")'; } &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_tty_stdout_off() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
        2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_tty_on() {
    lk_log_is_open || return 0
    exec \
        > >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD") \
        2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") &&
        { [ -z "${_LK_FD_LOGGED-}" ] ||
            eval "exec $_LK_FD"'> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD")'; } &&
        _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_to_file_stdout() {
    lk_log_is_open || lk_warn "no output log" || return
    cat > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")
}

function lk_log_to_file_stderr() {
    lk_log_is_open || lk_warn "no output log" || return
    cat > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
}

function lk_log_to_tty_stdout() {
    if lk_log_is_open; then
        cat >&"$_LK_TTY_OUT_FD"
    else
        cat
    fi
}

function lk_log_to_tty_stderr() {
    if lk_log_is_open; then
        cat >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
    else
        cat >&2
    fi
}

function _lk_log_bypass() {
    (
        unset "${!_LK_LOG_@}"
        "$@"
    )
}

# lk_log_bypass [-o|-e|-t|-to|-te|-n] COMMAND [ARG...]
#
# Run the given command with stdout and stderr redirected to the console,
# bypassing output log files. If -o or -e is set, only redirect stdout or stderr
# respectively. If -t is set, run the command with stdout and stderr redirected
# to output log files, bypassing the console. If -to or -te are set, only
# redirect stdout or stderr to output logs. If -n is set, run COMMAND with the
# same redirections lk_log_tty_on would apply.
function lk_log_bypass() {
    local ARG=${1-} _LK_CAN_FAIL=1
    [[ ! $ARG =~ ^-(t?[oe]|n)$ ]] || shift
    lk_log_is_open || {
        "$@"
        return
    }
    case "$ARG" in
    -to)
        _lk_log_bypass "$@" \
            > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD")
        ;;
    -te)
        _lk_log_bypass "$@" \
            2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
        ;;
    -t)
        _lk_log_bypass "$@" \
            > >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") \
            2> >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD")
        ;;
    -o)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD"
        ;;
    -e)
        _lk_log_bypass "$@" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    -n)
        _lk_log_bypass "$@" \
            > >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_OUT_FD") >&"$_LK_TTY_OUT_FD") \
            2> >(_lk_tee >(_lk_tee -"$_LK_LOG_FD" "/dev/fd/$_LK_LOG_FD" >&"$_LK_LOG_ERR_FD") >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}")
        ;;
    *)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    esac
}

function lk_log_bypass_stdout() {
    lk_log_bypass -o "$@"
}

function lk_log_bypass_stderr() {
    lk_log_bypass -e "$@"
}

function lk_log_bypass_tty() {
    lk_log_bypass -t "$@"
}

function lk_log_bypass_tty_stdout() {
    lk_log_bypass -to "$@"
}

function lk_log_bypass_tty_stderr() {
    lk_log_bypass -te "$@"
}

function lk_log_no_bypass() {
    lk_log_bypass -n "$@"
}

# lk_echoc [-n] [MESSAGE [COLOUR]]
function lk_echoc() {
    local NEWLINE MESSAGE
    [ "${1-}" != -n ] || { NEWLINE=0 && shift; }
    MESSAGE=${1-}
    [ $# -le 1 ] || [ -z "$LK_RESET" ] ||
        MESSAGE=$2${MESSAGE//"$LK_RESET"/$LK_RESET$2}$LK_RESET
    echo ${NEWLINE:+-n} "$MESSAGE"
}

function lk_readline_format() {
    local STRING=$1 REGEX
    eval "$(lk_get_regex CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX)"
    for REGEX in CONTROL_SEQUENCE_REGEX ESCAPE_SEQUENCE_REGEX; do
        while [[ $STRING =~ ((.*)(^|[^$'\x01']))(${!REGEX})+(.*) ]]; do
            STRING=${BASH_REMATCH[1]}$'\x01'${BASH_REMATCH[4]}$'\x02'${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
        done
    done
    echo "$STRING"
}

function lk_diff() { (
    _LK_CAN_FAIL=1
    [ $# -eq 2 ] || lk_usage "Usage: $FUNCNAME FILE1 FILE2" || exit
    for i in 1 2; do
        if [ -p "${!i}" ] || [ -n "${_LK_DIFF_SED_SCRIPT:+1}" ]; then
            FILE=$(lk_mktemp_file) && lk_delete_on_exit "$FILE" &&
                lk_maybe_sudo sed -E \
                    "${_LK_DIFF_SED_SCRIPT-}" \
                    "${!i}" >"$FILE" || exit
            set -- "${@:1:i-1}" "$FILE" "${@:i+1}"
        fi
    done
    # Use the same escape sequences as icdiff, which ignores TERM
    BLUE=$'\E[34m'
    GREEN=$'\E[1;32m'
    RESET=$'\E[m'
    if lk_command_exists icdiff; then
        # Don't use icdiff if FILE1 is empty
        if lk_maybe_sudo test ! -s "$1" -a -s "$2"; then
            echo "$BLUE$2$RESET"
            printf '%s' "$GREEN"
            # Add $RESET to the last line
            lk_maybe_sudo cat "$2" | awk -v "r=$RESET" \
                's { print l } { s = 1; l = $0 } END { print l r }'
            false
        else
            printf '%s' "$LK_RESET"
            ! lk_require_output lk_maybe_sudo icdiff -U2 --no-headers \
                ${_LK_TTY_INDENT:+--cols=$(($(
                    lk_tty_columns
                ) - 2 * (_LK_TTY_INDENT + 2)))} "$@"
        fi
    elif lk_command_exists git; then
        lk_maybe_sudo \
            git diff --no-index --no-prefix --no-ext-diff --color -U3 "$@"
    else
        DIFF_VER=$(lk_diff_version 2>/dev/null) &&
            lk_version_at_least "$DIFF_VER" 3.4 || unset DIFF_VER
        lk_maybe_sudo gnu_diff ${DIFF_VER+--color=always} -U3 "$@"
    fi && echo "${BLUE}Files are identical${_LK_DIFF_SED_SCRIPT:+ or have hidden differences}$RESET"
); }

function lk_maybe_trace() {
    local OUTPUT COMMAND
    [ "${1-}" != -o ] || { OUTPUT=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no command" || return
    COMMAND=("$@")
    [[ $- != *x* ]] ||
        COMMAND=(env
            ${BASH_XTRACEFD:+BASH_XTRACEFD=$BASH_XTRACEFD}
            SHELLOPTS=xtrace
            "$@")
    ! lk_will_sudo || {
        # See: https://bugzilla.sudo.ws/show_bug.cgi?id=950
        local SUDO_MIN=3 VER
        ! VER=$(sudo -V | awk 'NR == 1 { print $NF }') ||
            printf '%s\n' "$VER" 1.8.9 1.8.32 1.9.0 1.9.4p1 | sort -V |
            awk -v "v=$VER" '$0 == v { l = NR } END { exit 1 - l % 2 }' ||
            SUDO_MIN=4
        COMMAND=(
            sudo -H
            -C "$(($(set +u && printf '%s\n' $((SUDO_MIN - 1)) \
                $((_LK_FD ? _LK_FD : 2)) $((BASH_XTRACEFD)) $((_LK_TRACE_FD)) \
                $((_LK_TTY_OUT_FD)) $((_LK_TTY_ERR_FD)) \
                $((_LK_LOG_OUT_FD)) $((_LK_LOG_ERR_FD)) \
                $((_LK_LOG_FD)) $((_LK_LOG2_FD)) | sort -n | tail -n1) + 1))"
            "${COMMAND[@]}"
        )
    }
    # Remove "env" from sudo command
    [[ $- != *x* ]] || ! lk_will_sudo || unset "COMMAND[4]"
    ! lk_is_true OUTPUT ||
        COMMAND=(lk_quote_args "${COMMAND[@]}")
    "${COMMAND[@]}"
}

# lk_clip
#
# Copy input to the user's clipboard if possible, otherwise print it out.
function lk_clip() {
    local OUTPUT COMMAND LINES MESSAGE DISPLAY_LINES=${LK_CLIP_LINES:-5}
    [ ! -t 0 ] || lk_warn "no input" || return
    OUTPUT=$(cat && printf .) && OUTPUT=${OUTPUT%.}
    if COMMAND=$(lk_first_command \
        "xclip -selection clipboard" \
        pbcopy) &&
        echo -n "$OUTPUT" | $COMMAND &>/dev/null; then
        LINES=$(wc -l <<<"$OUTPUT" | tr -d ' ')
        [ "$LINES" -le "$DISPLAY_LINES" ] || {
            OUTPUT=$(head -n$((DISPLAY_LINES - 1)) <<<"$OUTPUT" &&
                echo "$LK_BOLD$LK_MAGENTA...$LK_RESET")
            MESSAGE="$LINES lines copied"
        }
        lk_tty_print "${MESSAGE:-Copied} to clipboard:" \
            $'\n'"$LK_GREEN$OUTPUT$LK_RESET" "$LK_MAGENTA"
    else
        lk_tty_error "Unable to copy input to clipboard"
        echo -n "$OUTPUT"
    fi
}

# lk_paste
#
# Paste the user's clipboard to output, if possible.
function lk_paste() {
    local COMMAND
    COMMAND=$(lk_first_command \
        "xclip -selection clipboard -out" \
        pbpaste) &&
        $COMMAND ||
        lk_tty_error "Unable to paste clipboard to output"
}

# lk_file_add_suffix FILENAME SUFFIX
#
# Add SUFFIX to FILENAME without changing its extension.
function lk_file_add_suffix() {
    local EXT
    [[ $1 =~ [^/]((\.tar)?\.[-a-zA-Z0-9_]+/*|/*)$ ]] &&
        EXT=${BASH_REMATCH[1]} ||
        EXT=
    echo "${1%"$EXT"}$2$EXT"
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
        printf 'declare %s=%q\n' "$PART" "$VALUE"
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
    [ "${1-}" != -s ] || { SERVER_NAMES=1 && shift; }
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
            lk_delete_on_exit "$DOWNLOAD_DIR" &&
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
        COMMANDS+=("$(lk_quote_arr CURL_COMMAND DOWNLOAD_ARGS)")
    done < <([ $# -gt 0 ] &&
        lk_echo_args "$@" ||
        cat)
    [ ${#COMMAND_ARGS[@]} -eq 0 ] || {
        CURL_COMMAND=("${CURL_COMMAND[@]//--remote-name/--remote-name-all}")
        ! lk_version_at_least "$CURL_VERSION" 7.66.0 ||
            CURL_COMMAND+=(--parallel)
        ! lk_version_at_least "$CURL_VERSION" 7.68.0 ||
            CURL_COMMAND+=(--parallel-immediate)
        COMMANDS+=("$(lk_quote_arr CURL_COMMAND COMMAND_ARGS)")
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
        --retry 2
        --show-error
        --silent
    )
    curl ${CURL_OPTIONS[@]+"${CURL_OPTIONS[@]}"} "$@"
}

function lk_maybe_drop() {
    if ! lk_root; then
        "$@"
    elif lk_is_linux; then
        runuser -u nobody -- "$@"
    else
        sudo -u nobody -- "$@"
    fi
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
    local COMMAND=${1-} USERNAME=${2-} ERROR
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

function lk_me() {
    lk_maybe_sudo id -un
}

# lk_rm [-v] [--] [FILE...]
function lk_rm() {
    local v=
    [ "${1-}" != -v ] || { v=v && shift; }
    [ "${1-}" != -- ] || shift
    [ $# -gt 0 ] || return 0
    if lk_command_exists trash-put; then
        lk_maybe_sudo trash-put -f"$v" -- "$@"
    elif lk_command_exists trash; then
        local DELETE=()
        while [ $# -gt 0 ]; do
            lk_maybe_sudo test -e "$1" &&
                DELETE[${#DELETE[@]}]=$1 || true
            shift
        done
        [ -z "${DELETE+1}" ] ||
            lk_maybe_sudo trash -F"$v" -- "${DELETE[@]}"
    else
        lk_file_backup -m "$@" &&
            lk_maybe_sudo rm -Rf"$v" -- "$@"
    fi
}

# - lk_install [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
# - lk_install -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY...
#
# Create or set permissions and ownership on each FILE or DIRECTORY.
function lk_install() {
    local OPTIND OPTARG OPT LK_USAGE _USER LK_SUDO=${LK_SUDO-} \
        DIR MODE OWNER GROUP VERBOSE DEST STAT REGEX ARGS=()
    LK_USAGE="\
Usage: $FUNCNAME [-m MODE] [-o OWNER] [-g GROUP] [-v] FILE...
   or: $FUNCNAME -d [-m MODE] [-o OWNER] [-g GROUP] [-v] DIRECTORY..."
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
    [ -z "${OWNER-}" ] &&
        { [ -z "${GROUP-}" ] || lk_user_in_group "$GROUP"; } ||
        LK_SUDO=1
    if lk_is_true DIR; then
        lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} "$@"
    else
        for DEST in "$@"; do
            if lk_maybe_sudo test ! -e "$DEST" 2>/dev/null; then
                lk_maybe_sudo install ${ARGS[@]+"${ARGS[@]}"} /dev/null "$DEST"
            else
                STAT=$(lk_file_security "$DEST" 2>/dev/null) || return
                [ -z "${MODE-}" ] ||
                    { [[ $MODE =~ ^0*([0-7]+)$ ]] &&
                        REGEX=" 0*${BASH_REMATCH[1]}\$" &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_maybe_sudo chmod \
                        ${VERBOSE:+-v} "$MODE" "$DEST" ||
                    return
                [ -z "${OWNER-}${GROUP-}" ] ||
                    { REGEX='[-a-z0-9_]+\$?' &&
                        REGEX="^${OWNER:-$REGEX}:${GROUP:-$REGEX} " &&
                        [[ $STAT =~ $REGEX ]]; } ||
                    lk_elevate chown \
                        ${VERBOSE:+-v} "${OWNER-}${GROUP:+:$GROUP}" "$DEST" ||
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
    [ "${1-}" != -f ] || { NO_ORIG=1 && shift; }
    [ $# -eq 2 ] || lk_usage "\
Usage: $FUNCNAME [-f] TARGET LINK"
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
            lk_rm ${v:+"-$v"} -- "$LINK" || return
        fi
    elif lk_maybe_sudo test ! -d "$LINK_DIR"; then
        lk_maybe_sudo \
            install -d"$v" -- "$LINK_DIR" || return
    fi
    lk_maybe_sudo ln -s"$v" -- "$TARGET" "$LINK" &&
        LK_SYMLINK_NO_CHANGE=0
}

function lk_user_exists() {
    id "$1" &>/dev/null || return
}

function lk_user_home() {
    lk_expand_path "~${1-}"
}

# lk_user_groups [USER]
function lk_user_groups() {
    id -Gn ${1+"$1"} | tr -s '[:blank:]' '\n'
}

# lk_user_in_group GROUP [USER]
function lk_user_in_group() {
    lk_user_groups ${2+"$2"} | grep -Fx "$1" >/dev/null
}

# lk_dir_parents [-u UNTIL] DIR...
function lk_dir_parents() {
    local UNTIL=/
    [ "${1-}" != -u ] || {
        UNTIL=$(lk_realpath "$2") || return
        shift 2
    }
    lk_realpath "$@" | awk -v "u=$UNTIL" 'BEGIN {
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
    _LK_TEST="(${1//{\}/\$_LK_VAL})"
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

# lk_remove_missing_or_empty ARRAY
#
# Remove paths to missing or empty files from ARRAY.
function lk_remove_missing_or_empty() {
    lk_remove_false 'lk_maybe_sudo test -s "{}" -o -L "{}"' "$1"
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
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 0 "$@" || return "$EXIT_STATUS"
    [ -n "${1-}" ] || lk_warn "no path" || return
    _PATH=$1
    SHOPT=$(shopt -p nullglob) || true
    shopt -s nullglob
    DELIM=${LK_Z:+'\0'}
    # If the path is double- or single-quoted, remove enclosing quotes and
    # unescape
    if [[ $_PATH =~ ^\"(.*)\"$ ]]; then
        _PATH=${BASH_REMATCH[1]//'\"'/'"'}
    elif [[ $_PATH =~ ^\'(.*)\'$ ]]; then
        _PATH=${BASH_REMATCH[1]//"\\'"/"'"}
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
        _PATH=$(lk_double_quote -f "$_PATH")
        _PATH=${_PATH:1:${#_PATH}-2}
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

function lk_basename() {
    { [ $# -gt 0 ] && lk_echo_args "$@" || cat; } |
        sed -E 's/.*\/([^/]+)\/*$/\1/'
}

function lk_filter() {
    local LK_Z=${LK_Z-} EXIT_STATUS TEST DELIM
    [ "${1-}" != -z ] || { LK_Z=1 && shift; }
    ! _lk_maybe_xargs 1 "$@" || return "$EXIT_STATUS"
    TEST=$1
    [ -n "$TEST" ] || lk_warn "no test command" || return
    shift
    DELIM=${LK_Z:+'\0'}
    ! eval "($TEST \"\$1\")" || printf "%s${DELIM:-\\n}" "$1"
}

function lk_json_from_xml_schema() {
    [ $# -gt 0 ] && [ $# -le 2 ] && lk_files_exist "$@" || lk_usage "\
Usage: $FUNCNAME XSD_FILE [XML_FILE]" || return
    "$LK_BASE/lib/python/json_from_xml_schema.py" "$@"
}

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
    printf '%s' "${PASSWORD:0:LENGTH}"
}

# lk_base64 [-d]
function lk_base64() {
    local DECODE
    [ "${1-}" != -d ] || DECODE=1
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

function _lk_file_sort() {
    sort "${@:--n}" | sed -E 's/^[0-9]+ ://'
}

if ! lk_is_macos; then
    function lk_file_sort_by_date() {
        lk_maybe_sudo stat -c '%Y :%n' -- "$@" | _lk_file_sort
    }
    function lk_file_modified() {
        lk_maybe_sudo stat -c '%Y' -- "$@"
    }
    function lk_file_owner() {
        lk_maybe_sudo stat -c '%U' -- "$@"
    }
    function lk_file_group() {
        lk_maybe_sudo stat -c '%G' -- "$@"
    }
    function lk_file_mode() {
        lk_maybe_sudo stat -c '%04a' -- "$@"
    }
    function lk_file_security() {
        lk_maybe_sudo stat -c '%U:%G %04a' -- "$@"
    }
    function lk_full_name() {
        getent passwd "${1:-$UID}" | cut -d: -f5 | cut -d, -f1
    }
else
    # lk_dscl_read [PATH] KEY
    function lk_dscl_read() {
        [ $# -ne 1 ] || set -- "/Users/$USER" "$1"
        [ $# -eq 2 ] || lk_warn "invalid arguments" || return
        dscl . -read "$@" |
            sed -E "1s/^$(lk_sed_escape "$2")://;s/^ //;/^\$/d"
    }
    function lk_full_name() {
        lk_dscl_read RealName
    }
    function lk_file_sort_by_date() {
        lk_maybe_sudo stat -t '%s' -f '%Sm :%N' -- "$@" | _lk_file_sort
    }
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

if ! lk_is_macos; then
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
    [ "${LK_FILE_KEEP_ORIGINAL:-1}" -eq 1 ] || return 0
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

# lk_file_backup [-m] [FILE...]
#
# Copy each FILE to FILE.lk-bak-TIMESTAMP, where TIMESTAMP is the file's last
# modified time in UTC (e.g. 20201202T095515Z). If -m is set, copy FILE to
# LK_BASE/var/backup if elevated, or ~/.lk-platform/backup if not elevated.
function lk_file_backup() {
    local MOVE=${LK_FILE_BACKUP_MOVE-} FILE OWNER OWNER_HOME DEST GROUP \
        MODIFIED SUFFIX TZ=UTC s vv=
    [ "${1-}" != -m ] || { MOVE=1 && shift; }
    ! lk_verbose 2 || vv=v
    export TZ
    while [ $# -gt 0 ]; do
        if lk_maybe_sudo test -e "$1"; then
            lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
            lk_maybe_sudo test -s "$1" || return 0
            ! lk_is_true MOVE || {
                FILE=$(lk_realpath "$1") || return
                {
                    OWNER=$(lk_file_owner "$FILE") &&
                        OWNER_HOME=$(lk_expand_path "~$OWNER") &&
                        OWNER_HOME=$(lk_realpath "$OWNER_HOME")
                } 2>/dev/null || OWNER_HOME=
                if [ -d "${_LK_INST:-${LK_BASE-}}" ] &&
                    lk_will_elevate && [ "${FILE#"$OWNER_HOME"}" = "$FILE" ]; then
                    lk_install -d \
                        -m "$([ -g "${_LK_INST:-$LK_BASE}" ] &&
                            echo 02775 ||
                            echo 00755)" \
                        "${_LK_INST:-$LK_BASE}/var" || return
                    DEST=${_LK_INST:-$LK_BASE}/var/backup
                    unset OWNER
                elif lk_will_elevate; then
                    DEST=$OWNER_HOME/.lk-platform/backup
                    GROUP=$(id -gn "$OWNER") &&
                        lk_install -d -m 00755 -o "$OWNER" -g "$GROUP" \
                            "$OWNER_HOME/.lk-platform" || return
                else
                    DEST=~/.lk-platform/backup
                    unset OWNER
                fi
                lk_install -d -m 00700 ${OWNER:+-o "$OWNER" -g "$GROUP"} \
                    "$DEST" || return
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
    [ "${1-}" != -n ] || { NO_COPY=1 && shift; }
    DIR=${1%/*}
    [ "$DIR" != "$1" ] || DIR=$PWD
    ! lk_verbose 2 || vv=v
    TEMP=$(lk_maybe_sudo mktemp -- "${DIR%/}/.${1##*/}.XXXXXXXXXX") || return
    ! lk_maybe_sudo test -f "$1" ||
        if lk_is_true NO_COPY; then
            local OPT
            lk_is_macos || OPT=--
            MODE=$(lk_file_mode "$1") &&
                lk_maybe_sudo chmod "$(lk_pad_zero 5 "$MODE")" \
                    ${OPT:+"$OPT"} "$TEMP"
        else
            lk_maybe_sudo cp -aL"$vv" -- "$1" "$TEMP"
        fi >&2 || return
    echo "$TEMP"
}

# lk_file_replace [OPTIONS] TARGET [CONTENT]
function lk_file_replace() {
    local OPTIND OPTARG OPT LK_USAGE IFS SOURCE= IGNORE= FILTER= ASK= \
        LINK=1 BACKUP=${LK_FILE_BACKUP_TAKE-} MOVE=${LK_FILE_BACKUP_MOVE-} \
        NEW=1 VERB=Created CONTENT PREVIOUS TEMP vv=
    unset IFS PREVIOUS
    LK_USAGE="\
Usage: $FUNCNAME [OPTIONS] TARGET [CONTENT]

If TARGET differs from input or CONTENT, replace TARGET.

Options:
  -f SOURCE     read CONTENT from SOURCE
  -i PATTERN    ignore lines matching the regular expression when comparing
  -s SCRIPT     filter lines through \`sed -E SCRIPT\` when comparing
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
            TEMP=$(lk_realpath "$1") || return
            set -- "$TEMP"
        }
        lk_maybe_sudo test -f "$1" || lk_warn "not a file: $1" || return
        ! lk_maybe_sudo test -s "$1" || unset NEW VERB
        lk_maybe_sudo test -L "$1" || ! diff \
            <(TARGET=$1 _lk_maybe_filter "$IGNORE" "$FILTER" \
                lk_maybe_sudo cat '"$TARGET"') \
            <([ -z "${CONTENT:+1}" ] || _lk_maybe_filter "$IGNORE" "$FILTER" \
                echo "\"\${CONTENT%\$'\\n'}\"") >/dev/null || {
            ! lk_verbose 2 || lk_tty_detail "Not changed:" "$1"
            return 0
        }
        ! lk_is_true ASK || lk_is_true NEW || {
            lk_tty_diff "$1" "" <<<"${CONTENT%$'\n'}" || return
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
        { [ -z "${CONTENT:+1}" ] || echo "${CONTENT%$'\n'}"; } |
        lk_maybe_sudo tee "$TEMP" >/dev/null &&
        lk_maybe_sudo mv -f"$vv" "$TEMP" "$1" &&
        LK_FILE_REPLACE_NO_CHANGE=0 || return
    ! lk_verbose || {
        if lk_is_true LK_FILE_NO_DIFF || lk_is_true ASK; then
            lk_tty_detail "${VERB:-Updated}:" "$1"
        elif [ -n "${PREVIOUS+1}" ]; then
            echo -n "$PREVIOUS" | lk_tty_diff_detail "" "$1"
        else
            lk_tty_file_detail "$1"
        fi
    }
}

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
}

# lk_nohup COMMAND [ARG...]
function lk_nohup() { (
    _LK_CAN_FAIL=1
    trap "" SIGHUP SIGINT SIGTERM
    set -m
    OUT_FILE=$(TMPDIR=$(lk_first_existing "$LK_BASE/var/log" ~ /tmp) &&
        _LK_MKTEMP_EXT=.nohup.out lk_mktemp_file) &&
        OUT_FD=$(lk_fd_next) &&
        eval "exec $OUT_FD"'>"$OUT_FILE"' || return
    ! lk_verbose || lk_tty_print "Redirecting output to" "$OUT_FILE"
    if lk_log_is_open; then
        TTY_OUT_FD=$_LK_TTY_OUT_FD &&
            TTY_ERR_FD=$_LK_TTY_ERR_FD &&
            _LK_TTY_OUT_FD=$OUT_FD &&
            _LK_TTY_ERR_FD=$OUT_FD &&
            ${_LK_LOG_TTY_LAST:-lk_log_tty_on} &&
            exec </dev/null
    else
        TTY_OUT_FD=$(lk_fd_next) &&
            eval "exec $TTY_OUT_FD>&1" &&
            TTY_ERR_FD=$(lk_fd_next) &&
            eval "exec $TTY_ERR_FD>&2" &&
            exec >&"$OUT_FD" 2>&1 </dev/null
    fi || return
    (trap - SIGHUP SIGINT SIGTERM &&
        exec tail -fn+1 "$OUT_FILE") >&"$TTY_OUT_FD" 2>&"$TTY_ERR_FD" &
    lk_kill_on_exit $!
    "$@" &
    wait $! 2>/dev/null
); }

function lk_ignore_SIGINT() {
    trap "" SIGINT
}

function lk_propagate_SIGINT() {
    local PGID
    PGID=$(($(ps -o pgid= $$))) &&
        trap - SIGINT &&
        kill -SIGINT -- -"$PGID"
}

function _lk_exit_trap() {
    local STATUS=$?
    [ $STATUS -eq 0 ] || [ "${_LK_CAN_FAIL-}" = 1 ] ||
        [[ ${FUNCNAME[1]-} =~ ^_?lk_(die|usage)$ ]] ||
        { [[ $- == *i* ]] && [ $BASH_SUBSHELL -eq 0 ]; } ||
        lk_tty_error \
            "$(LK_VERBOSE=1 \
                _lk_caller "${_LK_ERR_TRAP_CALLER:-$1}"): unhandled error" \
            "$(lk_stack_trace \
                $((1 - ${_LK_STACK_DEPTH:-0})) \
                "$([ "${LK_NO_STACK_TRACE-}" != 1 ] || echo 1)" \
                "${_LK_ERR_TRAP_CALLER-}")"
}

function _lk_err_trap() {
    _LK_ERR_TRAP_CALLER=$1
}

set -o pipefail

lk_trap_add EXIT '_lk_exit_trap "$LINENO ${FUNCNAME-} ${BASH_SOURCE-}"'
lk_trap_add ERR '_lk_err_trap "$LINENO ${FUNCNAME-} ${BASH_SOURCE-}"'

if lk_is_true LK_TTY_NO_COLOUR; then
    declare \
        LK_BLACK= \
        LK_RED= \
        LK_GREEN= \
        LK_YELLOW= \
        LK_BLUE= \
        LK_MAGENTA= \
        LK_CYAN= \
        LK_WHITE= \
        LK_GREY= \
        LK_BLACK_BG= \
        LK_RED_BG= \
        LK_GREEN_BG= \
        LK_YELLOW_BG= \
        LK_BLUE_BG= \
        LK_MAGENTA_BG= \
        LK_CYAN_BG= \
        LK_WHITE_BG= \
        LK_GREY_BG= \
        LK_BOLD= \
        LK_DIM= \
        LK_UNDIM= \
        LK_RESET=
else
    # See: `man 4 console_codes`
    declare \
        LK_BLACK=$'\E[30m' \
        LK_RED=$'\E[31m' \
        LK_GREEN=$'\E[32m' \
        LK_YELLOW=$'\E[33m' \
        LK_BLUE=$'\E[34m' \
        LK_MAGENTA=$'\E[35m' \
        LK_CYAN=$'\E[36m' \
        LK_WHITE=$'\E[37m' \
        LK_GREY=$'\E[90m' \
        LK_BLACK_BG=$'\E[40m' \
        LK_RED_BG=$'\E[41m' \
        LK_GREEN_BG=$'\E[42m' \
        LK_YELLOW_BG=$'\E[43m' \
        LK_BLUE_BG=$'\E[44m' \
        LK_MAGENTA_BG=$'\E[45m' \
        LK_CYAN_BG=$'\E[46m' \
        LK_WHITE_BG=$'\E[47m' \
        LK_GREY_BG=$'\E[100m' \
        LK_BOLD=$'\E[1m' \
        LK_DIM=$'\E[2m' \
        LK_UNDIM=$'\E[22m' \
        LK_RESET=$'\E[m'

    case "${TERM-}" in
    '' | dumb | unknown)
        [ -z "${TERM+1}" ] || unset TERM
        ;;
    linux | vt220 | xterm-*color) ;;
    *)
        eval "$(lk_get_colours)"
        ;;
    esac
fi

_LK_COLOUR=$LK_CYAN
_LK_ALT_COLOUR=$LK_YELLOW
_LK_SUCCESS_COLOUR=$LK_GREEN
_LK_WARNING_COLOUR=$LK_YELLOW
_LK_ERROR_COLOUR=$LK_RED

true || {
    env
    md5
    md5sum
    pbcopy
    pbpaste
    sha256sum
    shasum
    xclip
    xxh32sum
    xxh64sum
    xxh128sum
    xxhsum
}

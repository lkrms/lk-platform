#!/bin/bash

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
        lk_sudo sed -i"${1-}" "${@:2}"
    else
        lk_sudo sed -i "$@"
    fi
}

# lk_unbuffer [exec] COMMAND [ARG...]
#
# Run COMMAND with unbuffered input and line-buffered output (if supported by
# the command and platform).
function lk_unbuffer() {
    [ "$1" != exec ] || { local LK_EXEC=1 && shift; }
    case "$1" in
    sed | gsed | gnu_sed)
        set -- "$1" -u "${@:2}"
        ;;
    grep | ggrep | gnu_grep)
        set -- "$1" --line-buffered "${@:2}"
        ;;
    *)
        if [ "$1" = tr ] && lk_is_macos; then
            set -- "$1" -u "${@:2}"
        else
            # TODO: reinstate unbuffer after resolving LF -> CRLF issue
            case "$(lk_command_first stdbuf)" in
            stdbuf)
                set -- stdbuf -i0 -oL -eL "$@"
                ;;
            unbuffer)
                set -- unbuffer -p "$@"
                ;;
            esac
        fi
        ;;
    esac
    lk_sudo "$@"
}

#### Reviewed: 2021-09-06

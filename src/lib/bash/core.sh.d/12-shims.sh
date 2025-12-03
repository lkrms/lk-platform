#!/usr/bin/env bash

# lk_mapfile [-z] ARRAY [FILE]
#
# Read lines from FILE or input into ARRAY. If -z is set, input is
# NUL-delimited.
function lk_mapfile() {
    local _ARGS=()
    [ "${1-}" != -z ] || { _ARGS=(-d '') && shift; }
    [ -n "${2+1}" ] || set -- "$1" /dev/stdin
    [ -r "$2" ] || lk_err "not readable: $2" || return
    if lk_bash_is 4 4 ||
        { [ -z "${_ARGS+1}" ] && lk_bash_is 4 0; }; then
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
    lk_bash_is 4 ||
        BASHPID=$(exec sh -c 'echo "$PPID"')
}

# lk_sed_i SUFFIX SED_ARG...
#
# Run `sed` with the correct arguments to edit files in-place on the detected
# platform.
function lk_sed_i() {
    if ! lk_system_is_macos; then
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
    if lk_has realpath; then
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
    sed)
        if lk_system_is_macos; then
            set -- "$CMD" -l "$@"
        else
            set -- "$CMD" -u "$@"
        fi
        ;;
    gsed | gnu_sed)
        set -- "$CMD" -u "$@"
        ;;
    grep | ggrep | gnu_grep)
        set -- "$CMD" --line-buffered "$@"
        ;;
    *)
        if [ "$CMD" = tr ] && lk_system_is_macos; then
            set -- "$CMD" -u "$@"
        else
            # TODO: reinstate unbuffer after resolving LF -> CRLF issue
            case "$(lk_runnable stdbuf)" in
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

#### Reviewed: 2021-09-06

#!/usr/bin/env bash

# lk_log_start [TEMP_LOG_FILE]
function lk_log_start() {
    [[ -z ${_LK_NO_LOG-} ]] &&
        ! lk_log_is_open && lk_script_running || return 0
    local ARG0 HEADER FILE
    ARG0=$(type -p "${LK_LOG_CMDLINE:-$0}") &&
        ARG0=${ARG0:-${LK_LOG_CMDLINE+"Bash $(type -t "$LK_LOG_CMDLINE") $LK_LOG_CMDLINE"}} ||
        ARG0=
    [[ -n ${LK_LOG_CMDLINE+1} ]] ||
        local LK_LOG_CMDLINE=("$0" ${_LK_ARGV+"${_LK_ARGV[@]}"})
    LK_LOG_CMDLINE[0]=${ARG0:-$LK_LOG_CMDLINE}
    HEADER=$(
        printf '====> %s invoked' "$0"
        [[ $0 == "$LK_LOG_CMDLINE" ]] ||
            printf " as '%s'" "$LK_LOG_CMDLINE"
        ! ((ARGC = ${#LK_LOG_CMDLINE[@]} - 1)) || {
            printf ' with %s %s:' "$ARGC" "$(lk_plural "$ARGC" argument)"
            for ((i = 1; i <= ARGC; i++)); do
                printf '\n%3d %q' "$i" "${LK_LOG_CMDLINE[i]}"
            done
        }
    )
    if [[ -n ${LK_LOG_FILE:+1} ]]; then
        FILE=$LK_LOG_FILE
        _lk_log_install_file "$FILE" || return
    elif (($#)); then
        local _FILE=${1%.out}
        _FILE=${1%.log}.log
        if FILE=$(lk_log_create_file); then
            if [[ -e $_FILE ]]; then
                cat -- "$_FILE" >>"$FILE" &&
                    rm -f -- "$_FILE" || return
            fi
        else
            FILE=$_FILE
        fi
    else
        FILE=$(lk_log_create_file ~ /tmp) ||
            lk_warn "unable to create log file" || return
    fi
    lk_log_migrate_legacy "$FILE" ||
        lk_warn "unable to migrate legacy log file: $FILE" || return
    _LK_TTY_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_OUT_FD>&1" &&
        _LK_TTY_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_ERR_FD>&2" &&
        _LK_LOG_FD=$(lk_fd_next) &&
        if [[ -z ${LK_LOG_SECONDARY_FILE:+1} ]]; then
            eval "exec $_LK_LOG_FD> >(lk_log >>\"\$FILE\")"
        else
            eval "exec $_LK_LOG_FD> >(lk_log | lk_tee -a \"\$LK_LOG_SECONDARY_FILE\" >>\"\$FILE\")"
        fi || return
    ((${_LK_FD-2} != 2)) || {
        _LK_FD=3
        _LK_FD_LOGGED=1
    }
    lk_log_tty_on
    cat <<<"$HEADER" >"/dev/fd/$_LK_LOG_FD"
    ! lk_verbose 2 || _LK_FD=$_LK_TTY_OUT_FD lk_tty_log "Output log:" "$FILE"
    _LK_LOG_FILE=$FILE
}

# lk_log_close [-r]
#
# Close redirections opened by lk_log_start. If -r is set, reopen them for
# further logging (useful when closing a secondary log file).
function lk_log_close() {
    lk_log_is_open || return 0
    if [[ ${1-} == -r ]]; then
        [[ -z ${LK_LOG_SECONDARY_FILE:+1} ]] ||
            eval "exec $_LK_LOG_FD> >(lk_log >>\"\$_LK_LOG_FILE\")"
        return
    fi
    local FD
    exec \
        >&"$_LK_TTY_OUT_FD" \
        2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}" || return
    for FD in ${_LK_FD_LOGGED:+_LK_FD} _LK_LOG_FD _LK_TTY_ERR_FD _LK_TTY_OUT_FD; do
        [[ -n ${!FD-} ]] || continue
        eval "exec ${!FD}>&-" && unset "$FD" || return
    done
    unset _LK_FD_LOGGED
}

# lk_log_create_file [DIR...]
#
# Find the first DIR in which the user can write to a log file, installing the
# directory (world-writable) and log file (owner-only) if needed, then print the
# pathname of the log file.
#
# $LK_BASE/var/log is always tried first.
function lk_log_create_file() {
    local CMD LOG_DIRS=() LOG_DIR LOG_PATH
    CMD=${LK_LOG_CMDLINE:-$0}
    [[ ! -d ${LK_BASE-} ]] ||
        lk_file_is_empty_dir "$LK_BASE" ||
        LOG_DIRS=("$LK_BASE/var/log")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS+"${LOG_DIRS[@]}"}; do
        LOG_PATH=$LOG_DIR/${LK_LOG_BASENAME:-${CMD##*/}}-$EUID.log
        _lk_log_install_file "$LOG_PATH" 2>/dev/null || continue
        echo "$LOG_PATH"
        return 0
    done
    false
}

# _lk_log_install_file FILE
#
# If the parent directory of FILE doesn't exist, create it with mode 01777,
# using root privileges if necessary. Then, if FILE doesn't exist or isn't
# writable, create it or change its permissions and ownership as needed.
function _lk_log_install_file() {
    if [[ -f $1 ]] && [[ -w $1 ]]; then
        return
    fi
    local GID
    if [[ ! -e $1 ]]; then
        local DIR=${1%"${1##*/}"}
        [[ -d ${DIR:=$PWD} ]] ||
            lk_elevate -f install -d -m 01777 "$DIR" || return
        GID=$(id -g) &&
            lk_elevate -f install -m 00600 -o "$EUID" -g "$GID" /dev/null "$1"
    else
        lk_elevate -f chmod 00600 "$1" || return
        [[ -w $1 ]] ||
            { GID=$(id -g) &&
                lk_elevate chown "$EUID:$GID" "$1"; }
    fi
}

function lk_log_is_open() {
    local FD
    for FD in _LK_{TTY_{OUT,ERR},LOG}_FD; do
        lk_fd_is_open "${!FD-}" || return
    done
}

# lk_log_migrate_legacy FILE
function lk_log_migrate_legacy() {
    local OUT_FILE=${1%.log}.out
    [[ -f $1 ]] && [[ -f $OUT_FILE ]] || return 0
    sed -E 's/^(\.\.|!!)//' "$OUT_FILE" >"$1" &&
        touch -r "$OUT_FILE" "$1" &&
        rm -f "$OUT_FILE"
}

# lk_log_tty_off -a
function lk_log_tty_off() {
    lk_log_is_open || return 0
    exec &>"/dev/fd/$_LK_LOG_FD" || return
    [[ ${1-} != -a ]] || [[ -z ${_LK_FD_LOGGED-} ]] ||
        eval "exec $_LK_FD>/dev/fd/$_LK_LOG_FD" || return
    _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

function lk_log_tty_on() {
    lk_log_is_open || return 0
    exec \
        > >(lk_tee "/dev/fd/$_LK_LOG_FD" >&"$_LK_TTY_OUT_FD") \
        2> >(lk_tee "/dev/fd/$_LK_LOG_FD" >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") || return
    [[ -z ${_LK_FD_LOGGED-} ]] ||
        eval "exec $_LK_FD> >(lk_tee \"/dev/fd/\$_LK_LOG_FD\" >&\"\$_LK_TTY_OUT_FD\")" || return
    _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

# lk_log_bypass [-o|-e] COMMAND [ARG...]
#
# Run COMMAND with stdout and/or stderr redirected exclusively to the console.
# If -o or -e is set, only redirect stdout or stderr respectively.
function lk_log_bypass() {
    local ARG _LK_CAN_FAIL=1
    [[ $1 != -[oe] ]] || { ARG=$1 && shift; }
    lk_log_is_open || {
        "$@"
        return
    }
    case "${ARG-}" in
    -o)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD"
        ;;
    -e)
        _lk_log_bypass "$@" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    *)
        _lk_log_bypass "$@" \
            >&"$_LK_TTY_OUT_FD" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
        ;;
    esac
}

function _lk_log_bypass() { (
    unset "${!_LK_LOG_@}"
    "$@"
); }

function lk_log_bypass_stdout() { lk_log_bypass -o "$@"; }
function lk_log_bypass_stderr() { lk_log_bypass -e "$@"; }

function lk_start_trace() {
    [[ -z ${_LK_NO_LOG-} ]] &&
        [[ $- != *x* ]] && lk_debug && lk_script_running || return 0
    local CMD TRACE_FILE
    CMD=${LK_LOG_CMDLINE:-$0}
    TRACE_FILE=${LK_LOG_TRACE_FILE:-/tmp/${LK_LOG_BASENAME:-${CMD##*/}}-$EUID.$(lk_date_ymdhms).trace} &&
        exec 4> >(lk_log >"$TRACE_FILE") || return
    if lk_bash_is 4 1; then
        BASH_XTRACEFD=4
    else
        # If BASH_XTRACEFD isn't supported, trace all output to stderr and send
        # lk_tty_* to the terminal
        exec 2>&4 || return
        ! lk_log_is_open || _LK_TRACE_FD=4
        ((${_LK_FD-2} != 2)) ||
            { exec 3>/dev/tty && _LK_FD=3; } || return
    fi
    set -x
}

# lk_log
#
# For each line of input, add a microsecond-resolution timestamp and remove
# characters before any carriage returns that aren't part of the line ending.
function lk_log() {
    local PL DELETE=
    lk_perl_load PL log || return
    [[ $PL != "${LK_MKTEMP_WITH_LAST-}" ]] || DELETE=1
    exec perl "$PL" ${DELETE:+--self-delete}
}

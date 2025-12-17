#!/usr/bin/env bash

# lk_log_open [<temp_log_file>]
#
# Redirect copies of the standard output and error streams to a timestamped log
# file, creating it if necessary.
#
# No action is taken if:
# - `LK_NO_LOG` is non-empty
# - output is already being logged by this or a parent process
# - a script file is not running
function lk_log_open() {
    [[ ! ${LK_NO_LOG-} ]] && ! lk_log_is_open && lk_is_script || return 0
    local cmd args file \
        LK_LOG_CMDLINE=(${LK_LOG_CMDLINE+"${LK_LOG_CMDLINE[@]}"})
    if [[ ${LK_LOG_CMDLINE+1} ]]; then
        # Unlike `type -P`, `type -p` prints nothing but returns 0 if given a
        # Bash function, builtin, keyword, or alias
        cmd=$(type -p "${LK_LOG_CMDLINE[0]}") &&
            cmd=${cmd:-"Bash $(type -t "${LK_LOG_CMDLINE[0]}") ${LK_LOG_CMDLINE[0]}"} ||
            cmd=${LK_LOG_CMDLINE[0]}
    else
        LK_LOG_CMDLINE=("$0" ${_LK_ARGV+"${_LK_ARGV[@]}"})
        cmd=$0
    fi
    args=$((${#LK_LOG_CMDLINE[@]} - 1))

    if [[ ${LK_LOG_FILE-} ]]; then
        file=$LK_LOG_FILE
        _lk_log_file_install "$file" || return
    elif (($#)); then
        local _file=${1%.out}
        _file=${_file%.log}.log
        if file=$(lk_log_file_create); then
            if [[ -f $_file ]]; then
                local temp
                _lk_log_file_migrate "$_file" || return
                temp=$(lk_mktemp) &&
                    cp -- "$file" "$temp" &&
                    cat -- "$_file" >>"$file" &&
                    rm -f -- "$_file" ||
                    lk_pass cp -- "$temp" "$file" ||
                    lk_err "log file import failed: $_file -> $file" || return
                rm -f -- "$temp" || true
            fi
        else
            file=$_file
        fi
    else
        file=$(lk_log_file_create ~ /tmp) ||
            lk_err "error creating log file" || return
    fi
    _lk_log_file_migrate "$file" || return
    _LK_TTY_OUT_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_OUT_FD>&1" &&
        _LK_TTY_ERR_FD=$(lk_fd_next) &&
        eval "exec $_LK_TTY_ERR_FD>&2" &&
        _LK_LOG_FD=$(lk_fd_next) &&
        if [[ -z ${LK_LOG_SECONDARY_FILE:+1} ]]; then
            eval "exec $_LK_LOG_FD> >(lk_log >>\"\$file\")"
        else
            eval "exec $_LK_LOG_FD> >(lk_log | lk_tee -a \"\$LK_LOG_SECONDARY_FILE\" >>\"\$file\")"
        fi || return
    ((${_LK_FD-2} != 2)) || {
        _LK_FD=3
        _LK_FD_LOGGED=1
    }
    lk_log_tty_on

    {
        printf '====> %s invoked with %d %s%s\n' \
            "$cmd" \
            $args "$(lk_plural $args argument)" "${LK_LOG_CMDLINE[1]+:}"
        for ((i = 1; i <= args; i++)); do
            printf '%3d %q\n' $i "${LK_LOG_CMDLINE[i]}"
        done
    } >"/dev/fd/$_LK_LOG_FD"
    ! lk_is_v 2 || _LK_FD=$_LK_TTY_OUT_FD lk_tty_log "Output log:" "$file"
    _LK_LOG_FILE=$file
}

# lk_log_close [-r]
#
# Close redirections opened by lk_log_open. If -r is set, reopen them for
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

# lk_log_file_create [DIR...]
#
# Find the first DIR in which the user can write to a log file, installing the
# directory (world-writable) and log file (owner-only) if needed, then print the
# pathname of the log file.
#
# $LK_BASE/var/log/lk-platform is always tried first.
function lk_log_file_create() {
    local CMD LOG_DIRS=() LOG_DIR LOG_PATH
    CMD=${LK_LOG_CMDLINE:-$0}
    [[ ! -d ${LK_BASE-} ]] ||
        lk_file_is_empty_dir "$LK_BASE" ||
        LOG_DIRS=("$LK_BASE/var/log/lk-platform")
    LOG_DIRS+=("$@")
    for LOG_DIR in ${LOG_DIRS+"${LOG_DIRS[@]}"}; do
        LOG_PATH=$LOG_DIR/${LK_LOG_BASENAME:-${CMD##*/}}-$EUID.log
        _lk_log_file_install "$LOG_PATH" 2>/dev/null || continue
        echo "$LOG_PATH"
        return 0
    done
    false
}

# _lk_log_file_install FILE
#
# If the parent directory of FILE doesn't exist, create it with mode 01777,
# using root privileges if necessary. Then, if FILE doesn't exist or isn't
# writable, create it or change its permissions and ownership as needed.
function _lk_log_file_install() {
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

# _lk_log_file_migrate <file>
#
# Migrate legacy log files to current equivalents for the given `.log` file.
#
# - If <file> is not empty and has a sibling with extension `.out`, replace both
#   with one `.log` file.
# - If <file> is in `$LK_BASE/var/log/lk-platform` and is empty, check for files
#   in `$LK_BASE/var/log` with the same name or a recognised logrotate suffix
#   and move them to `$LK_BASE/var/log/lk-platform` if found.
function _lk_log_file_migrate() {
    [[ -f ${1-} ]] && [[ $1 == *.log ]] || lk_bad_args || return
    if [[ -s $1 ]]; then
        local out_file=${1%.log}.out
        if [[ -f $out_file ]]; then
            sed -E 's/^(\.\.|!!)//' "$out_file" >"$1" &&
                touch -r "$out_file" "$1" &&
                rm -f -- "$out_file" ||
                lk_err "log file migration failed: $out_file -> $1" || return
        fi
    elif [[ ${1%/*} == "$LK_BASE/var/log/lk-platform" ]] &&
        [[ ! $LK_BASE/var/log -ef /var/log ]]; then
        (
            shopt -s nullglob
            file=${1%.log}
            # Match !(+(?)) to eliminate files that don't exist
            files=("$LK_BASE/var/log/${file##*/}"{.log,.out}{,.+([0-9])?(.gz)}!(+(?)))
            [[ ! ${files+1} ]] ||
                mv -- "${files[@]}" "$LK_BASE/var/log/lk-platform/" ||
                lk_err "log file migration failed: $LK_BASE/var/log/${file##*/}* -> $LK_BASE/var/log/lk-platform/"
        ) || return
    fi
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
    [[ -z ${LK_NO_LOG-} ]] &&
        [[ $- != *x* ]] && lk_debug_is_on && lk_is_script || return 0
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

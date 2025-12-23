#!/usr/bin/env bash

# lk_log_open [-v] [<temp_log_file>]
#
# Redirect copies of the standard output and error streams to a timestamped log
# file, creating it if necessary.
#
# If -v is given, write the pathname of the log file to the terminal.
#
# No action is taken if:
# - `LK_NO_LOG` is non-empty
# - output is already being logged by this or a parent process
# - a script file is not running
function lk_log_open() {
    [[ ! ${LK_NO_LOG-} ]] && ! lk_log_is_open && lk_is_script || return 0
    local v=0 cmd args file file_q \
        LK_LOG_CMDLINE=(${LK_LOG_CMDLINE+"${LK_LOG_CMDLINE[@]}"})
    [[ ${1-} != -v ]] || {
        v=1
        shift
    }
    _lk_log_cmdline_resolve
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
        file=$(
            lk_log_file_create \
                ~/.local/state/log/lk-platform \
                /tmp/lk-platform/log
        ) || lk_err "error creating log file" || return
    fi
    file_q=$(printf '%q\n' "$file")
    _lk_log_file_migrate "$file" || return
    _LK_TTY_OUT_FD=$(lk_fd_next) && eval "exec $_LK_TTY_OUT_FD>&1" &&
        _LK_TTY_ERR_FD=$(lk_fd_next) && eval "exec $_LK_TTY_ERR_FD>&2" &&
        _LK_LOG_FD=$(lk_fd_next) &&
        if [[ ! ${LK_LOG_SECONDARY_FILE-} ]]; then
            eval "exec $_LK_LOG_FD> >(lk_log >>$file_q)"
            unset _LK_LOG_SECONDARY_FILE
        else
            local file2_q
            file2_q=$(printf '%q\n' "$LK_LOG_SECONDARY_FILE")
            eval "exec $_LK_LOG_FD> >(lk_log | tee -a $file2_q >>$file_q)"
            _LK_LOG_SECONDARY_FILE=$LK_LOG_SECONDARY_FILE
        fi &&
        _LK_FD=3 &&
        _LK_LOG_FILE=$file &&
        lk_log_tty_on ||
        lk_err "error opening file descriptors" || return
    {
        printf '====> %s invoked with %d %s%s\n' \
            "$cmd" \
            $args "$(lk_plural $args argument)" "${LK_LOG_CMDLINE[1]+:}"
        for ((i = 1; i <= args; i++)); do
            printf '%3d %q\n' $i "${LK_LOG_CMDLINE[i]}"
        done
    } >"/dev/fd/$_LK_LOG_FD"
    ((!v)) || printf "Output log: %s\n" "$file" >"/dev/fd/$_LK_TTY_OUT_FD"
}

# _lk_log_cmdline_resolve
#
# Assign `cmd` from `LK_LOG_CMDLINE` if possible, otherwise set `LK_LOG_CMDLINE`
# to its default value and assign `$0` to `cmd`.
function _lk_log_cmdline_resolve() {
    if [[ ${LK_LOG_CMDLINE+1} ]]; then
        # `type -p` prints nothing but returns 0 if given a Bash callable
        cmd=$(type -p "${LK_LOG_CMDLINE[0]}") &&
            cmd=${cmd:-"Bash $(type -t "${LK_LOG_CMDLINE[0]}") ${LK_LOG_CMDLINE[0]}"} ||
            cmd=${LK_LOG_CMDLINE[0]}
    else
        LK_LOG_CMDLINE=("$0" ${_LK_ARGV+"${_LK_ARGV[@]}"})
        cmd=$0
    fi
}

# - lk_log_close
# - lk_log_close -s
#
# If file descriptors opened by `lk_log_open` are present in the current scope,
# close them, or if -s is set and a secondary log file is open, close it.
function lk_log_close() {
    lk_log_is_open || return 0
    if [[ ${1-} == -s ]]; then
        [[ ${_LK_LOG_SECONDARY_FILE-} ]] || return 0
        local file_q
        file_q=$(printf '%q\n' "$_LK_LOG_FILE")
        eval "exec $_LK_LOG_FD> >(lk_log >>$file_q)"
        unset _LK_LOG_SECONDARY_FILE
        return
    fi
    # shellcheck disable=SC2261
    exec \
        >&"$_LK_TTY_OUT_FD" \
        2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}" || return
    local close_lk_fd=1 fd
    [[ ! ${_LK_TRACE_FD-} ]] || {
        exec 3>&1 &&
            unset _LK_TRACE_FD close_lk_fd || return
    }
    for fd in ${close_lk_fd:+_LK_FD} _LK_LOG_FD _LK_TTY_ERR_FD _LK_TTY_OUT_FD; do
        [[ ${!fd-} ]] && eval "exec ${!fd}>&-" && unset "$fd" ||
            lk_err "error closing file descriptors" || return
    done
    unset _LK_LOG_FILE
}

# lk_log_file_create [<dir>...]
#
# Get the pathname of a writable log file for the running command.
#
# - Tests `$LK_BASE/var/log/lk-platform`, then each of the given directories,
#   until one that exists and is writable, or does not exist but can be created,
#   is found. Otherwise it fails silently.
# - The directory is created with mode 1777 (world-writable) if necessary.
# - Access to the file is limited to its owner (the current user) via mode 0600.
function lk_log_file_create() {
    local cmd file
    cmd=${LK_LOG_CMDLINE[0]:-$0}
    [[ ! -d ${LK_BASE-} ]] ||
        lk_file_is_empty_dir "$LK_BASE" ||
        set -- "$LK_BASE/var/log/lk-platform" "$@"
    while (($#)); do
        file=$1/${LK_LOG_BASENAME:-${cmd##*/}}-$EUID.log
        ! _lk_log_file_install "$file" 2>/dev/null || {
            printf '%s\n' "$file"
            break
        }
        shift
    done
    (($#))
}

# _lk_log_file_install <file>
#
# Create the given log file or update its ownership and permissions if needed.
function _lk_log_file_install() {
    [[ ! -f $1 ]] || [[ ! -w $1 ]] || return 0
    local gid
    if [[ ! -e $1 ]]; then
        local dir=${1%"${1##*/}"}
        [[ $dir ]] || dir=$PWD
        gid=$(id -g) &&
            { [[ -d $dir ]] || lk_elevate -f install -d -m 01777 "$dir"; } &&
            lk_elevate -f install -m 00600 -o "$EUID" -g "$gid" /dev/null "$1"
    else
        local mode
        mode=0$(lk_file_mode "$1") &&
            { ((mode == 0600)) || lk_elevate -f chmod 00600 "$1"; } &&
            { [[ -w $1 ]] || { gid=$(id -g) && lk_elevate chown "$EUID:$gid" "$1"; }; }
    fi
}

# lk_log_is_open
#
# Check if file descriptors opened by `lk_log_open` are present in the current
# scope.
function lk_log_is_open() {
    local fd
    for fd in _LK_TTY_OUT_FD _LK_TTY_ERR_FD _LK_LOG_FD; do
        [[ ${!fd-} ]] && lk_fd_is_open "${!fd-}" || return
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
    elif [[ -d ${LK_BASE-} ]] &&
        ! lk_file_is_empty_dir "$LK_BASE" &&
        [[ ${1%/*} == "$LK_BASE/var/log/lk-platform" ]] &&
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

# lk_log_tty_off
#
# Redirect standard output and error streams to the output log only.
#
# `lk_tty_*` output is still written to the terminal.
function lk_log_tty_off() {
    lk_log_is_open || return 0
    exec \
        &>"/dev/fd/$_LK_LOG_FD" \
        3> >(tee "/dev/fd/$_LK_LOG_FD" >&"$_LK_TTY_OUT_FD") || return
    _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

# lk_log_tty_all_off
#
# Same as `lk_log_tty_off`, but `lk_tty_*` output is not written to the
# terminal.
function lk_log_tty_all_off() {
    lk_log_is_open || return 0
    exec \
        &>"/dev/fd/$_LK_LOG_FD" \
        3>&1 || return
    _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

# lk_log_tty_on
#
# Redirect standard output and error streams to the terminal and the output log.
function lk_log_tty_on() {
    lk_log_is_open || return 0
    exec \
        > >(tee "/dev/fd/$_LK_LOG_FD" >&"$_LK_TTY_OUT_FD") \
        2> >(tee "/dev/fd/$_LK_LOG_FD" >&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}") \
        3>&1 || return
    _LK_LOG_TTY_LAST=${FUNCNAME[0]}
}

# lk_log_run_tty_only [options] [--] <command> [<arg>...]
#
# Run a command with its standard output and/or error streams redirected to the
# terminal only.
#
# Options:
#
#     -o, --stdout  Only redirect standard output.
#     -e, --stderr  Only redirect standard error.
#
# Useful with commands that perform their own logging.
function lk_log_run_tty_only() {
    local only
    while [[ ${1-} == -* ]]; do
        case "$1" in
        -o | --stdout) only=stdout ;;
        -e | --stderr) only=stderr ;;
        --) shift && break ;;
        *) lk_bad_args || return ;;
        esac
        shift || lk_bad_args || return
    done
    (($#)) || lk_bad_args || return
    if ! lk_log_is_open; then
        "$@"
    elif [[ ${only-} == stdout ]]; then
        "$@" \
            >&"$_LK_TTY_OUT_FD"
    elif [[ ${only-} == stderr ]]; then
        "$@" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
    else
        # shellcheck disable=SC2261
        "$@" \
            >&"$_LK_TTY_OUT_FD" \
            2>&"${_LK_TRACE_FD:-$_LK_TTY_ERR_FD}"
    fi
}

# lk_log_open_trace
#
# Enable `set -x` and redirect trace output to a timestamped log file, creating
# or truncating it if necessary.
#
# No action is taken if:
# - `LK_NO_LOG` is non-empty
# - `set -x` is already enabled
# - `LK_DEBUG` is not `Y`
# - a script file is not running
function lk_log_open_trace() {
    [[ ! ${LK_NO_LOG-} ]] && [[ $- != *x* ]] && lk_debug_is_on && lk_is_script || return 0
    local cmd file LK_LOG_CMDLINE=(${LK_LOG_CMDLINE+"${LK_LOG_CMDLINE[@]}"})
    _lk_log_cmdline_resolve
    file=${LK_LOG_TRACE_FILE:-/tmp/${LK_LOG_BASENAME:-${cmd##*/}}-$EUID.$(uuidgen | lk_lower).trace} &&
        _lk_log_file_install "$file" &&
        exec 4> >(lk_log >"$file") &&
        if lk_bash_is 4 1; then
            BASH_XTRACEFD=4
        else
            # If BASH_XTRACEFD isn't supported, redirect standard error to the
            # trace file and `lk_tty_*` output to standard output
            if lk_log_is_open; then
                _LK_TRACE_FD=4
            else
                _LK_FD=3
                exec 3>&1
            fi &&
                exec 2>&4
        fi ||
        lk_err "error opening file descriptors" || return
    set -x
}

# lk_log
#
# Add a microsecond-resolution timestamp to each line of input after removing
# any non-printing characters.
function lk_log() {
    local pl delete
    lk_perl_load pl log || return
    [[ $pl != "${LK_MKTEMP_WITH_LAST-}" ]] || delete=1
    exec perl "$pl" ${delete:+--self-delete}
}

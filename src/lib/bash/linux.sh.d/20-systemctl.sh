#!/bin/bash

function _lk_systemctl() {
    local OPTIND OPTARG OPT LK_USAGE PARAMS=0 _USER _MACHINE NAME _NAME \
        _LK_STACK_DEPTH=1 COMMAND=(systemctl) ARGS=() IFS=$' \t\n'
    unset _USER _MACHINE
    [ -z "${_LK_PARAM+1}" ] || PARAMS=${#_LK_PARAM[@]}
    LK_USAGE="\
Usage:
  ${FUNCNAME[1]} [options] ${_LK_PARAM+${_LK_PARAM[*]} }<SERVICE>

Options:
  -u                Use \`systemctl --user\`.
  -m <CONTAINER>    Use \`systemctl --machine <CONTAINER>\`.
  -n <NAME>         Refer to the service as <NAME> in output."
    while getopts ":um:n:" OPT; do
        case "$OPT" in
        u)
            [ -n "${_USER+1}" ] || {
                COMMAND+=(--user)
                ARGS+=(-u)
                _USER=
            }
            ;;
        m)
            [ -n "${_MACHINE+1}" ] || {
                COMMAND+=(--machine "$OPTARG")
                ARGS+=(-m "$OPTARG")
                _MACHINE=
            }
            ;;
        n)
            NAME=$OPTARG
            ;;
        \? | :)
            lk_usage
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1 + PARAMS))
    [ $# -eq 1 ] ||
        # Accept more parameters if _LK_PARAM allows them
        { [ $# -gt 1 ] &&
            [[ "${_LK_PARAM+${_LK_PARAM[*]: -1}}" =~ \.\.\.[]\)\>]*$ ]]; } ||
        lk_usage || return
    set -- "${*: -1}"
    [[ $1 == *.* ]] || {
        set -- "$1.service"
        echo 'set -- "${@:1:$#-1}" "${*: -1}.service"'
    }
    NAME=${NAME:-$1}
    _NAME=$NAME$([ "$NAME" = "$1" ] || echo " ($1)")
    lk_var_sh_q -a LK_USAGE COMMAND ARGS _USER _MACHINE NAME _NAME IFS
    [ -n "${_USER+1}" ] || echo 'unset _USER'
    [ -n "${_MACHINE+1}" ] || echo 'unset _MACHINE'
    printf 'shift %s\n' $((OPTIND - 1))
}

function lk_systemctl_get_property() {
    local SH VALUE
    SH=$(_LK_PARAM=("<PROPERTY>") &&
        _lk_systemctl "$@") && eval "$SH" || return
    VALUE=$("${COMMAND[@]}" show --property "$1" "$2") &&
        [ -n "$VALUE" ] &&
        echo "${VALUE#*=}"
}

function lk_systemctl_property_is() {
    local SH ONE_OF VALUE
    SH=$(_LK_PARAM=("<PROPERTY>" "<VALUE>...") &&
        _lk_systemctl "$@") && eval "$SH" || return
    ONE_OF=("${@:2:$#-2}")
    VALUE=$("${COMMAND[@]}" show --property "$1" "${*: -1}") &&
        [ -n "$VALUE" ] &&
        lk_in_array "${VALUE#*=}" ONE_OF
}

function lk_systemctl_enabled() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    "${COMMAND[@]}" is-enabled --quiet "$1"
}

function lk_systemctl_running() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_property_is ${ARGS+"${ARGS[@]}"} \
        ActiveState active activating "$1"
}

function lk_systemctl_failed() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    "${COMMAND[@]}" is-failed --quiet "$1"
}

function lk_systemctl_exists() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_property_is ${ARGS+"${ARGS[@]}"} \
        LoadState loaded "$1" 2>/dev/null
}

function lk_systemctl_masked() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_property_is ${ARGS+"${ARGS[@]}"} \
        LoadState masked "$1"
}

function lk_systemctl_check_exists() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_exists ${ARGS+"${ARGS[@]}"} "$1" ||
        _LK_STACK_DEPTH=1 lk_warn "unknown service: $_NAME"
}

function lk_systemctl_check_failed() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    ! lk_systemctl_failed ${ARGS+"${ARGS[@]}"} "$1" ||
        _LK_STACK_DEPTH=1 lk_warn "service failed: $_NAME"
}

function lk_systemctl_start() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_check_failed ${ARGS+"${ARGS[@]}"} "$1" || return
    lk_systemctl_running ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Starting service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" start "$1" ||
            lk_warn "could not start service: $_NAME"
    }
}

function lk_systemctl_stop() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    ! lk_systemctl_running ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Stopping service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" stop "$1" ||
            lk_warn "could not stop service: $_NAME"
    }
}

function lk_systemctl_restart() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    if ! lk_systemctl_running ${ARGS+"${ARGS[@]}"} "$1"; then
        lk_systemctl_start ${ARGS+"${ARGS[@]}"} "$1"
    else
        lk_tty_detail "Restarting service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" restart "$1" ||
            lk_warn "could not restart service: $_NAME"
    fi
}

function lk_systemctl_reload() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_running ${ARGS+"${ARGS[@]}"} "$1" ||
        lk_warn "not reloading inactive service: $_NAME" || return
    lk_tty_detail "Reloading service:" "$NAME"
    ${_USER-lk_elevate} "${COMMAND[@]}" reload "$1" ||
        lk_warn "could not reload service: $_NAME"
}

function lk_systemctl_reload_or_restart() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_tty_detail "Reloading or restarting service:" "$NAME"
    # "Reload one or more units if they support it. If not, stop and then start
    # them instead. If the units are not running yet, they will be started."
    ${_USER-lk_elevate} "${COMMAND[@]}" reload-or-restart "$1" ||
        lk_warn "could not reload or restart service: $_NAME"
}

function lk_systemctl_enable() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_check_exists ${ARGS+"${ARGS[@]}"} "$1" || return
    lk_systemctl_enabled ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Enabling service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" enable "$1" ||
            lk_warn "could not enable service: $_NAME"
    }
}

function lk_systemctl_enable_now() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    # Return immediately if this is an enabled one-shot service
    if lk_systemctl_exists ${ARGS+"${ARGS[@]}"} "$1" &&
        lk_systemctl_property_is ${ARGS+"${ARGS[@]}"} Type oneshot "$1" &&
        lk_systemctl_enabled ${ARGS+"${ARGS[@]}"} "$1"; then
        return
    fi
    lk_systemctl_start ${ARGS+"${ARGS[@]}"} "$1" &&
        lk_systemctl_enable ${ARGS+"${ARGS[@]}"} "$1"
}

function lk_systemctl_disable() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_check_exists ${ARGS+"${ARGS[@]}"} "$1" || return
    ! lk_systemctl_enabled ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Disabling service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" disable "$1" ||
            lk_warn "could not disable service: $_NAME"
    }
}

function lk_systemctl_disable_now() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_stop ${ARGS+"${ARGS[@]}"} "$1" &&
        lk_systemctl_disable ${ARGS+"${ARGS[@]}"} "$1"
}

function lk_systemctl_mask() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_stop ${ARGS+"${ARGS[@]}"} "$1" || return
    lk_systemctl_masked ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Masking service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" mask "$1" ||
            lk_warn "could not mask service: $_NAME"
    }
}

function lk_systemctl_mask_now() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    lk_systemctl_stop ${ARGS+"${ARGS[@]}"} "$1" &&
        lk_systemctl_mask ${ARGS+"${ARGS[@]}"} "$1"
}

function lk_systemctl_unmask() {
    local SH
    SH=$(_lk_systemctl "$@") && eval "$SH" || return
    ! lk_systemctl_masked ${ARGS+"${ARGS[@]}"} "$1" || {
        lk_tty_detail "Unmasking service:" "$NAME"
        ${_USER-lk_elevate} "${COMMAND[@]}" unmask "$1" ||
            lk_warn "could not unmask service: $_NAME"
    }
}

true || {
    systemctl
}

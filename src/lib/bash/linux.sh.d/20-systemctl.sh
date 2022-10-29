#!/bin/bash

function _lk_systemctl() {
    # Skip the argument check if we've called ourselves
    [[ ${FUNCNAME[2]-} == "$FUNCNAME" ]] && local DIRECT=0 || {
        local IFS=$' \t\n' CMD=(systemctl) SYS= NAME=${*: -1} DIRECT=1 _LK_STACK_DEPTH=1
        while (($# > 1)); do
            [[ $1 != -u ]] || { CMD+=(--user) && unset SYS && shift && continue; }
            [[ $1 != -n ]] || { NAME=$2 && shift 2 && continue; }
            break
        done
    }
    case "${FUNCNAME[1]#*lk_systemctl_}" in
    get_property)
        "${CMD[@]}" show --property "$1" "$2" |
            sed '1s/^[^=]*=//' | grep --color=never .
        ;;
    property_is)
        (($# > 2)) && lk_systemctl_get_property "$1" "${*: -1}" |
            grep -Fxf <(printf '%s\n' "${@:2:$#-2}") >/dev/null
        ;;
    exists)
        # Check via filesystem first to work around systemctl's limitations when
        # running in a chroot
        [[ $1 == *.* ]] || set -- "$1.service"
        [[ -e /usr/lib/systemd/${SYS+system}${SYS-user}/$1 ]] ||
            [[ -e /etc/systemd/${SYS+system}${SYS-user}/$1 ]] ||
            lk_systemctl_property_is LoadState loaded "$1" 2>/dev/null
        ;;
    enabled)
        # Check the unit exists if lk_systemctl_enabled was called directly,
        # otherwise assume it's already been checked
        { ((!DIRECT)) || lk_systemctl_exists "$1"; } &&
            "${CMD[@]}" is-enabled --quiet "$1"
        ;;
    running)
        lk_systemctl_property_is ActiveState active activating "$1"
        ;;
    failed)
        "${CMD[@]}" is-failed --quiet "$1"
        ;;
    masked)
        lk_systemctl_property_is LoadState masked "$1"
        ;;
    check_exists)
        lk_systemctl_exists "$1" || lk_stack lk_warn "unit does not exist: $NAME"
        ;;
    check_failed)
        ! lk_systemctl_failed "$1" || lk_stack lk_warn "unit failed: $NAME"
        ;;
    check_startable)
        lk_systemctl_running "$1" ||
            { _lk_systemctl_check_exists "$1" &&
                _lk_systemctl_check_failed "$1"; }
        ;;
    start)
        ! lk_systemctl_running "$1" || return 0
        _lk_systemctl_check_exists "$1" &&
            _lk_systemctl_check_failed "$1" &&
            _lk_systemctl_apply start "$1" Starting
        ;;
    stop)
        ! lk_systemctl_running "$1" ||
            _lk_systemctl_apply stop "$1" Stopping
        ;;
    restart)
        _lk_systemctl_check_startable "$1" || return
        _lk_systemctl_apply restart "$1" Restarting
        ;;
    reload)
        lk_systemctl_running "$1" ||
            lk_warn "not reloading inactive unit: $NAME" || return
        _lk_systemctl_apply reload "$1" Reloading
        ;;
    reload_or_restart)
        _lk_systemctl_check_startable "$1" || return
        # "Reload one or more units if they support it. If not, stop and then start
        # them instead. If the units are not running yet, they will be started."
        _lk_systemctl_apply reload-or-restart "$1" \
            "Reloading or restarting" "reload or restart"
        ;;
    enable)
        _lk_systemctl_check_exists "$1" || return
        lk_systemctl_enabled "$1" ||
            _lk_systemctl_apply enable "$1" Enabling
        ;;
    enable_now)
        # Return immediately if this is an enabled one-shot service
        if lk_systemctl_exists "$1" &&
            lk_systemctl_property_is Type oneshot "$1" &&
            lk_systemctl_enabled "$1"; then
            return
        fi
        lk_systemctl_start "$1" &&
            lk_systemctl_enable "$1"
        ;;
    disable)
        _lk_systemctl_check_exists "$1" || return
        ! lk_systemctl_enabled "$1" ||
            _lk_systemctl_apply disable "$1" Disabling
        ;;
    disable_now)
        lk_systemctl_stop "$1" &&
            lk_systemctl_disable "$1"
        ;;
    mask)
        lk_systemctl_stop "$1" || return
        lk_systemctl_masked "$1" ||
            _lk_systemctl_apply mask "$1" Masking
        ;;
    unmask)
        lk_systemctl_masked "$1" || return 0
        _lk_systemctl_apply unmask "$1" Unmasking
        ;;
    *)
        false || lk_warn "not implemented"
        ;;
    esac
}

# _lk_systemctl_apply COMMAND UNIT "<Command>ing" ["<command>"]
function _lk_systemctl_apply() {
    local _LK_STACK_DEPTH=$((_LK_STACK_DEPTH + 1))
    lk_tty_detail "$3 unit:" "$NAME"
    ${SYS+lk_elevate} "${CMD[@]}" "$1" "$2" ||
        lk_warn "could not ${4-$1} unit: $NAME"
}

# lk_systemctl_get_property PROPERTY UNIT
function lk_systemctl_get_property() { _lk_systemctl "$@"; }

# lk_systemctl_property_is PROPERTY VALUE... UNIT
function lk_systemctl_property_is() { _lk_systemctl "$@"; }

# lk_systemctl_exists UNIT
function lk_systemctl_exists() { _lk_systemctl "$@"; }

# lk_systemctl_enabled UNIT
function lk_systemctl_enabled() { _lk_systemctl "$@"; }

# lk_systemctl_running UNIT
function lk_systemctl_running() { _lk_systemctl "$@"; }

# lk_systemctl_failed UNIT
function lk_systemctl_failed() { _lk_systemctl "$@"; }

# lk_systemctl_masked UNIT
function lk_systemctl_masked() { _lk_systemctl "$@"; }

# _lk_systemctl_check_exists UNIT
function _lk_systemctl_check_exists() { _lk_systemctl "$@"; }

# _lk_systemctl_check_failed UNIT
function _lk_systemctl_check_failed() { _lk_systemctl "$@"; }

# _lk_systemctl_check_startable UNIT
function _lk_systemctl_check_startable() { _lk_systemctl "$@"; }

# lk_systemctl_start UNIT
function lk_systemctl_start() { _lk_systemctl "$@"; }

# lk_systemctl_stop UNIT
function lk_systemctl_stop() { _lk_systemctl "$@"; }

# lk_systemctl_restart UNIT
function lk_systemctl_restart() { _lk_systemctl "$@"; }

# lk_systemctl_reload UNIT
function lk_systemctl_reload() { _lk_systemctl "$@"; }

# lk_systemctl_reload_or_restart UNIT
function lk_systemctl_reload_or_restart() { _lk_systemctl "$@"; }

# lk_systemctl_enable UNIT
function lk_systemctl_enable() { _lk_systemctl "$@"; }

# lk_systemctl_enable_now UNIT
function lk_systemctl_enable_now() { _lk_systemctl "$@"; }

# lk_systemctl_disable UNIT
function lk_systemctl_disable() { _lk_systemctl "$@"; }

# lk_systemctl_disable_now UNIT
function lk_systemctl_disable_now() { _lk_systemctl "$@"; }

# lk_systemctl_mask UNIT
function lk_systemctl_mask() { _lk_systemctl "$@"; }

# lk_systemctl_unmask UNIT
function lk_systemctl_unmask() { _lk_systemctl "$@"; }

true || {
    systemctl
}

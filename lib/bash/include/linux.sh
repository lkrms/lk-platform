#!/bin/bash

function lk_atop_ps_mem() {
    local TEMP
    TEMP=$(mktemp) &&
        lk_elevate atop -R -PPRM "$@" |
        awk -f "${LK_INST:-$LK_BASE}/lib/awk/atop-ps-mem.awk" \
            -v "TEMP=$TEMP"
}

function lk_systemctl_get_property() {
    local VALUE
    VALUE=$(systemctl show --property "$1" "${@:2}") &&
        [ -n "$VALUE" ] &&
        echo "${VALUE#$1=}"
}

function lk_systemctl_property_is() {
    local VALUE
    VALUE=$(lk_systemctl_get_property "$1" "${@:3}") &&
        [ "$VALUE" = "$2" ]
}

function lk_systemctl_enabled() {
    systemctl is-enabled --quiet "$@"
}

function lk_systemctl_running() {
    systemctl is-active --quiet "$@"
}

function lk_systemctl_failed() {
    systemctl is-failed --quiet "$@"
}

function lk_systemctl_exists() {
    lk_systemctl_property_is LoadState loaded "$@" ||
        lk_warn "unknown service: $*"
}

function lk_systemctl_start() {
    lk_systemctl_running "$@" || {
        lk_console_detail "Starting service:" "$*"
        lk_elevate systemctl start "$@" ||
            lk_warn "could not start service: $*"
    }
}

function lk_systemctl_stop() {
    ! lk_systemctl_running "$@" || {
        lk_console_detail "Stopping service:" "$*"
        lk_elevate systemctl stop "$@" ||
            lk_warn "could not stop service: $*"
    }
}

function lk_systemctl_enable() {
    lk_systemctl_exists "$@" || return
    lk_systemctl_enabled "$@" || {
        lk_console_detail "Enabling service:" "$*"
        lk_elevate systemctl enable "$@" ||
            lk_warn "could not enable service: $*" || return
    }
    ! lk_systemctl_failed "$@" ||
        lk_warn "not starting failed service: $*" || return
    lk_systemctl_start "$@"
}

function lk_systemctl_disable() {
    lk_systemctl_exists "$@" &&
        lk_systemctl_stop "$@" || return
    ! lk_systemctl_enabled "$@" || {
        lk_console_detail "Disabling service:" "$*"
        lk_elevate systemctl disable "$@" ||
            lk_warn "could not disable service: $*"
    }
}

# shellcheck disable=SC2034,SC2207
function lk_get_standard_users() {
    local IFS ADM_USERS USERS
    IFS=,
    ADM_USERS=($(getent group adm | cut -d: -f4))
    IFS=$'\n'
    USERS=($(getent passwd |
        awk -F: '$3 >= 1000 && $3 < 65534 { print $1 }'))
    # lk_linode_hosting_ssh_add_all relies on this being a standalone function,
    # so don't use lk_echo_array
    comm -13 \
        <(printf '%s\n' "${ADM_USERS[@]}" | sort) \
        <(printf '%s\n' "${USERS[@]}" | sort)
}

function lk_full_name() {
    getent passwd "${1:-$UID}" | cut -d: -f5 | cut -d, -f1
}

function lk_icon_install() {
    local TARGET_DIR="${2:-$HOME/.local/share/icons/hicolor}" SIZE SIZES=(
        16x16 22x22 24x24 32x32 36x36 48x48 64x64 72x72 96x96
        128x128 160x160 192x192 256x256 384x384 512x512
        1024x1024
    )
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    for SIZE in "${SIZES[@]}"; do
        lk_maybe_sudo mkdir -pv "$TARGET_DIR/$SIZE/apps" &&
            lk_maybe_sudo convert "$1" -resize "$SIZE" \
                "$TARGET_DIR/$SIZE/apps/${1##*/}" || return
    done
    ! lk_command_exists gtk-update-icon-cache ||
        lk_maybe_sudo gtk-update-icon-cache --force --quiet \
            --ignore-theme-index "$TARGET_DIR" || true
}

function lk_is_portable() {
    # 8  = Portable
    # 9  = Laptop
    # 10 = Notebook
    # 11 = Hand Held
    # 12 = Docking Station
    # 14 = Sub Notebook
    # 30 = Tablet
    # 31 = Convertible
    # 32 = Detachable
    grep -Eq "^(8|9|10|11|12|14|30|31|32)\$" /sys/class/dmi/id/chassis_type
}

function _lk_lid_files() {
    (
        shopt -s nullglob || exit
        LID_FILES=(/proc/acpi/button/lid/*/state)
        [ ${#LID_FILES[@]} -gt 0 ] || exit
        lk_echo_array LID_FILES
    )
}

function lk_is_lid_closed() {
    local LID_FILE
    LID_FILE=$(_lk_lid_files | head -n1) &&
        grep -q 'closed$' "$LID_FILE"
}

function lk_x_dpi() {
    xdpyinfo |
        grep -Eo '^[[:blank:]]+resolution:[[:blank:]]*[0-9]+x[0-9]+' |
        grep -Eo '[0-9]+' | head -n1
}

function lk_xfce4_xfconf_dump() {
    local CHANNELS
    # shellcheck disable=SC2207
    CHANNELS=($(xfconf-query -l | tail -n+2 | sort -f))
    for CHANNEL in "${CHANNELS[@]}"; do
        while read -r PROPERTY VALUE; do
            printf '%s,%s,%s\n' "$CHANNEL" "$PROPERTY" "$VALUE"
        done < <(xfconf-query -c "$CHANNEL" -lv | sort -f)
    done
}

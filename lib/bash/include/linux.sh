#!/bin/bash

function lk_atop_ps_mem() {
    local TEMP
    TEMP=$(mktemp) &&
        lk_elevate atop -R -PPRM "$@" |
        awk -f "${LK_INST:-$LK_BASE}/lib/awk/atop-ps-mem.awk" \
            -v "TEMP=$TEMP"
}

function lk_systemctl_loaded() {
    [ "$(systemctl show --property=LoadState "$@" | cut -d= -f2-)" = loaded ]
}

function lk_systemctl_enable() {
    systemctl is-enabled --quiet "$@" || {
        ! lk_verbose ||
            lk_console_detail "Running:" "systemctl enable --now $*"
        sudo systemctl enable --now "$@"
    }
}

function lk_systemctl_disable() {
    ! systemctl is-enabled --quiet "$@" || {
        ! lk_verbose ||
            lk_console_detail "Running:" "systemctl disable --now $*"
        sudo systemctl disable --now "$@"
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

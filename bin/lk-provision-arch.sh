#!/usr/bin/env bash

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

shopt -s nullglob extglob

. "$LK_BASE/lib/bash/common.sh"
lk_require arch git linux provision whiptail

! lk_in_chroot || _LK_BOOTSTRAP=1

if lk_is_bootstrap; then
    function systemctl_enable() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        [[ ! -e /usr/lib/systemd/system/$1 ]] &&
            [[ ! -e /etc/systemd/system/$1 ]] || {
            lk_tty_detail "Enabling service:" "${2:-$1}"
            sudo systemctl enable "$1"
        }
    }
    function systemctl_mask() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        lk_tty_detail "Masking service:" "${2:-$1}"
        sudo systemctl mask "$1"
    }
    function lk_systemctl_stop() {
        :
    }
    lk_tty_print
else
    function systemctl_enable() {
        local NO_START_REGEX='^(NetworkManager-dispatcher|lightdm)$'
        lk_systemctl_exists "$1" || return 0
        if [[ $1 =~ $NO_START_REGEX ]]; then
            lk_systemctl_enable ${2:+-n "$2"} "$1"
        else
            lk_systemctl_running "$1" || SERVICE_STARTED+=("$1")
            lk_systemctl_enable_now ${2:+-n "$2"} "$1"
        fi
    }
    function systemctl_mask() {
        lk_systemctl_mask ${2:+-n "$2"} "$1"
    }
fi

function service_apply() {
    local i _ERRORS=${#ERRORS[@]}
    lk_tty_print "Checking services"
    lk_is_bootstrap || ! lk_is_true DAEMON_RELOAD ||
        lk_tty_run_detail sudo systemctl daemon-reload ||
        ERRORS+=("Command failed: systemctl daemon-reload")
    [ ${#SERVICE_ENABLE[@]} -eq 0 ] ||
        for i in $(seq 0 2 $((${#SERVICE_ENABLE[@]} - 1))); do
            systemctl_enable "${SERVICE_ENABLE[@]:i:2}" ||
                ERRORS+=("Could not enable service: ${SERVICE_ENABLE[*]:i:1}")
        done
    lk_is_bootstrap || [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
        SERVICE_RESTART=($(comm -23 \
            <(lk_arr SERVICE_RESTART | sort -u) \
            <(lk_arr SERVICE_STARTED | sort -u))) && {
            [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
                lk_tty_print "Restarting services with changed settings"
                for SERVICE in "${SERVICE_RESTART[@]}"; do
                    lk_systemctl_restart "$SERVICE" ||
                        ERRORS+=("Could not restart service: $SERVICE")
                done
            } || ERRORS+=("Could not restart services")
        }
    }
    DAEMON_RELOAD=
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    SERVICE_STARTED=()
    [ ${#ERRORS[@]} -eq "$_ERRORS" ]
}

function file_delete() {
    local FILES=("$@")
    LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE:-1}
    lk_remove_missing FILES
    [ ${#FILES[@]} -eq 0 ] || {
        LK_FILE_REPLACE_NO_CHANGE=0
        sudo rm -fv "${FILES[@]}"
    }
}

# - In: i, IF_ARRAY, IF_PREFIX, ${IF_ARRAY}_NOW[i]
# - Out: IF, IF_PATH, IF_ADDRESS, IF_NAME, ${IF_ARRAY}[i], UDEV_RULES[],
#   IF_RENAME[]
function process_interface() {
    eval "IF=\${${IF_ARRAY}_NOW[i]}"
    IF_PATH=/sys/class/net/$IF
    IF_ADDRESS=$(<"$IF_PATH/address")
    IF_NAME=$IF_PREFIX$i
    eval "${IF_ARRAY}[i]=\$IF_NAME"
    [ -z "${UDEV_RULES[i]+1}" ] || local i=${#UDEV_RULES[@]}
    UDEV_RULES[i]=$(printf \
        'SUBSYSTEM=="net", DEVPATH!="*/virtual/*", ACTION=="add", ATTR{address}=="%s", NAME="%s"\n' \
        "$IF_ADDRESS" "$IF_NAME")
    [ "$IF" = "$IF_NAME" ] ||
        IF_RENAME+=("$IF" "$IF_NAME")
}

function link_rename() {
    . "$LK_BASE/lib/bash/include/core.sh"
    lk_tty_run_detail udevadm control --reload
    while [ $# -ge 2 ]; do
        { ! lk_require_output -q \
            nmcli -g GENERAL.CONNECTION device show "$1" 2>/dev/null ||
            lk_tty_run_detail nmcli device disconnect "$1"; } &&
            lk_tty_run_detail ip link set "$1" down &&
            lk_tty_run_detail ip link set "$1" name "$2" &&
            lk_tty_run_detail ip link set "$2" up ||
            return
        shift 2
    done
}

function memory_at_least() {
    [ "${_LK_SYSTEM_MEMORY:=$(lk_system_memory)}" -ge "$1" ]
}

lk_assert_not_root
lk_assert_is_arch

# Try to detect missing settings
if ! lk_is_bootstrap; then
    [ -n "${LK_NODE_TIMEZONE-}" ] || ! _TZ=$(lk_system_timezone) ||
        set -- --set LK_NODE_TIMEZONE "$_TZ" "$@"
    [ -n "${LK_NODE_HOSTNAME-}" ] || ! _HN=$(lk_hostname) ||
        set -- --set LK_NODE_HOSTNAME "$_HN" "$@"
    [ -n "${LK_NODE_LOCALES+1}" ] ||
        set -- --set LK_NODE_LOCALES "en_AU.UTF-8 en_GB.UTF-8" "$@"
    [ -n "${LK_NODE_LANGUAGE+1}" ] ||
        set -- --set LK_NODE_LANGUAGE "en_AU:en_GB:en" "$@"
fi

SETTINGS_SH=$(lk_settings_getopt "$@")
eval "$SETTINGS_SH"
shift "$_LK_SHIFT"

lk_getopt -"$_LK_SHIFT"
eval "set -- $LK_GETOPT"

LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE-}}
if [ -n "$LK_PACKAGES_FILE" ]; then
    if [ ! -f "$LK_PACKAGES_FILE" ]; then
        FILE=${LK_PACKAGES_FILE##*/}
        FILE=${FILE#packages-arch-}
        FILE=${FILE%.sh}
        FILE=$LK_BASE/share/packages/arch/$FILE.sh
        [ -f "$FILE" ] || lk_die "file not found: $LK_PACKAGES_FILE"
        LK_PACKAGES_FILE=$FILE
    fi
    SETTINGS_SH=$(
        [ -z "${SETTINGS_SH:+1}" ] || cat <<<"$SETTINGS_SH"
        printf '%s=%q\n' LK_PACKAGES_FILE "$LK_PACKAGES_FILE"
    )
fi

lk_log_start
lk_start_trace

{
    lk_tty_log "Provisioning Arch Linux"
    lk_sudo_nopasswd_offer || lk_die "unable to run commands as root"
    ! lk_is_bootstrap || lk_tty_detail "Bootstrap environment detected"
    GROUP=$(id -gn)
    MEMORY=$(lk_system_memory 2)
    lk_tty_detail "System memory:" "${MEMORY}M"

    LK_SUDO=1
    LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-$(lk_is_bootstrap || echo 1)}
    LK_FILE_BACKUP_MOVE=1

    (LK_VERBOSE=1 &&
        lk_settings_persist "$SETTINGS_SH")

    ERRORS=()
    SERVICE_STARTED=()
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    DAEMON_RELOAD=

    if [ -n "${LK_NODE_TIMEZONE-}" ]; then
        lk_tty_print "Checking system time zone"
        FILE=/usr/share/zoneinfo/$LK_NODE_TIMEZONE
        lk_symlink "$FILE" /etc/localtime
    fi

    if [ ! -e /etc/adjtime ]; then
        lk_tty_print "Setting hardware clock"
        lk_tty_run_detail sudo hwclock --systohc
    fi

    lk_tty_print "Checking locales"
    lk_configure_locales

    lk_tty_print "Checking interfaces"
    systemctl_enable NetworkManager "Network Manager"
    unset LK_FILE_REPLACE_NO_CHANGE
    NM_DIR=/etc/NetworkManager/system-connections
    NM_EXT=.nmconnection
    ETHERNET=()
    WIFI=()
    UDEV_RULES=()
    IF_RENAME=()
    if ! lk_is_portable &&
        lk_require_output -q lk_system_list_ethernet_links -u; then
        NM_IGNORE="^$LK_h*(#|\$|(uuid|permissions|timestamp|method)=|\[proxy\])"
        BRIDGE=${LK_BRIDGE_INTERFACE-}
        BRIDGE_FILE=${BRIDGE:+$NM_DIR/$BRIDGE$NM_EXT}
        IPV4_IPV6=(
            "${LK_IPV4_ADDRESS-}"
            "${LK_IPV4_GATEWAY-}"
            "${LK_DNS_SERVERS-}"
            "${LK_DNS_SEARCH-}"
        )
        ETHERNET_NOW=($(lk_system_list_ethernet_links))
        ETHERNET_NOW=($(lk_system_sort_links "${ETHERNET_NOW[@]}"))
        IF_PREFIX=en
        IF_ARRAY=ETHERNET
        # Reverse the order to minimise *.nmconnection renaming collisions
        for i in $(lk_args "${!ETHERNET_NOW[@]}" | tac); do
            process_interface
            FILE=$NM_DIR/$IF_NAME$NM_EXT
            [ "$IF" = "$IF_NAME" ] || {
                # If this interface has a connection profile, try to rename it
                PREV_FILE=$NM_DIR/$IF$NM_EXT
                ! sudo test -e "$PREV_FILE" -a ! -e "$FILE" || {
                    LK_FILE_REPLACE_NO_CHANGE=0
                    lk_tty_run_detail sudo mv -n "$PREV_FILE" "$FILE"
                }
            }
            # Install a connection profile for this interface and/or the bridge
            # interface
            lk_install -m 00600 "$FILE"
            case "$i${BRIDGE:+b}" in
            0)
                lk_file_replace -i "$NM_IGNORE" "$FILE" \
                    < <(lk_nm_file_get_ethernet \
                        "$IF_NAME" "$IF_ADDRESS" "" "${IPV4_IPV6[@]}")
                ;;
            0b)
                lk_install -m 00600 "$BRIDGE_FILE"
                lk_file_replace -i "$NM_IGNORE" "$BRIDGE_FILE" \
                    < <(lk_nm_file_get_bridge \
                        "$BRIDGE" "$IF_ADDRESS" "${IPV4_IPV6[@]}" \
                        "${LK_BRIDGE_IPV6_PD:+$(lk_nm_is_running &&
                            nmcli -g ipv6.method connection show "$BRIDGE" 2>/dev/null |
                            grep -Fx ignore ||
                            echo shared)}")
                lk_file_replace -i "$NM_IGNORE" "$FILE" \
                    < <(lk_nm_file_get_ethernet \
                        "$IF_NAME" "$IF_ADDRESS" "$BRIDGE")
                ;;
            *)
                # Don't change existing settings for interfaces above en0
                sudo test -s "$FILE" || {
                    lk_file_replace -i "$NM_IGNORE" "$FILE" \
                        < <(lk_nm_file_get_ethernet \
                            "$IF_NAME" "$IF_ADDRESS")
                }
                ;;
            esac
            # Delete any other connections using the MAC address of this
            # interface
            lk_mapfile -z NM_FILES <(
                sudo find "$NM_DIR" -maxdepth 1 -type f -name "*$NM_EXT" \
                    ! -name "$IF_NAME$NM_EXT" \
                    ${BRIDGE:+! -name "$BRIDGE$NM_EXT"} \
                    -execdir grep -Eiq "\\<mac-address$LK_h*=$LK_h*$IF_ADDRESS$LK_h*\$" \
                    '{}' \; -print0
            )
            [ ${#NM_FILES[@]} -eq 0 ] || {
                LK_FILE_REPLACE_NO_CHANGE=0
                lk_file_backup "${NM_FILES[@]}" &&
                    lk_tty_run_detail sudo rm "${NM_FILES[@]}"
            }
        done
    fi
    if lk_require_output -q lk_system_list_wifi_links -u; then
        WIFI_NOW=($(lk_system_list_wifi_links))
        WIFI_NOW=($(lk_system_sort_links "${WIFI_NOW[@]}"))
        IF_PREFIX=wl
        IF_ARRAY=WIFI
        for i in "${!WIFI_NOW[@]}"; do
            process_interface
            [ "$IF" = "$IF_NAME" ] || {
                # Update any connections that use the old interface name
                lk_mapfile -z NM_FILES <(
                    sudo find "$NM_DIR" -maxdepth 1 -type f -name "*$NM_EXT" \
                        -execdir grep -Fxq "interface-name=$IF" '{}' \; \
                        -print0
                )
                [ ${#NM_FILES[@]} -eq 0 ] || {
                    LK_FILE_REPLACE_NO_CHANGE=0
                    lk_file_backup "${NM_FILES[@]}" &&
                        lk_tty_run_detail lk_sudo sed -Ei \
                            "s/^(interface-name=)$IF\$/\\1$IF_NAME/" \
                            "${NM_FILES[@]}"
                }
            }
        done
    fi
    FILE=/etc/udev/rules.d/10-${LK_PATH_PREFIX}local.rules
    _FILE=$(lk_arr UDEV_RULES)
    lk_install -m 00644 "$FILE"
    lk_file_replace "$FILE" "$_FILE"
    if ! lk_is_bootstrap && lk_is_false LK_FILE_REPLACE_NO_CHANGE; then
        lk_systemctl_start NetworkManager
        if [ ${#IF_RENAME[@]} -gt 0 ]; then
            lk_maybe_trace bash -c "$(
                declare -f link_rename
                lk_quote_args link_rename "${IF_RENAME[@]}"
            )" || lk_die "interface rename failed"
            (
                # Reduce IF_RENAME to new Ethernet interfaces
                for ((i = 0; i < ${#IF_RENAME[@]}; i += 2)); do
                    unset "IF_RENAME[i]"
                done
                IF_RENAME=($(comm -12 \
                    <(lk_arr IF_RENAME | sort) \
                    <(lk_arr ETHERNET | sort)))
                [ ${#IF_RENAME[@]} -gt 0 ] || exit 0
                lk_tty_detail \
                    "Waiting for renamed Ethernet interfaces to settle"
                while :; do
                    sleep 2
                    ! lk_system_list_ethernet_links -u |
                        grep -Fxc -f <(lk_arr IF_RENAME) |
                        grep -Fx ${#IF_RENAME[@]} &>/dev/null ||
                        break
                done
            )
        fi
        lk_systemctl_restart NetworkManager &&
            nm-online -s -q || lk_die "error restarting NetworkManager"
    fi

    if lk_require_output -q lk_system_list_wifi_links &&
        lk_pac_installed crda; then
        lk_tty_print "Checking wireless regulatory domain"
        [[ ${LK_WIFI_REGDOM-} =~ ^(00|[A-Z]{2})?$ ]] ||
            lk_die "invalid regulatory domain: $LK_WIFI_REGDOM"
        FILE=/etc/conf.d/wireless-regdom
        lk_file_keep_original "$FILE"
        lk_file_replace "$FILE" < <(sed -E \
            -e 's/^[#[:blank:]]*(WIRELESS_REGDOM=)/#\1/' \
            -e "s/^#(WIRELESS_REGDOM=)([\"']?)(${LK_WIFI_REGDOM-})\\2$LK_h*\$/\\1\"\\3\"/" \
            "$FILE") || return
    fi

    lk_tty_print "Checking udev rules"
    unset LK_FILE_REPLACE_NO_CHANGE
    for _FILE in \
        "$LK_BASE/share/udev"/{keyboard-event,disable-webcam-sound,libvirt-guest-tap-unmanaged}*.rules; do
        FILE=${_FILE##*/}
        FILE=/etc/udev/rules.d/85-${LK_PATH_PREFIX}${FILE/.template./.}
        lk_install -m 00644 "$FILE"
        if [[ $_FILE == *.template.* ]]; then
            lk_file_replace "$FILE" < <(lk_expand_template "$_FILE")
        else
            lk_file_replace -f "$_FILE" "$FILE"
        fi
    done
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        lk_tty_run_detail sudo udevadm control --reload

    if [ -n "${LK_NODE_HOSTNAME-}" ]; then
        lk_tty_print "Checking system hostname"
        FILE=/etc/hostname
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$LK_NODE_HOSTNAME"

        lk_tty_print "Checking hosts file"
        FILE=/etc/hosts
        IP_ADDRESS=127.0.1.1
        [ ${#ETHERNET[@]} -eq 0 ] || {
            IP_ADDRESS=${LK_IPV4_ADDRESS:-127.0.1.1}
            IP_ADDRESS=${IP_ADDRESS%/*}
        }
        _FILE=$(HOSTS="# Generated by ${0##*/} at $(lk_date_log)
127.0.0.1 localhost
::1 localhost
$IP_ADDRESS \
${LK_NODE_FQDN:-$LK_NODE_HOSTNAME.localdomain} \
$LK_NODE_HOSTNAME" &&
            awk \
                -v "BLOCK=$HOSTS" \
                -v "FIRST=^(# Generated by |127.0.0.1 localhost($LK_h|\$))" \
                -v "LAST=^127.0.1.1 " \
                -v "BREAK=^$LK_h*\$" \
                -v "MAX_LINES=4" \
                -f "$LK_BASE/lib/awk/block-replace.awk" \
                "$FILE" && printf .)
        _FILE=${_FILE%.}
        lk_file_keep_original "$FILE"
        lk_file_replace -i "^(#|$LK_h*\$)" "$FILE" "$_FILE"
    else
        lk_tty_error \
            "Cannot check hostname or /etc/hosts: LK_NODE_HOSTNAME is not set"
    fi

    lk_tty_print "Checking systemd default target"
    lk_is_desktop &&
        DEFAULT_TARGET=graphical.target ||
        DEFAULT_TARGET=multi-user.target
    CURRENT_DEFAULT_TARGET=$(${_LK_BOOTSTRAP:+sudo} systemctl get-default)
    [ "$CURRENT_DEFAULT_TARGET" = "$DEFAULT_TARGET" ] ||
        lk_tty_run_detail sudo systemctl set-default "$DEFAULT_TARGET"

    lk_tty_print "Checking root account"
    lk_user_lock_passwd root

    lk_tty_print "Checking sudo"
    lk_sudo_apply_sudoers \
        "$LK_BASE/share/sudoers.d"/{default,default-arch}

    lk_tty_print "Checking default umask"
    FILE=/etc/profile.d/Z90-${LK_PATH_PREFIX}umask.sh
    lk_install -m 00644 "$FILE"
    lk_file_replace -f "$LK_BASE/share/profile.d/umask.sh" "$FILE"

    if [ -d /etc/polkit-1/rules.d ]; then
        lk_tty_print "Checking polkit rules"
        FILE=/etc/polkit-1/rules.d/49-wheel.rules
        # polkit fails with "error compiling script" unless file mode is 644
        lk_install -m 00644 "$FILE"
        lk_file_replace \
            -f "$LK_BASE/share/polkit-1/rules.d/default-arch.rules" \
            "$FILE"
    fi

    lk_tty_print "Checking kernel parameters"
    unset LK_FILE_REPLACE_NO_CHANGE
    for FILE in default.conf \
        $(! lk_node_is_router || echo router.conf) \
        $(lk_system_is_vm || echo sysrq.conf); do
        TARGET=/etc/sysctl.d/90-${FILE/default/${LK_PATH_PREFIX}default}
        FILE=$LK_BASE/share/sysctl.d/$FILE
        lk_install -m 00644 "$TARGET"
        lk_file_replace -f "$FILE" "$TARGET"
    done
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        sudo sysctl --system

    if lk_pac_installed tlp; then
        lk_tty_print "Checking TLP"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/tlp.d/90-${LK_PATH_PREFIX}default.conf
        lk_install -m 00644 "$FILE"
        FILES=("$LK_BASE/share/tlp.d"/*-{stable,quiet}-*.conf)
        ! lk_is_portable ||
            FILES+=("$LK_BASE/share/tlp.d"/*-battery-thresholds.conf)
        lk_feature_enabled minimal ||
            FILES+=("$LK_BASE/share/tlp.d"/*-maximum-performance.conf)
        lk_file_replace "$FILE" \
            < <(lk_arr FILES | sort | tr '\n' '\0' | xargs -0 cat)
        systemctl_mask systemd-rfkill.service
        systemctl_mask systemd-rfkill.socket
        systemctl_mask power-profiles-daemon.service
        file_delete "/etc/tlp.d/90-${LK_PATH_PREFIX}defaults.conf"
        SERVICE_ENABLE+=(
            NetworkManager-dispatcher "Network Manager dispatcher"
            tlp "TLP"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(tlp)
    fi

    lk_tty_print "Checking console display power management"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/systemd/system/setterm-enable-blanking.service
    lk_install -m 00644 "$FILE"
    lk_file_replace \
        -f "$LK_BASE/share/systemd/setterm-enable-blanking.service" \
        "$FILE"
    SERVICE_ENABLE+=(
        setterm-enable-blanking "setterm blanking"
    )
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE || {
        DAEMON_RELOAD=1
        SERVICE_RESTART+=(setterm-enable-blanking)
    }

    ROOT_DEVICE=$(findmnt --noheadings --target / --output SOURCE)
    if lk_block_device_is_ssd "$ROOT_DEVICE"; then
        lk_tty_print "Checking fstrim"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/systemd/system/fstrim.timer
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/systemd/fstrim.timer" "$FILE"
        SERVICE_ENABLE+=(
            fstrim.timer "fstrim"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            DAEMON_RELOAD=1
    fi

    lk_tty_print "Checking NTP"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/ntp.conf
    lk_file_keep_original "$FILE"
    _FILE=$(
        interfaces=$({
            ! lk_feature_enabled desktop ||
                ! lk_pac_installed libvirt ||
                printf '%s\n' 192.168.{122,100}.0/24
            [[ -z ${LK_BRIDGE_INTERFACE-} ]] ||
                printf '%s\n' "$LK_BRIDGE_INTERFACE"
            lk_system_list_physical_links
        } | lk_implode_input ,) &&
            awk -v server="${LK_NTP_SERVER-}" \
                -v interfaces="$interfaces" \
                -f "$LK_BASE/lib/awk/ntp-set-server.awk" \
                "$FILE"
    )
    lk_file_replace "$FILE" "$_FILE"
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        SERVICE_RESTART+=(ntpd)
    SERVICE_ENABLE+=(
        ntpd "NTP"
    )

    lk_tty_print "Checking SSH server"
    unset LK_FILE_REPLACE_NO_CHANGE
    LK_CONF_OPTION_FILE=/etc/ssh/sshd_config
    lk_ssh_set_option PermitRootLogin "no"
    [ ! -s ~/.ssh/authorized_keys ] ||
        lk_ssh_set_option PasswordAuthentication "no"
    lk_ssh_set_option AcceptEnv "LANG LC_*"
    SERVICE_ENABLE+=(
        sshd "SSH server"
    )
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        SERVICE_RESTART+=(sshd)

    ! lk_pac_installed kernel-modules-hook ||
        SERVICE_ENABLE+=(
            linux-modules-cleanup "Kernel modules cleanup"
        )

    service_apply

    if ! lk_is_bootstrap && lk_pac_installed grub; then
        lk_tty_print "Checking boot loader"
        unset LK_FILE_REPLACE_NO_CHANGE
        lk_arch_configure_grub
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            sudo update-grub --install
    fi

    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/mkinitcpio.conf
    if [ -f "$FILE" ] && lk_feature_enabled desktop &&
        lk_system_has_amd_graphics; then
        lk_tty_print "Checking" "$FILE"
        if ! grep -Eq '^MODULES=(.*\<amdgpu\>.*)' "$FILE"; then
            TEMP_FILE=$(lk_mktemp)
            lk_delete_on_exit "$TEMP_FILE"
            (
                unset MODULES
                . "$FILE"
                MODULES+=(amdgpu)
                sed -E 's/^(MODULES=\().*(\))/\1'"$(lk_sed_escape_replace \
                    "$(lk_quote_arr MODULES)")"'\2/' "$FILE"
            ) >"$TEMP_FILE"
            lk_file_keep_original "$FILE"
            lk_file_replace -f "$TEMP_FILE" "$FILE"
            ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
                sudo mkinitcpio -P
        fi
    fi

    lk_tty_print
    _LK_NO_LOG=1 \
        lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh"

    lk_tty_print
    lk_tty_log "Checking packages"
    lk_arch_configure_pacman
    [ -z "$LK_PACKAGES_FILE" ] ||
        . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/arch/packages.sh"

    # Avoid "unknown public key" errors
    unset LK_SUDO
    LK_CONF_OPTION_FILE=~/.gnupg/gpg.conf
    lk_install -d -m 00700 "${LK_CONF_OPTION_FILE%/*}"
    lk_install -m 00644 "$LK_CONF_OPTION_FILE"
    LK_FILE_KEEP_ORIGINAL=0
    if ! grep -q "\<auto-key-retrieve\>" "$LK_CONF_OPTION_FILE"; then
        lk_conf_enable_row auto-key-retrieve
    fi
    _LK_CONF_DELIM=" " \
        lk_conf_set_option keyserver hkps://keyserver.ubuntu.com
    unset LK_FILE_KEEP_ORIGINAL
    LK_SUDO=1

    if lk_has aur ||
        [ -n "${LK_ARCH_AUR_REPO_NAME-}" ] ||
        { [ ${#AUR_PACKAGES[@]} -gt 0 ] &&
            lk_tty_list AUR_PACKAGES \
                "To install from AUR:" package packages &&
            lk_tty_yn \
                "OK to install aurutils for AUR package management?" Y; }; then
        lk_tty_print "Checking AUR packages"
        PAC_INSTALL=($(lk_pac_not_installed_list \
            base-devel devtools vifm))
        [ ${#PAC_INSTALL[@]} -eq 0 ] || {
            lk_tty_detail "Installing aurutils dependencies"
            lk_faketty pacman -S --noconfirm "${PAC_INSTALL[@]}"
        }

        REPO=${LK_ARCH_AUR_REPO_NAME:-aur}
        DIR=$({ pacman-conf --repo="$REPO" |
            awk -F"$LK_h*=$LK_h*" '$1=="Server"{print$2}' |
            grep '^file://' |
            sed 's#^file://##'; } 2>/dev/null) && [ -d "$DIR" ] ||
            DIR=/srv/repo/$REPO
        FILE=$DIR/$REPO.db.tar.xz
        lk_tty_detail "Checking pacman repo at" "$DIR"
        lk_install -d -m 00755 -o "$USER" -g "$GROUP" "$DIR"
        [ -e "$FILE" ] ||
            (LK_SUDO= && lk_faketty repo-add "$FILE")

        lk_arch_add_repo "$REPO|file://$DIR"
        LK_CONF_OPTION_FILE=/etc/pacman.conf
        lk_conf_enable_row -s options "CacheDir = /var/cache/pacman/pkg/"
        lk_conf_enable_row -s options "CacheDir = $DIR/"
        _LK_CONF_DELIM=" = " \
            lk_conf_set_option -s options CleanMethod KeepCurrent

        if ! lk_has aur ||
            ! lk_pac_repo_available_list "$REPO" |
            grep -Fx aurutils >/dev/null; then
            lk_tty_detail "Building aurutils"
            PKGDEST=$DIR lk_makepkg -a aurutils --force
            lk_test_all_f "${LK_MAKEPKG_LIST[@]}" ||
                lk_die "not found: ${LK_MAKEPKG_LIST[*]}"
            (LK_SUDO= &&
                lk_faketty repo-add --remove "$FILE" "${LK_MAKEPKG_LIST[@]}")
            lk_tty_detail "Installing aurutils"
            lk_pac_sync -f
            lk_faketty pacman -S --noconfirm "$REPO/aurutils"
        fi

        FILE=/etc/aurutils/pacman-$REPO.conf
        _FILE=$(cat /usr/share/devtools/pacman.conf.d/extra.conf &&
            printf '\n[%s]\n' "$REPO" &&
            pacman-conf --repo="$REPO")
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$_FILE"

        unset LK_SUDO
        LK_CONF_OPTION_FILE=~/.gnupg/gpg-agent.conf
        lk_install -m 00644 "$LK_CONF_OPTION_FILE"
        LK_FILE_KEEP_ORIGINAL=0
        if ! grep -q "\<allow-preset-passphrase\>" "$LK_CONF_OPTION_FILE"; then
            lk_conf_enable_row allow-preset-passphrase
            _LK_CONF_DELIM=" " \
                lk_conf_set_option max-cache-ttl 86400
        fi
        unset LK_FILE_KEEP_ORIGINAL
        LK_SUDO=1

        if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
            lk_aur_sync -g "${AUR_PACKAGES[@]}" ||
                ERRORS+=("Failed to sync from AUR: ${FAILED[*]}")
            ! lk_aur_can_chroot || lk_pac_sync -f
            PAC_PACKAGES+=($(comm -12 \
                <({ echo aurutils && lk_arr AUR_PACKAGES; } | sort -u) \
                <(lk_pac_repo_available_list "$REPO" | sort -u)))
            AUR_PACKAGES=()
        fi
    fi

    if [ ${#PAC_OFFER[@]} -gt 0 ]; then
        PAC_OFFER=($(lk_pac_installed_list "${PAC_OFFER[@]}"))
    fi
    _PAC_KEEP=($(lk_arr PAC_OFFER | sed -E '/^aurutils$/d'))

    lk_tty_print "Checking install reasons"
    PAC_EXPLICIT=($(lk_arr PAC_PACKAGES AUR_PACKAGES PAC_OFFER | sort -u))
    PAC_MARK_EXPLICIT=($(lk_pac_installed_not_explicit "${PAC_EXPLICIT[@]}"))
    PAC_UNMARK_EXPLICIT=($(comm -13 \
        <(lk_arr PAC_EXPLICIT) \
        <(lk_pac_installed_explicit | sort -u)))
    [ ${#PAC_MARK_EXPLICIT[@]} -eq 0 ] ||
        lk_log_bypass lk_faketty \
            pacman -D --asexplicit "${PAC_MARK_EXPLICIT[@]}"
    [ ${#PAC_UNMARK_EXPLICIT[@]} -eq 0 ] ||
        lk_log_bypass lk_faketty \
            pacman -D --asdeps "${PAC_UNMARK_EXPLICIT[@]}"

    REMOVE_MESSAGE=()
    if PAC_REMOVE=($(pacman -Qdttq | grep -Fxvf <(lk_arr PAC_EXCEPT))); then
        lk_whiptail_build_list PAC_REMOVE '' "${PAC_REMOVE[@]}"
        lk_mapfile PAC_REMOVE <(lk_whiptail_checklist "Orphaned packages" \
            "Selected packages will be removed:" "${PAC_REMOVE[@]}" off)
        [ ${#PAC_REMOVE[@]} -eq 0 ] || {
            lk_tty_list PAC_REMOVE "Orphaned:" package packages
            REMOVE_MESSAGE+=("orphaned")
        }
    fi
    [ ${#PAC_EXCEPT[@]} -eq 0 ] ||
        PAC_EXCEPT=($(lk_pac_installed_list "${PAC_EXCEPT[@]}"))
    [ ${#PAC_EXCEPT[@]} -eq 0 ] || {
        REMOVE_MESSAGE+=("blacklisted")
        PAC_REMOVE+=("${PAC_EXCEPT[@]}")
    }
    [ ${#PAC_REMOVE[@]} -eq 0 ] || {
        lk_tty_print \
            "Removing $(lk_implode_arr " and " REMOVE_MESSAGE) packages"
        lk_log_bypass lk_faketty pacman -Rdds --noconfirm "${PAC_REMOVE[@]}"
    }

    [ ${#_PAC_KEEP[@]} -eq 0 ] ||
        lk_tty_list _PAC_KEEP "Not uninstalling:" package packages
    PAC_INSTALL=($(comm -23 \
        <(lk_arr PAC_PACKAGES | sort -u) \
        <(lk_pac_installed_list | sort -u)))
    if [ ${#PAC_INSTALL[@]} -gt 0 ]; then
        PAC_INSTALL=(
            $(pacman -Sp --print-format "%n %r/%n-%v" "${PAC_INSTALL[@]}" |
                # Remove dependencies from `pacman -Sp` output
                sort | grep -E "^$(lk_ere_implode_args -- "${PAC_INSTALL[@]}") ")
        )
        lk_mapfile PAC_INSTALL <(lk_whiptail_checklist "Installing packages" \
            "Selected packages will be installed:" "${PAC_INSTALL[@]}")
        [ ${#PAC_INSTALL[@]} -eq 0 ] ||
            lk_tty_list PAC_INSTALL "Installing:" package packages
    fi
    _PAC_UPGRADE=($(pacman -Suup --print-format "%n %r/%n-%v" | sort))
    PAC_UPGRADE=()
    if [ ${#_PAC_UPGRADE[@]} -gt 0 ]; then
        lk_mapfile PAC_UPGRADE <(lk_whiptail_checklist "Upgrading packages" \
            "Selected packages will be upgraded:" "${_PAC_UPGRADE[@]}")
        PAC_IGNORE=($(comm -23 \
            <(lk_arr _PAC_UPGRADE | awk 'NR % 2' | sort -u) \
            <(lk_arr PAC_UPGRADE | sort -u)))
        [ ${#PAC_UPGRADE[@]} -eq 0 ] ||
            lk_tty_list PAC_UPGRADE "Upgrading:" package packages
        [ ${#PAC_IGNORE[@]} -eq 0 ] ||
            lk_tty_list PAC_IGNORE "Not upgrading:" package packages
    fi
    [ ${#PAC_INSTALL[@]}${#PAC_UPGRADE[@]} = 00 ] || (
        IFS=,
        lk_log_bypass lk_faketty \
            pacman -Suu --noconfirm --ignore "${PAC_IGNORE[*]-}" "${PAC_INSTALL[@]}"
    )

    lk_symlink_bin codium code || true
    lk_symlink_bin vim vi || true
    lk_symlink_bin xfce4-terminal xterm || true
    lk_symlink_bin yad zenity || true

    lk_tty_print
    lk_tty_log "Checking installed packages and services"
    SERVICE_ENABLE+=(
        lightdm "LightDM"
        cups "CUPS"
        atd "at"
        cronie "cron"
    )

    if lk_pac_installed logrotate; then
        FILE=/etc/logrotate.d/lk-platform
        DIR=$(lk_double_quote "$LK_BASE/var/log")
        GROUP=$(lk_file_group "$LK_BASE")
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" < <(LK_PLATFORM_LOGS="$DIR/*.log" \
            LK_PLATFORM_OWNER="root $GROUP" \
            lk_expand_template "$LK_BASE/share/logrotate.d/default.template")
    fi

    if lk_pac_installed fail2ban; then
        unset LK_FILE_REPLACE_NO_CHANGE
        _FILE=$LK_BASE/share/fail2ban/default-arch.conf
        FILE=/etc/fail2ban/jail.local
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$_FILE" "$FILE"
        SERVICE_ENABLE+=(
            fail2ban "Fail2ban"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(fail2ban)
    fi

    if lk_pac_installed mariadb; then
        sudo test -d /var/lib/mysql/mysql ||
            sudo mariadb-install-db \
                --user=mysql \
                --basedir=/usr \
                --datadir=/var/lib/mysql
        SERVICE_ENABLE+=(
            mariadb "MariaDB"
        )
    fi

    if lk_pac_installed php; then
        for DIR in /etc/php84 /etc/php83 /etc/php82 /etc/php81 /etc/php80 /etc/php74 /etc/php; do
            unset LK_FILE_REPLACE_NO_CHANGE
            FILE=$DIR/php.ini
            CLI_FILE=$DIR/php-cli.ini
            [ -f "$FILE" ] || continue
            [ -f "$CLI_FILE" ] ||
                sudo cp -a "$(lk_readable "$FILE.orig" "$FILE")" "$CLI_FILE"
            for LK_CONF_OPTION_FILE in "$FILE" "$CLI_FILE"; do
                [[ $LK_CONF_OPTION_FILE != "$CLI_FILE" ]] || {
                    lk_php_set_option memory_limit -1
                    lk_php_set_option short_open_tag On
                }
                PHP_EXT=(
                    bcmath
                    curl
                    exif
                    gd
                    gettext
                    iconv
                    igbinary.so
                    imagick
                    intl
                    memcache.so
                    memcached.so
                    mysqli
                    pcov
                    pdo_sqlite
                    soap
                    sodium
                    sqlite3
                    zip
                )
                [[ $DIR != *74 ]] || PHP_EXT+=(imap)
                for EXT in ${PHP_EXT+"${PHP_EXT[@]}"}; do
                    FILES=("$DIR"/conf.d/?([0-9][0-9]-)"${EXT%.*}".ini)
                    [[ -f ${FILES-} ]] || unset FILES
                    ! grep -Eq "^$LK_h*extension$LK_h*=$LK_h*$EXT(\\.so)?$LK_h*(\$|;)" \
                        "$LK_CONF_OPTION_FILE" \
                        ${FILES+"$FILES"} || continue
                    # Require a disabled entry
                    grep -Eq "^$LK_h*;$LK_h*extension$LK_h*=$LK_h*$EXT(\\.so)?$LK_h*(\$|;)" \
                        "$LK_CONF_OPTION_FILE" \
                        ${FILES+"$FILES"} || continue
                    lk_php_enable_option extension "$EXT" ${FILES+"$FILES"}
                done
                FILE=$DIR/conf.d/imagick.ini
                [ ! -f "$FILE" ] || lk_php_set_option \
                    imagick.skip_version_check 1 "$FILE"
                if lk_is_desktop; then
                    lk_php_set_option error_reporting E_ALL
                    lk_php_set_option display_errors On
                    lk_php_set_option display_startup_errors On
                    lk_php_set_option log_errors On
                    lk_php_set_option error_log syslog

                    (
                        LK_CONF_OPTION_FILE=$DIR/conf.d/xdebug.ini
                        [ -f "$LK_CONF_OPTION_FILE" ] || exit 0
                        lk_install -d -m 01777 ~/.xdebug
                        lk_php_set_option xdebug.output_dir ~/.xdebug
                        # Alternative values: profile, trace
                        lk_php_set_option xdebug.mode debug
                        lk_php_set_option xdebug.start_with_request trigger
                        lk_php_set_option xdebug.profiler_output_name callgrind.out.%H.%R.%u
                        lk_php_set_option xdebug.collect_return On
                        lk_php_set_option xdebug.trace_output_name trace.%H.%R.%u
                        #lk_php_enable_option zend_extension xdebug.so
                    )
                fi
            done
        done
        file_delete "${LK_BIN_DIR:-/usr/local/bin}/wp"
    fi

    if lk_pac_installed php-fpm apache; then
        lk_install -d -m 00700 -o http -g http /var/cache/php/opcache
        lk_php_set_option opcache.file_cache /var/cache/php/opcache
        lk_php_set_option opcache.validate_permission On
        lk_php_enable_option zend_extension opcache
        if lk_is_desktop; then
            lk_php_set_option max_execution_time 0
            lk_php_set_option opcache.enable Off
        fi
        lk_install -d -m 00775 -o root -g http /var/log/php-fpm
        FILE=/etc/logrotate.d/php-fpm
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" <<"EOF"
/var/log/php-fpm/*.access.log {
    missingok
    sharedscripts
    su root root
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
}
/var/log/php-fpm/*.error.log {
    missingok
    sharedscripts
    su http http
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
}
EOF
        LK_CONF_OPTION_FILE=/etc/php/php-fpm.d/www.conf
        lk_php_set_option pm static
        lk_php_set_option pm.status_path /php-fpm-status
        lk_php_set_option ping.path /php-fpm-ping
        lk_php_set_option access.log '/var/log/php-fpm/php-fpm-$pool.access.log'
        lk_php_set_option access.format '"%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'
        lk_php_set_option catch_workers_output yes
        lk_php_set_option 'php_admin_value[error_log]' '/var/log/php-fpm/php-fpm-$pool.error.log'
        lk_php_set_option 'php_admin_flag[log_errors]' On
        lk_php_set_option 'php_admin_flag[display_errors]' Off
        lk_php_set_option 'php_admin_flag[display_startup_errors]' Off
        if lk_is_desktop; then
            lk_php_set_option pm.max_children 5
            lk_php_set_option pm.max_requests 0
            lk_php_set_option request_terminate_timeout 0
        else
            lk_php_set_option pm.max_children 30
            lk_php_set_option pm.max_requests 10000
            lk_php_set_option request_terminate_timeout 300
        fi
        SERVICE_ENABLE+=(
            php-fpm "PHP-FPM"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(php-fpm)

        unset LK_FILE_REPLACE_NO_CHANGE
        LK_CONF_OPTION_FILE=/etc/httpd/conf/httpd.conf
        lk_install -d -m 00755 -o "$USER" -g "$GROUP" /srv/http/{,localhost/{,html},127.0.0.1}
        [ -e /srv/http/127.0.0.1/html ] ||
            ln -sfT ../localhost/html /srv/http/127.0.0.1/html
        lk_httpd_enable_option LoadModule "alias_module modules/mod_alias.so"
        lk_httpd_enable_option LoadModule "dir_module modules/mod_dir.so"
        lk_httpd_enable_option LoadModule "headers_module modules/mod_headers.so"
        lk_httpd_enable_option LoadModule "http2_module modules/mod_http2.so"
        lk_httpd_enable_option LoadModule "info_module modules/mod_info.so"
        lk_httpd_enable_option LoadModule "rewrite_module modules/mod_rewrite.so"
        lk_httpd_enable_option LoadModule "status_module modules/mod_status.so"
        lk_httpd_enable_option LoadModule "vhost_alias_module modules/mod_vhost_alias.so"
        if lk_is_desktop; then
            FILE=/etc/httpd/conf/extra/${LK_PATH_PREFIX}default-dev-arch.conf
            lk_install -m 00644 "$FILE"
            lk_file_replace \
                -f "$LK_BASE/share/httpd/default-dev-arch.conf" \
                "$FILE"
            lk_httpd_enable_option Include "${FILE#/etc/httpd/}"
            lk_httpd_enable_option LoadModule "proxy_module modules/mod_proxy.so"
            lk_httpd_enable_option LoadModule "proxy_fcgi_module modules/mod_proxy_fcgi.so"
            lk_user_in_group http ||
                sudo usermod --append --groups http "$USER"
            lk_user_in_group "$GROUP" http ||
                sudo usermod --append --groups "$GROUP" http
            lk_httpd_remove_option Include conf/extra/httpd-dev-defaults.conf
            file_delete /etc/httpd/conf/extra/httpd-dev-defaults.conf
        fi
        SERVICE_ENABLE+=(
            httpd "Apache"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(httpd)

        lk_git_provision_repo -fs \
            -o "$USER:adm" \
            -n "opcache-gui" \
            https://github.com/lkrms/opcache-gui.git \
            /opt/opcache-gui
    fi

    if lk_pac_installed lighttpd; then
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/systemd/system/lighttpd.service.d/override.conf
        lk_install -d -m 00755 "${FILE%/*}"
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" <<EOF
# If a reverse proxy with a hostname is enabled, lighttpd will go down with
# "Temporary failure in name resolution" if started too early
[Unit]
Wants=network-online.target
After=network-online.target

[Service]
RestartSec=10
EOF
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            DAEMON_RELOAD=1
        DIR=/etc/lighttpd/conf.d
        lk_install -d -m 00755 "$DIR"
        LK_CONF_OPTION_FILE=/etc/lighttpd/lighttpd.conf
        lk_conf_enable_row \
            "include_shell \"for f in /etc/lighttpd/conf.d/*.conf;do \
[ -f \\\"\$f\\\" ]||continue;\
printf 'include \\\"%s\\\"\\n' \\\"\${f#/etc/lighttpd/}\\\";\
done\""
        FILE=$DIR/00-${LK_PATH_PREFIX}default.conf
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/lighttpd/default-arch.conf" "$FILE"
        for FILE in reverse-proxy.sh simple-vhost.sh; do
            lk_symlink "$LK_BASE/share/lighttpd/$FILE" "$DIR/$FILE"
        done
        for FILE in 40-access_log.conf 40-mime.conf 60-status.conf; do
            _FILE=/usr/share/doc/lighttpd/config/conf.d/${FILE#*-}
            [ -f "$_FILE" ] || lk_warn "file not found: $_FILE" || continue
            FILE=$DIR/$FILE
            lk_install -m 00644 "$FILE"
            lk_file_replace "$FILE" < <(sed -E \
                "s/^($LK_h*mimetype.assign$LK_h*)\+?=($LK_h*\($LK_h*)/\1:=\2/" "$_FILE")
        done
        SERVICE_ENABLE+=(
            lighttpd "Lighttpd"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(lighttpd)
    fi

    if lk_pac_installed squid; then
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/squid/squid.conf
        grep -Eq "^$LK_h*cache_dir$LK_h+" "$FILE" || lk_squid_set_option \
            cache_dir "aufs /var/cache/squid 20000 16 256" "$FILE"
        lk_user_in_group proxy ||
            sudo usermod --append --groups proxy "$USER"
        SERVICE_ENABLE+=(
            squid "Squid proxy server"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE || {
            lk_systemctl_stop squid &&
                sudo squid -zN &>/dev/null || lk_die \
                "error creating Squid swap directories and cache_dir structures"
            SERVICE_RESTART+=(squid)
        }
        lk_is_bootstrap ||
            lk_systemctl_disable_now squid-rotate.timer
        FILE=/etc/logrotate.d/squid
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/logrotate.d/squid-arch" "$FILE"
    fi

    if lk_pac_installed bluez; then
        SERVICE_ENABLE+=(
            bluetooth "Bluetooth"
        )
    fi

    if lk_pac_installed libvirt; then
        lk_user_in_group libvirt && lk_user_in_group kvm ||
            sudo usermod --append --groups libvirt,kvm "$USER"

        unset LK_FILE_REPLACE_NO_CHANGE
        LK_CONF_OPTION_FILE=/etc/libvirt/network.conf
        _LK_CONF_DELIM=" = " \
            lk_conf_set_option firewall_backend '"iptables"'
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(libvirtd)

        LK_CONF_OPTION_FILE=/etc/conf.d/libvirt-guests
        lk_conf_set_option URIS default
        lk_conf_set_option PARALLEL_SHUTDOWN 4
        if lk_is_desktop; then
            lk_conf_set_option ON_BOOT ignore
            lk_conf_set_option SHUTDOWN_TIMEOUT 120
            FILE=/etc/qemu/bridge.conf
            lk_install -d -m 00755 "${FILE%/*}"
            lk_install -m 00644 "$FILE"
            lk_file_replace "$FILE" "allow all"
        else
            lk_conf_set_option ON_BOOT start
            lk_conf_set_option SHUTDOWN_TIMEOUT 300
        fi
        lk_conf_set_option ON_SHUTDOWN shutdown
        lk_conf_set_option SYNC_TIME 1

        ! memory_at_least 7 || SERVICE_ENABLE+=(
            libvirtd "libvirt"
            libvirt-guests "libvirt-guests"
        )
    fi

    if lk_pac_installed docker; then
        FILE=/etc/docker/daemon.json
        lk_node_is_router &&
            JQ='. + {"iptables":false,"ip6tables":false}' ||
            JQ='del(.iptables,.ip6tables)'
        lk_mktemp_with _FILE jq "$JQ" < <(
            if [[ -e $FILE ]]; then
                cat "$FILE"
            else
                echo "{}"
            fi
        )
        if [[ ! -e $FILE ]] ||
            ! diff -q <(jq <"$FILE") "$_FILE" >/dev/null; then
            lk_install -d -m 00755 "${FILE%/*}"
            lk_install -m 00644 "$FILE"
            lk_file_replace -f "$_FILE" "$FILE"
            SERVICE_RESTART+=(docker)
        fi
        lk_user_in_group docker ||
            sudo usermod --append --groups docker "$USER"
        ! memory_at_least 7 || SERVICE_ENABLE+=(
            docker "Docker"
        )
    fi

    if lk_pac_installed xfce4-session; then
        lk_symlink_bin "$LK_BASE/lib/xfce4/startxfce4"
        SOCKET=gcr-ssh-agent.socket
        if [[ -e /usr/lib/systemd/user/$SOCKET ]] &&
            [[ ! -e /etc/systemd/user/sockets.target.wants/$SOCKET ]]; then
            sudo systemctl enable --global "$SOCKET"
        fi
    fi

    if lk_pac_installed samba; then
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/samba/smb.conf
        lk_install -m 00644 "$FILE"
        lk_file_replace -mi "^(#|;|$LK_h*\$)" "$FILE" < <(
            lk_mktemp_with TEMP &&
                { LK_SMB_WORKGROUP=${LK_SMB_WORKGROUP:-WORKGROUP} \
                    lk_expand_template "$LK_BASE/share/samba/${LK_SMB_CONF:-standalone}.smb.t.conf" &&
                    { [[ ! -e $FILE ]] || cat "$FILE"; }; } >"$TEMP" &&
                testparm --suppress-prompt "$TEMP" 2>/dev/null
        )
        SERVICE_ENABLE+=(
            smb "Samba (SMB server)"
            nmb "Samba (NMB server)"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(smb nmb)
        sudo pdbedit -L | cut -d: -f1 | grep -Fx "$USER" >/dev/null ||
            lk_tty_detail \
                "User '$USER' not found in Samba user database. To fix, run:" \
                $'\n'"sudo smbpasswd -a $USER"
    fi

    service_apply || true

    if [ ${#ERRORS[@]} -eq 0 ]; then
        lk_tty_success "Provisioning complete"
    else
        lk_tty_error "Provisioning completed with errors"
        for ERROR in "${ERRORS[@]}"; do
            lk_tty_detail "$ERROR"
        done
        lk_die ""
    fi

    ! lk_arch_reboot_required || {
        lk_tty_print
        lk_tty_warning "Reboot required"
        lk_tty_yn "Reboot now?" N -t 5 || exit 0
        sudo shutdown -r now
    }

    exit
}

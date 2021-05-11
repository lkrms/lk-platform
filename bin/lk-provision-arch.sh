#!/bin/bash

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

shopt -s nullglob

. "$LK_BASE/lib/bash/common.sh"
lk_include arch git linux provision

! lk_in_chroot || _LK_BOOTSTRAP=1

if lk_is_bootstrap; then
    function systemctl_enable() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        [ ! -e "/usr/lib/systemd/system/$1" ] &&
            [ ! -e "/etc/systemd/system/$1" ] || {
            lk_console_detail "Enabling service:" "${2:-$1}"
            sudo systemctl enable "$1"
        }
    }
    function systemctl_mask() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        lk_console_detail "Masking service:" "${2:-$1}"
        sudo systemctl mask "$1"
    }
    function lk_systemctl_stop() {
        true
    }
    lk_console_blank
else
    function systemctl_enable() {
        local NO_START_REGEX='\<NetworkManager-dispatcher\>'
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
    local i EXIT_STATUS=0
    lk_console_message "Checking services"
    lk_is_bootstrap || ! lk_is_true DAEMON_RELOAD ||
        lk_run_detail sudo systemctl daemon-reload || EXIT_STATUS=$?
    [ ${#SERVICE_ENABLE[@]} -eq 0 ] ||
        for i in $(seq 0 2 $((${#SERVICE_ENABLE[@]} - 1))); do
            systemctl_enable "${SERVICE_ENABLE[@]:$i:2}" || EXIT_STATUS=$?
        done
    lk_is_bootstrap || [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
        SERVICE_RESTART=($(comm -23 \
            <(lk_echo_array SERVICE_RESTART | sort -u) \
            <(lk_echo_array SERVICE_STARTED | sort -u))) && {
            [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
                lk_console_message "Restarting services with changed settings"
                for SERVICE in "${SERVICE_RESTART[@]}"; do
                    lk_systemctl_restart "$SERVICE" || EXIT_STATUS=$?
                done
            } || EXIT_STATUS=$?
        }
    }
    DAEMON_RELOAD=
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    SERVICE_STARTED=()
    return "$EXIT_STATUS"
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

function link_rename() {
    . "$LK_BASE/lib/bash/include/core.sh"
    lk_run_detail udevadm control -R
    while [ $# -ge 2 ]; do
        lk_run_detail ip link set "$1" down &&
            lk_run_detail ip link set "$1" name "$2" &&
            lk_run_detail ip link set "$2" up ||
            return
        shift 2
    done
}

function link_reset() {
    . "$LK_BASE/lib/bash/include/core.sh"
    local BRIDGE DEV ACTIVE_UUID UUID
    [ "${1:-}" != -b ] || { BRIDGE=$2 && shift 2; }
    lk_run_detail nmcli connection reload
    for DEV in "$@"; do
        ! ACTIVE_UUID=$(lk_nm_active_connection_uuid "$DEV") ||
            { UUID=$(lk_nm_connection_uuid "$DEV") &&
                [ "$ACTIVE_UUID" = "$UUID" ]; } ||
            lk_run_detail nmcli connection down "$ACTIVE_UUID" || return
    done
    if [ -n "${BRIDGE:-}" ]; then
        lk_run_detail nmcli connection up "$BRIDGE" || return
    fi
    for DEV in "$@"; do
        grep -Fxq 1 "/sys/class/net/$DEV/carrier" 2>/dev/null ||
            lk_console_warning \
                "Not bringing connection up (no carrier):" "$DEV" ||
            continue
        lk_run_detail nmcli connection up "$DEV" || return
    done
}

function memory_at_least() {
    [ "${_LK_SYSTEM_MEMORY:=$(lk_system_memory)}" -ge "$1" ]
}

lk_assert_not_root
lk_assert_is_arch

# Try to detect missing settings
if ! lk_is_bootstrap; then
    [ -n "${LK_NODE_TIMEZONE:-}" ] || ! _TZ=$(lk_system_timezone) ||
        set -- --set LK_NODE_TIMEZONE "$_TZ" "$@"
    [ -n "${LK_NODE_HOSTNAME:-}" ] || ! _HN=$(lk_hostname) ||
        set -- --set LK_NODE_HOSTNAME "$_HN" "$@"
    [ -n "${LK_NODE_LOCALES+1}" ] ||
        set -- --set LK_NODE_LOCALES "en_AU.UTF-8 en_GB.UTF-8" "$@"
    [ -n "${LK_NODE_LANGUAGE+1}" ] ||
        set -- --set LK_NODE_LANGUAGE "en_AU:en_GB:en" "$@"
fi

SETTINGS_SH=$(lk_settings_getopt)
eval "$SETTINGS_SH"
shift "$_LK_SHIFT"

lk_getopt
eval "set -- $LK_GETOPT"

lk_sudo_offer_nopasswd || lk_die "unable to run commands as root"

LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE:-}}
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
lk_log_tty_stdout_off
lk_start_trace

{
    lk_console_log "Provisioning Arch Linux"
    ! lk_is_bootstrap || lk_console_detail "Bootstrap environment detected"
    GROUP=$(id -gn)
    MEMORY=$(lk_system_memory 2)
    lk_console_detail "System memory:" "${MEMORY}M"

    LK_SUDO=1
    LK_FILE_BACKUP_TAKE=${LK_FILE_BACKUP_TAKE-$(lk_is_bootstrap || echo 1)}
    LK_FILE_BACKUP_MOVE=1

    LK_VERBOSE=1 \
        lk_settings_persist "$SETTINGS_SH"

    EXIT_STATUS=0
    SERVICE_STARTED=()
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    DAEMON_RELOAD=

    if [ -n "${LK_NODE_TIMEZONE:-}" ]; then
        lk_console_message "Checking system time zone"
        FILE=/usr/share/zoneinfo/$LK_NODE_TIMEZONE
        lk_symlink "$FILE" /etc/localtime
    fi

    if [ ! -e /etc/adjtime ]; then
        lk_console_message "Setting hardware clock"
        lk_run_detail sudo hwclock --systohc
    fi

    lk_console_message "Checking locales"
    lk_configure_locales

    lk_console_message "Checking interfaces"
    systemctl_enable NetworkManager "Network Manager"
    ETHERNET=()
    if lk_require_output -q lk_system_list_ethernet_links -u; then
        unset LK_FILE_REPLACE_NO_CHANGE
        NM_DIR=/etc/NetworkManager/system-connections
        NM_EXT=.nmconnection
        NM_IGNORE="^$S*(#|\$|uuid=)"
        BRIDGE=${LK_BRIDGE_INTERFACE:-}
        BRIDGE_FILE=${BRIDGE:+$NM_DIR/$BRIDGE$NM_EXT}
        IPV4=(
            "${LK_IPV4_ADDRESS:-}"
            "${LK_IPV4_GATEWAY:-}"
            "${LK_IPV4_DNS_SERVER:-}"
            "${LK_IPV4_DNS_SEARCH:-}"
        )
        ETHERNET_NOW=($(lk_system_list_ethernet_links))
        ETHERNET_NOW=($(lk_system_sort_links "${ETHERNET_NOW[@]}"))
        UDEV_RULES=()
        IF_RENAME=()
        # Reverse the order to minimise *.nmconnection renaming collisions
        for i in $(lk_echo_args "${!ETHERNET_NOW[@]}" | tac); do
            IF=${ETHERNET_NOW[$i]}
            IF_PATH=/sys/class/net/$IF
            IF_ADDRESS=$(<"$IF_PATH/address")
            IF_NAME=en$i
            ETHERNET[$i]=$IF_NAME
            FILE=$NM_DIR/$IF_NAME$NM_EXT
            UDEV_RULES[$i]=$(printf \
                'SUBSYSTEM=="net", DEVPATH!="*/virtual/*", ACTION=="add", ATTR{address}=="%s", NAME="%s"\n' \
                "$IF_ADDRESS" "$IF_NAME")
            if [ "$IF" != "$IF_NAME" ]; then
                # If this interface has a connection profile, try to rename it
                PREV_FILE=$NM_DIR/$IF$NM_EXT
                ! sudo test -e "$PREV_FILE" -a ! -e "$FILE" || {
                    LK_FILE_REPLACE_NO_CHANGE=0
                    lk_run_detail sudo mv -n "$PREV_FILE" "$FILE"
                }
                IF_RENAME+=("$IF" "$IF_NAME")
            fi
            # Install a connection profile for this interface and/or the bridge
            # interface
            lk_install -m 00600 "$FILE"
            case "$i${BRIDGE:+b}" in
            0)
                lk_file_replace -i "$NM_IGNORE" "$FILE" \
                    < <(lk_nm_file_get_ethernet \
                        "$IF_NAME" "$IF_ADDRESS" "" "${IPV4[@]}")
                ;;
            0b)
                lk_install -m 00600 "$BRIDGE_FILE"
                lk_file_replace -i "$NM_IGNORE" "$BRIDGE_FILE" \
                    < <(lk_nm_file_get_bridge \
                        "$BRIDGE" "$IF_ADDRESS" "${IPV4[@]}")
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
            eval "NM_FILES=($(
                sudo find "$NM_DIR" -maxdepth 1 -type f -name "*$NM_EXT" \
                    ! -name "$IF_NAME$NM_EXT" \
                    ${BRIDGE:+! -name "$BRIDGE$NM_EXT"} \
                    -execdir grep -Eiq "\\<mac-address$S*=$S*$IF_ADDRESS$S*\$" \
                    '{}' \; -print0 |
                    while IFS= read -rd '' LINE; do
                        printf '%q\n' "$LINE"
                    done
            ))"
            [ ${#NM_FILES[@]} -eq 0 ] || {
                LK_FILE_REPLACE_NO_CHANGE=0
                lk_file_backup "${NM_FILES[@]}" &&
                    lk_run_detail sudo rm "${NM_FILES[@]}"
            }
        done
        FILE=/etc/udev/rules.d/10-${LK_PATH_PREFIX}local.rules
        _FILE=$(lk_echo_array UDEV_RULES)
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$_FILE"
        if ! lk_is_bootstrap &&
            lk_is_false LK_FILE_REPLACE_NO_CHANGE &&
            { ! lk_arch_reboot_required ||
                lk_warn "reboot required to apply changes"; }; then
            lk_systemctl_start NetworkManager
            if [ ${#IF_RENAME[@]} -gt 0 ]; then
                lk_maybe_trace bash -c \
                    "$(declare -f link_rename); link_rename \"\$@\"" \
                    bash \
                    "${IF_RENAME[@]}" ||
                    lk_die "interface rename failed"
                lk_console_detail "Waiting for renamed interfaces to settle"
                while :; do
                    sleep 2
                    ! lk_system_list_ethernet_links -u |
                        grep -Fx -f <(lk_echo_array ETHERNET) >/dev/null ||
                        break
                done
            fi
            lk_maybe_trace bash -c \
                "$(declare -f lk_nm_is_running \
                    lk_nm_active_connection_uuid lk_nm_connection_uuid \
                    link_reset); link_reset \"\$@\"" \
                bash \
                ${BRIDGE:+-b "$BRIDGE"} "${ETHERNET[@]}" ||
                lk_die "interface reset failed"
        fi
    fi

    if [ -n "${LK_NODE_HOSTNAME:-}" ]; then
        lk_console_message "Checking system hostname"
        FILE=/etc/hostname
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$LK_NODE_HOSTNAME"

        lk_console_message "Checking hosts file"
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
                -v "HOSTS=$HOSTS" \
                -v "FIRST=^(# Generated by |127.0.0.1 localhost($S|\$))" \
                -v "LAST=^127.0.1.1 " \
                -v "BREAK=^$S*\$" \
                -v "MAX_LINES=4" \
                -f "$LK_BASE/lib/awk/hosts-update.awk" \
                "$FILE" && printf .)
        _FILE=${_FILE%.}
        lk_file_keep_original "$FILE"
        lk_file_replace -i "^(#|$S*\$)" "$FILE" "$_FILE"
    else
        lk_console_error \
            "Cannot check hostname or /etc/hosts: LK_NODE_HOSTNAME is not set"
    fi

    lk_console_message "Checking systemd default target"
    lk_is_desktop &&
        DEFAULT_TARGET=graphical.target ||
        DEFAULT_TARGET=multi-user.target
    CURRENT_DEFAULT_TARGET=$(${_LK_BOOTSTRAP:+sudo} systemctl get-default)
    [ "$CURRENT_DEFAULT_TARGET" = "$DEFAULT_TARGET" ] ||
        lk_run_detail sudo systemctl set-default "$DEFAULT_TARGET"

    lk_console_message "Checking root account"
    lk_user_lock_passwd root

    lk_console_message "Checking sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default-arch
    lk_install -m 00440 "$FILE"
    lk_file_replace -f "$LK_BASE/share/sudoers.d/default-arch" "$FILE"

    lk_console_message "Checking default umask"
    FILE=/etc/profile.d/Z90-${LK_PATH_PREFIX}umask.sh
    lk_install -m 00644 "$FILE"
    lk_file_replace -f "$LK_BASE/share/profile.d/umask.sh" "$FILE"

    if [ -d /etc/polkit-1/rules.d ]; then
        lk_console_message "Checking polkit rules"
        FILE=/etc/polkit-1/rules.d/49-wheel.rules
        # polkit fails with "error compiling script" unless file mode is 644
        lk_install -m 00644 "$FILE"
        lk_file_replace \
            -f "$LK_BASE/share/polkit-1/rules.d/default-arch.rules" \
            "$FILE"
    fi

    lk_console_message "Checking kernel parameters"
    unset LK_FILE_REPLACE_NO_CHANGE
    for FILE in default.conf $(lk_is_virtual || lk_echo_args sysrq.conf); do
        TARGET=/etc/sysctl.d/90-${FILE/default/${LK_PATH_PREFIX}default}
        FILE=$LK_BASE/share/sysctl.d/$FILE
        lk_install -m 00644 "$TARGET"
        lk_file_replace -f "$FILE" "$TARGET"
    done
    ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
        sudo sysctl --system

    if lk_pac_installed tlp; then
        lk_console_message "Checking TLP"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/tlp.d/90-${LK_PATH_PREFIX}default.conf
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/tlp.d/default.conf" "$FILE"
        systemctl_mask systemd-rfkill.service
        systemctl_mask systemd-rfkill.socket
        file_delete "/etc/tlp.d/90-${LK_PATH_PREFIX}defaults.conf"
        SERVICE_ENABLE+=(
            NetworkManager-dispatcher "Network Manager dispatcher"
            tlp "TLP"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(tlp)
    fi

    lk_console_message "Checking console display power management"
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
        lk_console_message "Checking fstrim"
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

    if [ -n "${LK_NTP_SERVER:-}" ]; then
        lk_console_message "Checking NTP"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/ntp.conf
        lk_file_keep_original "$FILE"
        _FILE=$(awk \
            -v "NTP_SERVER=server $LK_NTP_SERVER iburst" \
            -f "$LK_BASE/lib/awk/ntp-set-server.awk" \
            "$FILE")
        lk_file_replace "$FILE" "$_FILE"
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(ntpd)
    fi
    SERVICE_ENABLE+=(
        ntpd "NTP"
    )

    lk_console_message "Checking SSH server"
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

    SERVICE_ENABLE+=(
        qemu-guest-agent "QEMU Guest Agent"
        lightdm "LightDM"
        cups "CUPS"
    )

    service_apply

    if ! lk_is_bootstrap && lk_pac_installed grub; then
        lk_console_message "Checking boot loader"
        unset LK_FILE_REPLACE_NO_CHANGE
        lk_arch_configure_grub
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            sudo update-grub --install
    fi

    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/mkinitcpio.conf
    if [ -f "$FILE" ] && lk_node_service_enabled desktop &&
        lk_system_has_amd_graphics; then
        lk_tty_print "Checking" "$FILE"
        if ! grep -Eq '^MODULES=(.*\<amdgpu\>.*)' "$FILE"; then
            TEMP_FILE=$(lk_mktemp_file)
            lk_delete_on_exit "$TEMP_FILE"
            (
                unset MODULES
                . "$FILE"
                MODULES+=(amdgpu)
                sed -E 's/^(MODULES=\().*(\))/\1'"$(lk_escape_ere_replace \
                    "$(lk_quote MODULES)")"'\2/' "$FILE"
            ) >"$TEMP_FILE"
            lk_file_keep_original "$FILE"
            lk_file_replace -f "$TEMP_FILE" "$FILE"
            ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
                sudo mkinitcpio -P
        fi
    fi

    lk_console_blank
    LK_NO_LOG=1 \
        lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh"

    lk_console_blank
    lk_console_log "Checking packages"
    lk_arch_configure_pacman
    [ -z "$LK_PACKAGES_FILE" ] ||
        . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/arch/packages.sh"

    if lk_command_exists aur ||
        { [ ${#AUR_PACKAGES[@]} -gt 0 ] && lk_confirm \
            "OK to install aurutils for AUR package management?" Y; }; then
        lk_log_tty_on
        lk_console_message "Checking AUR packages"
        PAC_INSTALL=($(lk_pac_not_installed_list \
            ${PAC_BASE_DEVEL[@]+"${PAC_BASE_DEVEL[@]}"} \
            devtools pacutils vifm))
        [ ${#PAC_INSTALL[@]} -eq 0 ] || {
            lk_console_detail "Installing aurutils dependencies"
            lk_tty sudo pacman -S --noconfirm "${PAC_INSTALL[@]}"
        }

        DIR=$({ pacman-conf --repo=aur |
            awk -F"$S*=$S*" '$1=="Server"{print$2}' |
            grep '^file://' |
            sed 's#^file://##'; } 2>/dev/null) && [ -d "$DIR" ] ||
            DIR=/srv/repo/aur
        FILE=$DIR/aur.db.tar.xz
        lk_console_detail "Checking pacman repo at" "$DIR"
        lk_install -d -m 00755 -o "$USER" -g "$GROUP" "$DIR"
        [ -e "$FILE" ] ||
            lk_tty repo-add "$FILE"

        lk_arch_add_repo "aur|file://$DIR|||Optional TrustAll"
        LK_CONF_OPTION_FILE=/etc/pacman.conf
        lk_conf_enable_row -s options "CacheDir = /var/cache/pacman/pkg/"
        lk_conf_enable_row -s options "CacheDir = $DIR/"
        _LK_CONF_DELIM=" = " \
            lk_conf_set_option -s options CleanMethod KeepCurrent

        if ! lk_command_exists aur ||
            ! lk_pac_repo_available_list aur |
            grep -Fx aurutils >/dev/null; then
            lk_console_detail "Installing aurutils"
            PKGDEST=$DIR lk_makepkg -a aurutils --force
            lk_files_exist "${LK_MAKEPKG_LIST[@]}" ||
                lk_die "not found: ${LK_MAKEPKG_LIST[*]}"
            lk_tty repo-add --remove "$FILE" "${LK_MAKEPKG_LIST[@]}"
            lk_pac_sync -f
            lk_tty sudo pacman -S --noconfirm aur/aurutils
        fi

        FILE=/etc/aurutils/pacman-aur.conf
        _FILE=$(cat /usr/share/devtools/pacman-extra.conf &&
            printf '\n[%s]\n' aur &&
            pacman-conf --repo=aur)
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$_FILE"

        # Avoid "unknown public key" errors
        unset LK_SUDO
        DIR=~/.gnupg
        FILE=$DIR/gpg.conf
        lk_install -d -m 00700 "$DIR"
        lk_install -m 00644 "$FILE"
        if ! grep -q "\<auto-key-retrieve\>" "$FILE"; then
            lk_console_detail \
                "Enabling in $(lk_pretty_path $FILE):" "auto-key-retrieve"
            lk_conf_enable_row auto-key-retrieve "$FILE"
        fi
        LK_SUDO=1

        if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
            lk_aur_sync "${AUR_PACKAGES[@]}"
            ! lk_aur_can_chroot || lk_pac_sync -f
            PAC_PACKAGES+=(aurutils "${AUR_PACKAGES[@]}")
            AUR_PACKAGES=()
        fi
        lk_log_tty_stdout_off
    fi

    if [ ${#PAC_KEEP[@]} -gt 0 ]; then
        PAC_KEEP=($(comm -12 \
            <(lk_echo_array PAC_KEEP | sort -u) \
            <(lk_pac_installed_list | sort -u)))
    fi

    lk_console_message "Checking install reasons"
    PAC_EXPLICIT=$(lk_echo_array PAC_PACKAGES AUR_PACKAGES PAC_KEEP | sort -u)
    PAC_MARK_EXPLICIT=($(comm -12 \
        <(lk_echo_array PAC_EXPLICIT) \
        <(lk_pac_installed_not_explicit | sort -u)))
    PAC_UNMARK_EXPLICIT=($(comm -13 \
        <(lk_echo_array PAC_EXPLICIT) \
        <(lk_pac_installed_explicit | sort -u)))
    [ ${#PAC_MARK_EXPLICIT[@]} -eq 0 ] ||
        lk_log_bypass lk_tty sudo \
            pacman -D --asexplicit "${PAC_MARK_EXPLICIT[@]}"
    [ ${#PAC_UNMARK_EXPLICIT[@]} -eq 0 ] ||
        lk_log_bypass lk_tty sudo \
            pacman -D --asdeps "${PAC_UNMARK_EXPLICIT[@]}"

    [ ${#PAC_KEEP[@]} -eq 0 ] ||
        lk_echo_array PAC_KEEP |
        lk_console_list "Not uninstalling:" package packages
    PAC_INSTALL=($(comm -23 \
        <(lk_echo_array PAC_PACKAGES | sort -u) \
        <(lk_pac_installed_list | sort -u)))
    [ ${#PAC_INSTALL[@]} -eq 0 ] ||
        lk_echo_array PAC_INSTALL |
        lk_console_list "Installing:" package packages
    PAC_UPGRADE=($(pacman -Sup --print-format %n))
    [ ${#PAC_UPGRADE[@]} -eq 0 ] ||
        lk_echo_array PAC_UPGRADE |
        lk_console_list "Upgrading:" package packages
    unset NOCONFIRM
    ! lk_no_input || NOCONFIRM=1
    [ ${#PAC_INSTALL[@]}${#PAC_UPGRADE[@]} = 00 ] ||
        lk_log_bypass lk_tty sudo pacman -Su ${NOCONFIRM+--noconfirm} \
            ${PAC_INSTALL[@]+"${PAC_INSTALL[@]}"}

    REMOVE_MESSAGE=()
    ! PAC_REMOVE=($(pacman -Qdttq)) || [ ${#PAC_REMOVE[@]} -eq 0 ] || {
        lk_echo_array PAC_REMOVE |
            lk_console_list "Orphaned:" package packages
        lk_confirm "Remove the above?" N &&
            REMOVE_MESSAGE+=("orphaned") ||
            PAC_REMOVE=()
    }
    PAC_REJECT=($(comm -12 \
        <(lk_echo_array PAC_REJECT | sort -u) \
        <(lk_pac_installed_list | sort -u)))
    [ ${#PAC_REJECT[@]} -eq 0 ] || {
        REMOVE_MESSAGE+=("blacklisted")
        PAC_REMOVE+=("${PAC_REJECT[@]}")
    }
    [ ${#PAC_REMOVE[@]} -eq 0 ] || {
        lk_console_message \
            "Removing $(lk_implode " and " REMOVE_MESSAGE) packages"
        lk_log_bypass lk_tty sudo pacman -Rs --noconfirm "${PAC_REMOVE[@]}"
    }

    lk_symlink_bin codium code || true
    lk_symlink_bin vim vi || true
    lk_symlink_bin xfce4-terminal xterm || true

    lk_console_blank
    lk_console_log "Checking installed packages and services"
    SERVICE_ENABLE+=(
        atd "at"
        cronie "cron"
    )

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

    if lk_pac_installed php || lk_pac_installed php7; then
        for DIR in /etc/php7 /etc/php; do
            unset LK_FILE_REPLACE_NO_CHANGE
            LK_CONF_OPTION_FILE=$DIR/php.ini
            [ -f "$LK_CONF_OPTION_FILE" ] || continue
            PHP_EXT=(
                bcmath
                curl
                exif
                gd
                gettext
                iconv
                imap
                intl
                mysqli
                pdo_sqlite
                soap
                sqlite3
                zip
            )
            for EXT in ${PHP_EXT[@]+"${PHP_EXT[@]}"}; do
                lk_php_enable_option extension "$EXT"
            done
            STANDALONE_PHP_EXT=(
                imagick
                memcache.so
                memcached.so
            )
            for EXT in ${STANDALONE_PHP_EXT[@]+"${STANDALONE_PHP_EXT[@]}"}; do
                FILE=$DIR/conf.d/${EXT%.*}.ini
                [ -f "$FILE" ] || continue
                lk_php_enable_option extension "$EXT" "$FILE"
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
                    lk_install -d -m 00777 ~/.xdebug
                    lk_php_set_option xdebug.output_dir ~/.xdebug
                    # Alternative values: profile, trace
                    lk_php_set_option xdebug.mode debug
                    lk_php_set_option xdebug.start_with_request trigger
                    lk_php_set_option xdebug.profiler_output_name callgrind.out.%H.%R.%u
                    lk_php_set_option xdebug.collect_return On
                    lk_php_set_option xdebug.trace_output_name trace.%H.%R.%u
                    lk_php_enable_option zend_extension xdebug.so
                )
            fi
        done
        # Mitigate PHP 8 bugs in wp-cli search-replace
        FILE=${LK_BIN_PATH:-/usr/local/bin}/wp
        if lk_pac_installed php7 wp-cli; then
            lk_install -m 00755 "$FILE"
            lk_file_replace "$FILE" <<EOF
#!/bin/sh
$(command -pv php7) $(command -pv wp) "\$@"
EOF
        else
            lk_rm "$FILE"
        fi
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
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
    su root root
}
/var/log/php-fpm/*.error.log {
    missingok
    sharedscripts
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
    su http http
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
        lk_httpd_enable_option LoadModule "info_module modules/mod_info.so"
        lk_httpd_enable_option LoadModule "rewrite_module modules/mod_rewrite.so"
        lk_httpd_enable_option LoadModule "status_module modules/mod_status.so"
        lk_httpd_enable_option LoadModule "vhost_alias_module modules/mod_vhost_alias.so"
        if lk_is_desktop; then
            FILE=/etc/httpd/conf/extra/${LK_PATH_PREFIX}default-dev-arch.conf
            lk_install -m 00644 "$FILE"
            lk_file_replace \
                -f "$LK_BASE/share/apache2/default-dev-arch.conf" \
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

        lk_git_provision_repo -s \
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
After=network-online.target
Wants=network-online.target
EOF
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            DAEMON_RELOAD=1
        DIR=/etc/lighttpd/conf.d
        lk_install -d -m 00755 "$DIR"
        LK_CONF_OPTION_FILE=/etc/lighttpd/lighttpd.conf
        lk_conf_remove_row 'var.log_root = "/var/log/lighttpd"'
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
                "s/^($S*mimetype.assign$S*)\+?=($S*\($S*)/\1:=\2/" "$_FILE")
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
        grep -Eq "^$S*cache_dir$S+" "$FILE" ||
            lk_squid_set_option cache_dir "aufs /var/cache/squid 20000 16 256"
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
    fi

    if lk_pac_installed bluez; then
        unset LK_FILE_REPLACE_NO_CHANGE
        lk_conf_set_option AutoEnable true /etc/bluetooth/main.conf
        SERVICE_ENABLE+=(
            bluetooth "Bluetooth"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(bluetooth)
    fi

    if lk_pac_installed libvirt; then
        lk_user_in_group libvirt && lk_user_in_group kvm ||
            sudo usermod --append --groups libvirt,kvm "$USER"
        LIBVIRT_USERS=$(lk_get_users_in_group libvirt)
        LIBVIRT_USERS=$([ -z "$LIBVIRT_USERS" ] || id -u $LIBVIRT_USERS)
        LK_CONF_OPTION_FILE=/etc/conf.d/libvirt-guests
        lk_conf_set_option URIS default
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
        lk_user_in_group docker ||
            sudo usermod --append --groups docker "$USER"
        ! memory_at_least 7 || SERVICE_ENABLE+=(
            docker "Docker"
        )
    fi

    if lk_pac_installed xfce4-session; then
        lk_symlink_bin "$LK_BASE/lib/xfce4/startxfce4"
        SH=$(sudo bash -c 'shopt -s nullglob &&
        a=({/etc/skel*,/home/*}/.config/xfce4/xinitrc) &&
        { [ ${#a[@]} -eq 0 ] || printf " %q" "${a[@]}"; }')
        [ -z "$SH" ] ||
            eval "file_delete$SH"
    fi

    if { [ -n "${LK_SAMBA_WORKGROUP:-}" ] || lk_node_service_enabled samba; } &&
        lk_pac_installed samba; then
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/samba/smb.conf
        _FILE=$(LK_SAMBA_WORKGROUP=${LK_SAMBA_WORKGROUP:-WORKGROUP} \
            lk_expand_template "$LK_BASE/share/samba/smb.template.conf")
        lk_install -m 00644 "$FILE"
        lk_file_replace -i "^(#|;|$S*\$)" "$FILE" "$_FILE"
        SERVICE_ENABLE+=(
            smb "Samba (SMB server)"
            nmb "Samba (NMB server)"
        )
        ! lk_is_false LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(smb nmb)
        sudo pdbedit -L | cut -d: -f1 | grep -Fx "$USER" >/dev/null ||
            lk_console_detail \
                "User '$USER' not found in Samba user database. To fix, run:" \
                $'\n'"sudo smbpasswd -a $USER"
    fi

    service_apply || EXIT_STATUS=$?

    (exit "$EXIT_STATUS") &&
        lk_console_success "Provisioning complete" ||
        lk_console_error -r "Provisioning completed with errors" || lk_die ""

    exit
}

#!/bin/bash

lk_require provision

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

function lk_atop_ps_mem() {
    lk_elevate atop -R -PCPL,MEM,SWP,PAG,PRM "$@" |
        awk -f "$LK_BASE/lib/awk/atop-ps-mem.awk"
}

function _lk_lsblk() {
    if [ "${1-}" = -q ]; then
        local SH
        shift
        SH=$(lsblk --pairs --output "$@" |
            sed -E \
                -e "s/[^[:blank:]]+=\"([^\"]*)\"/\$'\1'/g" \
                -e "s/^/lk_quote_args /") && eval "$SH"
    else
        lsblk --list --noheadings --output "$@"
    fi
}

# lk_block_device_is TYPE DEVICE_PATH...
function lk_block_device_is() {
    local COUNT
    lk_paths_exist "${@:2}" || lk_warn "not found: ${*:2}" || return
    COUNT=$(_lk_lsblk TYPE --nodeps "${@:2}" | grep -Fxc "$1") &&
        [ "$COUNT" -eq $(($# - 1)) ]
}

# lk_block_device_is_ssd DEVICE_PATH...
function lk_block_device_is_ssd() {
    local COUNT
    lk_paths_exist "$@" || lk_warn "not found: $*" || return
    COUNT=$(_lk_lsblk DISC-GRAN,DISC-MAX --nodeps "$@" |
        grep -Evc "^$S*0B$S+0B$S*\$") &&
        [ "$COUNT" -eq $# ]
}

function lk_system_timezone() {
    local ZONE
    if [ -L /etc/localtime ] &&
        ZONE=$(readlink /etc/localtime 2>/dev/null) &&
        [[ $ZONE =~ /zoneinfo/(.*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # Work around limited support for `timedatectl show`
        timedatectl status |
            sed -En 's/^[^:]*zone: ([^ ]+).*/\1/Ip'
    fi
}

function lk_system_list_physical_links() {
    local WIFI ETH UP WIFI_ARGS UP_ARGS
    unset WIFI ETH UP
    WIFI_ARGS=(-execdir test -d "{}/wireless" -o -L "{}/phy80211" \;)
    UP_ARGS=(-execdir grep -Fxq 1 "{}/carrier" \;)
    [ "${1-}" != -w ] || { WIFI= && shift; }
    [ "${1-}" != -e ] || { WIFI= && ETH= && shift; }
    [ "${1-}" != -u ] || { UP= && shift; }
    find /sys/class/net \
        -type l \
        ! -lname '*virtual*' \
        ${ETH+!} \
        ${WIFI+"${WIFI_ARGS[@]}"} \
        ${UP+"${UP_ARGS[@]}"} \
        -printf '%f\n'
}

function lk_system_list_ethernet_links() {
    lk_system_list_physical_links -e "$@"
}

function lk_system_list_wifi_links() {
    lk_system_list_physical_links -w "$@"
}

function lk_system_sort_links() {
    local IF
    for IF in "$@"; do
        (
            unset UDEV_ID_NET_NAME_ONBOARD
            IF_PATH=/sys/class/net/$IF
            ! SH=$(udevadm info -q property -x -P UDEV_ "$IF_PATH") ||
                eval "$SH"
            SORT=${UDEV_ID_NET_NAME_ONBOARD:+1}
            printf '%s\t%s\t%s\n' \
                "$IF" \
                "${SORT:-2}" \
                "${UDEV_ID_NET_NAME_ONBOARD-}"
        )
    done | sort -V -k2 -k3 -k1 | cut -f1
}

function lk_system_list_graphics() {
    local EXIT_STATUS
    _LK_SYSTEM_GRAPHICS=${_LK_SYSTEM_GRAPHICS-$(lspci | grep -E "VGA|3D")} || {
        EXIT_STATUS=$?
        unset _LK_SYSTEM_GRAPHICS
        return "$EXIT_STATUS"
    }
    echo "$_LK_SYSTEM_GRAPHICS"
}

function lk_system_has_intel_graphics() {
    lk_system_list_graphics | grep -i Intel >/dev/null
}

function lk_system_has_nvidia_graphics() {
    lk_system_list_graphics | grep -i NVIDIA >/dev/null
}

function lk_system_has_amd_graphics() {
    lk_system_list_graphics | grep -i AMD >/dev/null
}

function lk_nm_is_running() {
    { nmcli -g running general status |
        grep -Fx running; } &>/dev/null
}

# lk_nm_active_connection_uuid DEVICE
function lk_nm_active_connection_uuid() {
    [ $# -gt 0 ] || lk_warn "no device" || return
    lk_nm_is_running &&
        nmcli -g device,uuid connection show --active |
        lk_require_output awk -F: -v "i=$1" '$1==i{print$2}'
}

# lk_nm_connection_uuid CONNECTION
function lk_nm_connection_uuid() {
    [ $# -gt 0 ] || lk_warn "no connection" || return
    lk_nm_is_running &&
        nmcli -g name,uuid connection show |
        lk_require_output awk -F: -v "i=$1" '$1==i{print$2}'
}

# lk_nm_device_connection_uuid DEVICE
function lk_nm_device_connection_uuid() {
    [ $# -gt 0 ] || lk_warn "no device" || return
    lk_nm_is_running &&
        nmcli -g uuid connection show |
        gnu_xargs -r nmcli -g connection.interface-name,connection.uuid \
            connection show |
            lk_require_output awk -v "i=$1" '$0==i{f=1;next}f{print;f=0}'
}

# lk_nm_file_get_ipv4_ipv6 IPV4_ADDRESS IPV4_GATEWAY DNS_SERVERS DNS_SEARCH
#
# Output NetworkManager [ipv4] and [ipv6] keyfile sections for the given
# configuration. All arguments are optional.
function lk_nm_file_get_ipv4_ipv6() {
    local ADDRESS=${1-} GATEWAY=${2-} DNS4 DNS6 DNS_SEARCH MANUAL IFS=$'; \t\n'
    unset MANUAL
    DNS4=($(printf '%s\n' ${3-} | lk_filter_ipv4))
    DNS6=($(printf '%s\n' ${3-} | lk_filter_ipv6))
    DNS_SEARCH=(${4-})
    [ -z "$ADDRESS" ] || MANUAL=
    cat <<EOF

[ipv4]${ADDRESS:+
address1=$ADDRESS${GATEWAY:+,$GATEWAY}}${DNS4[*]+
dns=${DNS4[*]};${DNS_SEARCH[*]+
dns-search=${DNS_SEARCH[*]};}
ignore-auto-dns=true}
method=${MANUAL-auto}${MANUAL+manual

[ipv6]
addr-gen-mode=stable-privacy${DNS6[*]+
dns=${DNS6[*]};${DNS_SEARCH[*]+
dns-search=${DNS_SEARCH[*]};}
ignore-auto-dns=true}
ip6-privacy=0
method=auto}
EOF
}

# lk_nm_file_get_ethernet DEV MAC [BRIDGE_DEV [IP_ARG...]]
function lk_nm_file_get_ethernet() {
    local NAME=$1 MAC=$2 MASTER=${3-} UUID
    # Maintain UUID if possible
    UUID=$(lk_nm_connection_uuid "$NAME" 2>/dev/null) ||
        UUID=${UUID:-$(uuidgen)} || return
    cat <<EOF
[connection]
id=$NAME
uuid=$UUID
type=ethernet
interface-name=$NAME${MASTER:+
master=$MASTER
slave-type=bridge}

[ethernet]
mac-address=$(lk_upper "$MAC")
EOF
    [ $# -lt 4 ] ||
        lk_nm_file_get_ipv4_ipv6 "${@:4}"
}

# lk_nm_file_get_bridge DEV MAC [IP_ARG...]
function lk_nm_file_get_bridge() {
    local NAME=$1 MAC=$2 UUID
    UUID=$(lk_nm_connection_uuid "$NAME" 2>/dev/null) ||
        UUID=${UUID:-$(uuidgen)} || return
    cat <<EOF
[connection]
id=$NAME
uuid=$UUID
type=bridge
interface-name=$NAME

[bridge]
mac-address=$(lk_upper "$MAC")
stp=false
EOF
    [ $# -lt 3 ] ||
        lk_nm_file_get_ipv4_ipv6 "${@:3}"
}

# lk_user_passwd_status USER
#
# Print L (locked password), NP (has no password) or P (has a usable password)
# for the given user.
function lk_user_passwd_status() {
    [ -n "${1-}" ] || lk_warn "no user" || return
    lk_user_exists "$1" || lk_warn "user not found: $1" || return
    lk_elevate passwd -S "$1" | awk '{print $2}'
}

# lk_user_lock_passwd USER
function lk_user_lock_passwd() {
    local STATUS
    STATUS=$(lk_user_passwd_status "$@") || return
    [ "$STATUS" = L ] || {
        lk_tty_detail "Locking user password:" "$1"
        lk_elevate passwd -l "$1"
    }
}

# lk_get_users_in_group GROUP...
function lk_get_users_in_group() {
    getent group "$@" 2>/dev/null |
        cut -d: -f4 |
        tr ',' '\n' |
        sort -u || true
}

# lk_get_standard_users [HOME_BASE_DIR]
function lk_get_standard_users() {
    local ADM_USERS USERS
    ADM_USERS=($(lk_get_users_in_group adm sudo wheel))
    USERS=($(getent passwd | awk -F: -v "h=${1-}" \
        '$3 >= 1000 && $3 < 65534 && index($6, h) == 1 { print $1 }'))
    # lk_linode_hosting_ssh_add_all relies on this being a standalone function,
    # so don't use lk_echo_array
    comm -13 \
        <(printf '%s\n' "${ADM_USERS[@]}" | sort) \
        <(printf '%s\n' "${USERS[@]}" | sort)
}

function lk_icon_install() {
    local TARGET_DIR=${2:-~/.local/share/icons/hicolor} SIZE SIZES=(
        16x16 22x22 24x24 32x32 36x36 48x48 64x64 72x72 96x96
        128x128 160x160 192x192 256x256 384x384 512x512
        1024x1024
    )
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    for SIZE in "${SIZES[@]}"; do
        lk_maybe_sudo install -d "$TARGET_DIR/$SIZE/apps" &&
            lk_maybe_sudo convert "$1" -resize "$SIZE" \
                "$TARGET_DIR/$SIZE/apps/${1##*/}" || return
    done
    ! lk_command_exists gtk-update-icon-cache ||
        lk_maybe_sudo gtk-update-icon-cache --force --quiet \
            --ignore-theme-index "$TARGET_DIR" || true
}

function lk_in_chroot() {
    # As per systemd's running_in_chroot check, return true if "/proc/1/root"
    # and "/" resolve to different inodes
    return "${_LK_IN_CHROOT:=$(INODES=$(lk_elevate \
        stat -Lc "%d %i" /proc/1/root / |
        awk '{print $1}' |
        sort -u |
        wc -l) && [ "$INODES" -gt 1 ] &&
        echo 0 || echo 1)}"
}

function lk_fs_ext4_check() {
    local IFS=$'\n' SOURCES SOURCE
    SOURCES=($(findmnt --types ext4,ext3,ext2 --noheadings --output SOURCE)) &&
        [ ${#SOURCES[@]} -gt 0 ] ||
        lk_warn "no ext4, ext3, or ext2 filesystems found" || return
    [ $# -gt 0 ] || set -- \
        "Filesystem volume name" \
        "Last mounted on" \
        "Default mount options" \
        "Filesystem state" \
        "Filesystem created" \
        "Last mount time" \
        "Last write time" \
        "Mount count" \
        "Maximum mount count" \
        "Last checked" \
        "Check interval" \
        "Lifetime writes"
    for SOURCE in "${SOURCES[@]}"; do
        lk_tty_print "Checking:" "$SOURCE"
        lk_elevate tune2fs -l "$SOURCE" |
            sed -En "s/^($(lk_regex_implode "$@")):$S*/\1\t/p" |
            IFS=$'\t' lk_tty_detail_pairs || return
        lk_tty_print
    done
}

function lk_is_portable() {
    # - 8  = Portable
    # - 9  = Laptop
    # - 10 = Notebook
    # - 11 = Hand Held
    # - 12 = Docking Station
    # - 14 = Sub Notebook
    # - 30 = Tablet
    # - 31 = Convertible
    # - 32 = Detachable
    grep -Eq '^(8|9|10|11|12|14|30|31|32)$' /sys/class/dmi/id/chassis_type
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

function lk_fc_charset() {
    local MATCH FAMILY SH
    [ -n "${1-}" ] || lk_warn "no pattern" || return
    MATCH=$(fc-match "$1" family charset) && [ -n "$MATCH" ] &&
        FAMILY=$(cut -d: -f1 <<<"$MATCH") ||
        lk_warn "match not found" || return
    lk_tty_detail "Loading glyphs from" "$FAMILY"
    SH=$(cut -d: -f2 <<<"$MATCH" |
        cut -d= -f2 |
        sed 's/ /\n/g' |
        sed -En \
            -e "s/^([0-9a-f]+)-([0-9a-f]+)\$/printf '{%d..%d} ' 0x\1 0x\2/p" \
            -e "s/^[0-9a-f]+\$/printf '%d ' 0x&/p") &&
        SH="printf '%s\n' $(eval "$SH")" &&
        eval "$SH"
}

function lk_fc_glyphs() {
    local CHARSET GLYPHS
    CHARSET=($(lk_fc_charset "$1")) &&
        eval "GLYPHS=\$'$(for GLYPH in "${CHARSET[@]}"; do
            printf '%08x \\U%08x\\n' "$GLYPH" "$GLYPH"
        done)'" ||
        return
    lk_tty_detail "Glyphs found:" "${#CHARSET[@]}"
    echo "$GLYPHS"
}

function lk_xfce4_xfconf_dump() {
    local CHANNELS
    CHANNELS=($(xfconf-query -l | tail -n+2 | sort -f))
    for CHANNEL in "${CHANNELS[@]}"; do
        while read -r PROPERTY VALUE; do
            printf '%s,%s,%s\n' "$CHANNEL" "$PROPERTY" "$VALUE"
        done < <(xfconf-query -c "$CHANNEL" -lv | sort -f)
    done
}

# lk_xfce4_panel_list_plugins
#
# Print tab-delimited fields PLUGIN_ID and PLUGIN_NAME for each configured Xfce4
# panel plugin
function lk_xfce4_panel_list_plugins() {
    xfconf-query -c xfce4-panel -p /plugins -lv |
        sed -En 's#^/plugins/plugin-([0-9]+)[[:blank:]]+(.*)#\1\t\2#p'
}

# lk_file_acl_list_with_extended [STARTING_POINT...]
#
# Use `getfacl` to search each STARTING_POINT and print the name of each file
# and directory with an extended ACL. If no STARTING_POINT is specified, search
# the current directory.
function lk_file_acl_list_with_extended() {
    [ $# -gt 0 ] || set -- "$PWD" || return
    getfacl -Rsp "$@" | sed -En 's/^# file: //p'
}

# lk_file_acl_remove_extended [STARTING_POINT...]
#
# Search each STARTING_POINT and remove extended ACLs from all files and
# directories. If no STARTING_POINT is specified, search the current directory.
function lk_file_acl_remove_extended() {
    lk_confirm "OK to remove extended ACL entries recursively?" Y || return
    lk_file_acl_list_with_extended "$@" |
        # Interpret special character escapes added by `getfacl`
        gnu_xargs -d '\n' printf '%b\0' |
        # Print filenames to stderr
        tee >(tr '\n\0' ' \n' >&2) |
        gnu_xargs -0r setfacl -b --
}

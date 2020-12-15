#!/bin/bash
# shellcheck disable=SC1090,SC2001,SC2015,SC2016,SC2034,SC2124,SC2206,SC2207

# To install Arch Linux using the script below:
# 1. boot from an Arch Linux live CD
# 2. wpa_supplicant -B -i wlan0 -c <(wpa_passphrase SSID passphrase)
# 3. curl -L https://lkr.ms/bs >bs
# 4. bash bs

BOOTSTRAP_PING_HOST=${BOOTSTRAP_PING_HOST:-one.one.one.one}  # https://blog.cloudflare.com/dns-resolver-1-1-1-1/
BOOTSTRAP_MOUNT_OPTIONS=${BOOTSTRAP_MOUNT_OPTIONS:-defaults} # On VMs with TRIM support, "discard" is added automatically
LK_NODE_TIMEZONE=${LK_NODE_TIMEZONE:-UTC}                    # See `timedatectl list-timezones`
LK_NODE_LOCALES=${LK_NODE_LOCALES-en_AU.UTF-8 en_GB.UTF-8}   # "en_US.UTF-8" is added automatically
LK_NODE_LANGUAGE=${LK_NODE_LANGUAGE-en_AU:en_GB:en}          #
LK_NTP_SERVER=${LK_NTP_SERVER-time.apple.com}                #
LK_ARCH_CUSTOM_REPOS=${LK_ARCH_CUSTOM_REPOS:-}               # REPO|SERVER|KEY_URL|KEY_ID|SIG_LEVEL,...
LK_ARCH_MIRROR=${LK_ARCH_MIRROR:-}
LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-}
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-master}
export LK_BASE=${LK_BASE:-/opt/lk-platform}

set -euo pipefail
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
[ "${_FILE%/*}" != "$_FILE" ] || _FILE=./$_FILE
[ ! -L "$_FILE" ] &&
    _DIR="$(cd "${_FILE%/*}" && pwd -P)" ||
    lk_die "unable to resolve path to script"

shopt -s nullglob

function usage() {
    echo "\
Usage:
  ${0##*/} <root_partition> <boot_partition> [<other_os_partition>...] <hostname> <username>
  ${0##*/} <install_disk> <hostname> <username>

Current block devices:

$(lsblk --output "NAME,RM,RO,SIZE,TYPE,FSTYPE,MOUNTPOINT" --paths)" >&2
    exit 1
}

function exit_trap() {
    exec >&6 2>&7 6>&- 7>&-
    [ ! -d "/mnt/boot" ] || {
        install -d -m 00755 "/mnt/var/log" &&
            install -m 00640 -g "adm" \
                "$LOG_FILE" "/mnt/var/log/${LK_PATH_PREFIX}bootstrap.log" || true
    }
}

function _lsblk() {
    lsblk --list --noheadings --output "$@"
}

function check_devices() {
    local COLUMN="${COLUMN:-TYPE}" MATCH="$1" DEV LIST
    shift
    for DEV in "$@"; do
        [ -e "$DEV" ] || return
    done
    LIST="$(_lsblk "$COLUMN" --nodeps "$@")" &&
        echo "$LIST" | grep -Fx "$MATCH" >/dev/null &&
        ! echo "$LIST" | grep -Fxv "$MATCH" >/dev/null
}

function is_ssd() {
    local COLUMNS
    COLUMNS="$(_lsblk "DISC-GRAN,DISC-MAX" --nodeps "$1")" || return
    [[ ! "$COLUMNS" =~ ^$S*0B$S+0B$S*$ ]]
}

function before_install() {
    lk_console_detail "Checking network connection"
    ping -c 1 "$BOOTSTRAP_PING_HOST" || lk_die "no network"

    if [ -n "$LK_NTP_SERVER" ]; then
        if ! type -P ntpd >/dev/null; then
            lk_console_detail "Installing ntpd in live environment"
            pacman -Sy --noconfirm ntp >/dev/null || lk_die "unable to install ntpd"
        fi
        lk_console_detail "Synchronising system time with" "$LK_NTP_SERVER"
        ntpd -qgx "$LK_NTP_SERVER" || lk_die "unable to sync system time"
    fi
}

function in_target() {
    arch-chroot /mnt "$@"
}

function configure_pacman() {
    lk_console_detail "Configuring pacman"
    lk_pacman_configure
    [ ${#CUSTOM_REPOS[@]} -eq 0 ] ||
        lk_pacman_add_repo "${CUSTOM_REPOS[@]}"
}

[ -d "/sys/firmware/efi/efivars" ] || lk_die "not booted in UEFI mode"
[ "$EUID" -eq 0 ] || lk_die "not running as root"
[[ $- != *s* ]] || lk_die "cannot run from standard input"
[ $# -ge 3 ] || usage

LOG_FILE=/tmp/${LK_PATH_PREFIX}bootstrap.$(date +'%s').log
exec 6>&1 7>&2
exec > >(tee "$LOG_FILE") 2>&1
trap exit_trap EXIT

for FILE_PATH in \
    /lib/bash/include/core.sh \
    /lib/bash/include/arch.sh \
    /lib/arch/include/packages.sh; do
    FILE="$_DIR/${FILE_PATH##*/}"
    URL="https://raw.githubusercontent.com/lkrms/lk-platform/$LK_PLATFORM_BRANCH$FILE_PATH"
    [ -e "$FILE" ] ||
        curl --fail --output "$FILE" "$URL" || {
        rm -f "$FILE"
        lk_die "unable to download from GitHub: $URL"
    }
done

. "$_DIR/core.sh"
. "$_DIR/arch.sh"

lk_console_message "Setting up live environment"
# otherwise mirrorlist may be replaced by reflector
systemctl stop reflector || true
configure_pacman
[ -z "$LK_ARCH_MIRROR" ] ||
    # pacstrap will copy this to the new system
    echo "Server=$LK_ARCH_MIRROR" >"/etc/pacman.d/mirrorlist"

. "$_DIR/packages.sh" >&6 2>&7

# in case we're starting over after a failed attempt
if [ -d "/mnt/boot" ]; then
    OTHER_OS_MOUNTS=(/mnt/mnt/*)
    [ ${#OTHER_OS_MOUNTS[@]} -eq 0 ] || {
        umount "${OTHER_OS_MOUNTS[@]}" &&
            rmdir "${OTHER_OS_MOUNTS[@]}" || exit
    }
    umount /mnt/boot &&
        umount /mnt || exit
fi

OTHER_OS_PARTITIONS=()

if [ $# -eq 3 ]; then

    check_devices disk "$1" || lk_die "not a disk: $1"

    before_install

    lk_confirm "Repartition $1? ALL DATA WILL BE LOST."

    lk_console_message "Partitioning $1"
    parted --script "$1" \
        mklabel gpt \
        mkpart fat32 2048s 260MiB \
        mkpart ext4 260MiB 100% \
        set 1 boot on || lk_die "parted failed (exit status $?)"
    partprobe "$1"
    sleep 1
    PARTITIONS=($(_lsblk "TYPE,NAME" --paths "$1" | grep -Po '(?<=^part ).*'))
    [ ${#PARTITIONS[@]} -eq 2 ] &&
        ROOT_PARTITION="${PARTITIONS[1]}" &&
        BOOT_PARTITION="${PARTITIONS[0]}" || exit
    wipefs -a "$ROOT_PARTITION"
    wipefs -a "$BOOT_PARTITION"

    REPARTITIONED=1
    LK_NODE_HOSTNAME="$2"
    TARGET_USERNAME="$3"

elif [ $# -ge 4 ]; then

    check_devices part "${@:1:$#-2}" || lk_die "not partitions: ${*:1:$#-2}"

    before_install

    REPARTITIONED=0
    ROOT_PARTITION="$1"
    BOOT_PARTITION="$2"
    OTHER_OS_PARTITIONS=("${@:3:$#-4}")
    LK_NODE_HOSTNAME="${@: -2:1}"
    TARGET_USERNAME="${@: -1:1}"

fi

TARGET_PASSWORD="${TARGET_PASSWORD:-}"
if [ -z "$TARGET_PASSWORD" ]; then
    while :; do
        TARGET_PASSWORD="$(lk_console_read_secret "Password for $TARGET_USERNAME:")"
        [ -n "$TARGET_PASSWORD" ] || lk_warn "Password cannot be empty" || continue
        CONFIRM_PASSWORD="$(lk_console_read_secret "Password for $TARGET_USERNAME (again):")"
        [ "$TARGET_PASSWORD" = "$CONFIRM_PASSWORD" ] || lk_warn "Passwords do not match" || continue
        break
    done
fi

TARGET_SSH_KEY="${TARGET_SSH_KEY:-}"
if [ -z "$TARGET_SSH_KEY" ]; then
    TARGET_SSH_KEY="$(lk_console_read "Authorised SSH key for $TARGET_USERNAME:")"
    [ -n "$TARGET_SSH_KEY" ] || lk_console_warning "SSH will not be configured (no key provided)"
fi

GRUB_CMDLINE="${GRUB_CMDLINE:-}"
if [ -z "$GRUB_CMDLINE" ]; then
    lk_console_item \
        "Kernel command-line argument examples:" \
        "$(lk_echo_args \
            "usbcore.autosuspend=5" \
            "mce=dont_log_ce" \
            "libata.force=3.00:noncq")"
    GRUB_CMDLINE="$(lk_console_read "Custom kernel command-line arguments:")"
fi

export -n TARGET_PASSWORD TARGET_SSH_KEY

ROOT_PARTITION_TYPE="$(_lsblk FSTYPE "$ROOT_PARTITION")" || lk_die "no block device at $ROOT_PARTITION"
BOOT_PARTITION_TYPE="$(_lsblk FSTYPE "$BOOT_PARTITION")" || lk_die "no block device at $BOOT_PARTITION"

KEEP_BOOT_PARTITION=0
case "$BOOT_PARTITION_TYPE" in
vfat)
    ! lk_confirm "$BOOT_PARTITION already has a vfat filesystem. Leave it as-is?" || KEEP_BOOT_PARTITION=1
    ;;&

vfat | "")
    if lk_is_false KEEP_BOOT_PARTITION; then
        lk_is_true REPARTITIONED ||
            lk_confirm "OK to format $BOOT_PARTITION as FAT32?"

        lk_console_message "Formatting $BOOT_PARTITION"
        mkfs.fat -vn ESP -F 32 "$BOOT_PARTITION"
    fi
    ;;

*)
    lk_die "unexpected filesystem at $BOOT_PARTITION: $BOOT_PARTITION_TYPE"
    ;;

esac

[ -z "$ROOT_PARTITION_TYPE" ] ||
    lk_console_warning "Unexpected filesystem at $ROOT_PARTITION: $ROOT_PARTITION_TYPE"

lk_is_true REPARTITIONED ||
    lk_confirm "OK to format $ROOT_PARTITION as ext4?" || exit

lk_console_message "Formatting $ROOT_PARTITION"
mkfs.ext4 -vL root "$ROOT_PARTITION"

lk_console_message "Mounting partitions"
if lk_is_virtual; then
    ! is_ssd "$ROOT_PARTITION" || ROOT_OPTION_EXTRA=",discard"
    ! is_ssd "$BOOT_PARTITION" || BOOT_OPTION_EXTRA=",discard"
fi
mount -o "$BOOTSTRAP_MOUNT_OPTIONS${ROOT_OPTION_EXTRA:-}" "$ROOT_PARTITION" /mnt &&
    mkdir /mnt/boot &&
    mount -o "$BOOTSTRAP_MOUNT_OPTIONS${BOOT_OPTION_EXTRA:-}" "$BOOT_PARTITION" /mnt/boot || exit

lk_is_false KEEP_BOOT_PARTITION || {
    lk_console_message "Checking for files from previous installations in boot filesystem"
    rm -Rfv /mnt/boot/syslinux /mnt/boot/intel-ucode.img
}

lk_console_message "Installing system"
pacstrap /mnt "${PACMAN_PACKAGES[@]}" >&6 2>&7

lk_console_message "Setting up installed system"

LK_ARCH_CHROOT_DIR=/mnt

lk_console_detail "Generating fstab"
lk_file_keep_original "/mnt/etc/fstab"
genfstab -U /mnt >>"/mnt/etc/fstab"

configure_pacman

if [ -n "$LK_NTP_SERVER" ]; then
    lk_console_detail "Configuring NTP"
    FILE="/mnt/etc/ntp.conf"
    lk_file_keep_original "$FILE"
    sed -Ei 's/^(server|pool)\b/#&/' "$FILE"
    echo "server $LK_NTP_SERVER iburst" >>"$FILE"
fi

lk_console_detail "Setting the time zone"
ln -sfv "/usr/share/zoneinfo/$LK_NODE_TIMEZONE" "/mnt/etc/localtime"

lk_console_detail "Configuring hardware clock"
in_target hwclock --systohc

LOCALES=($LK_NODE_LOCALES en_US.UTF-8)
lk_console_detail "Configuring locales"
lk_file_keep_original "/mnt/etc/locale.gen"
for _LOCALE in $(printf '%s\n' "${LOCALES[@]}" | sort -u); do
    sed -Ei "s/^$S*#$S*($(lk_escape_ere "$_LOCALE")$S+)/\\1/" "/mnt/etc/locale.gen"
done
in_target locale-gen

lk_file_keep_original "/mnt/etc/locale.conf"
cat <<EOF >"/mnt/etc/locale.conf"
LANG=${LOCALES[0]}${LK_NODE_LANGUAGE:+
LANGUAGE=$LK_NODE_LANGUAGE}
EOF

lk_console_detail "Setting hostname"
lk_file_keep_original "/mnt/etc/hostname"
echo "$LK_NODE_HOSTNAME" >"/mnt/etc/hostname"

lk_console_detail "Configuring hosts"
lk_file_keep_original "/mnt/etc/hosts"
cat <<EOF >>"/mnt/etc/hosts"
127.0.0.1 localhost
::1 localhost
127.0.1.1 $LK_NODE_HOSTNAME.localdomain $LK_NODE_HOSTNAME
EOF

if [ ${#PACMAN_DESKTOP_PACKAGES[@]} -eq 0 ]; then
    in_target systemctl set-default multi-user.target
else
    in_target systemctl set-default graphical.target

    lk_console_detail "Enabling LightDM"
    in_target systemctl enable lightdm.service

    install -v -d -m 00755 "/mnt/etc/skel/.config/xfce4"
    ln -sv "$LK_BASE/etc/xfce4/xinitrc" \
        "/mnt/etc/skel/.config/xfce4/xinitrc"
    in_target bash -c \
        '! XTERM_PATH="$(type -P xfce4-terminal)" || ln -sv "$XTERM_PATH" "/usr/local/bin/xterm"'
fi

lk_console_detail "Setting default umask"
cat <<"EOF" >"/mnt/etc/profile.d/Z90-${LK_PATH_PREFIX}umask.sh"
#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
    umask 002
else
    umask 022
fi
EOF

lk_console_detail "Sourcing $LK_BASE/lib/bash/rc.sh in ~/.bashrc for all users"
cat <<EOF >>"/mnt/etc/skel/.bashrc"

# Added by bootstrap.sh at $(lk_date_log)
if [ -f '$LK_BASE/lib/bash/rc.sh' ]; then
    . '$LK_BASE/lib/bash/rc.sh'
fi
EOF
install -v -m 00600 "/mnt/etc/skel/.bashrc" "/mnt/root/.bashrc"

lk_console_detail "Configuring SSH defaults for all users"
install -v -d -m 00700 "/mnt/etc/skel/.ssh"
install -v -m 00600 /dev/null "/mnt/etc/skel/.ssh/authorized_keys"
install -v -m 00600 /dev/null "/mnt/etc/skel/.ssh/config"
cat <<EOF >"/mnt/etc/skel/.ssh/config"
Host                    *
IdentitiesOnly          yes
ForwardAgent            yes
StrictHostKeyChecking   accept-new
ControlMaster           auto
ControlPath             /tmp/ssh_%h-%p-%r-%l
ControlPersist          120
SendEnv                 LANG LC_*
ServerAliveInterval     30
EOF

lk_console_detail "Creating superuser:" "$TARGET_USERNAME"
in_target useradd -m "$TARGET_USERNAME" -G adm,wheel -s /bin/bash
echo -e "$TARGET_PASSWORD\n$TARGET_PASSWORD" | in_target passwd "$TARGET_USERNAME"
[ -z "$TARGET_SSH_KEY" ] || {
    echo "$TARGET_SSH_KEY" | in_target sudo -H -u "$TARGET_USERNAME" \
        bash -c 'cat >"$HOME/.ssh/authorized_keys"'
    sed -Ei -e "s/^#?(PasswordAuthentication|PermitRootLogin)\b.*\$/\1 no/" \
        "/mnt/etc/ssh/sshd_config"
    in_target systemctl enable sshd.service
}

lk_console_detail "Configuring sudo"
FILE=/mnt/etc/sudoers.d/${LK_PATH_PREFIX}default-arch
install -v -m 00440 /dev/null "$FILE"
cat <<EOF >"$FILE"
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD:/usr/bin/pacman
EOF

lk_console_detail "Disabling root password"
in_target passwd -l root

lk_console_detail "Installing lk-platform to:" "$LK_BASE"
in_target install -v -d -m 02775 -o "$TARGET_USERNAME" -g "adm" \
    "$LK_BASE"
in_target sudo -H -u "$TARGET_USERNAME" \
    git clone -b "$LK_PLATFORM_BRANCH" \
    "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
lk_get_shell_var \
    LK_BASE \
    LK_PATH_PREFIX \
    LK_NODE_HOSTNAME \
    LK_NODE_TIMEZONE \
    LK_NODE_LOCALES \
    LK_NODE_LANGUAGE \
    LK_NTP_SERVER \
    LK_ARCH_CUSTOM_REPOS \
    LK_ARCH_MIRROR \
    LK_PLATFORM_BRANCH >"/mnt/etc/default/lk-platform"
in_target "$LK_BASE/bin/lk-platform-configure-system.sh" --no-log

if lk_is_qemu; then
    lk_console_detail "Enabling QEMU guest agent"
    in_target systemctl enable qemu-ga.service
fi

lk_console_detail "Enabling NetworkManager"
in_target systemctl enable NetworkManager.service

if ! lk_is_virtual; then
    lk_console_detail "Configuring TLP"
    in_target systemctl enable tlp.service
    in_target systemctl enable NetworkManager-dispatcher.service
    in_target systemctl mask systemd-rfkill.service
    in_target systemctl mask systemd-rfkill.socket
    cat <<EOF >"/mnt/etc/tlp.d/90-${LK_PATH_PREFIX}defaults.conf"
# Increase performance (and energy consumption, of course)
CPU_ENERGY_PERF_POLICY_ON_AC=performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_performance

# Exclude RTL8153 (r8152) from autosuspend (common USB / USB-C NIC)
USB_BLACKLIST="0bda:8153"

# Allow phones to charge
USB_BLACKLIST_PHONE=1
EOF

    if { is_ssd "$ROOT_PARTITION" || is_ssd "$BOOT_PARTITION"; }; then
        lk_console_detail "Enabling fstrim (TRIM support detected)"
        # replace the default timer
        cat <<EOF >"/mnt/etc/systemd/system/fstrim.timer"
[Unit]
Description=Discard unused blocks 30 seconds after booting, then weekly

[Timer]
OnBootSec=30
OnActiveSec=1w
AccuracySec=1h

[Install]
WantedBy=timers.target
EOF
        in_target systemctl enable fstrim.timer
    fi
fi

if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
    lk_console_message "Installing AUR packages"
    AUR_SCRIPT="{ $YAY_SCRIPT; } &&
    yay -Sy --aur --needed --noconfirm ${AUR_PACKAGES[*]}"
    in_target sudo -H -u "$TARGET_USERNAME" \
        bash -c "$AUR_SCRIPT" >&6 2>&7
fi

in_target bash -c \
    '! VI_PATH="$(type -P vim)" || ln -sv "$VI_PATH" "/usr/local/bin/vi"'

i=0
for PARTITION in ${OTHER_OS_PARTITIONS[@]+"${OTHER_OS_PARTITIONS[@]}"}; do
    MOUNT_DIR="/mnt/mnt/temp$i"
    mkdir -p "$MOUNT_DIR" &&
        mount "$PARTITION" "$MOUNT_DIR" || lk_console_warning "unable to mount partition $PARTITION"
    ((++i))
done

! lk_is_true KEEP_BOOT_PARTITION || {
    lk_console_warning "\
If installing to a boot partition created by Windows, filesystem damage
may cause efibootmgr to fail with 'Input/output error'"
    ! lk_confirm "Run 'dosfsck -a $BOOT_PARTITION' before installing boot loader?" Y || {
        lk_console_message "Running filesystem check on partition:" "$BOOT_PARTITION"
        umount "$BOOT_PARTITION" &&
            {
                EXIT_STATUS=0
                dosfsck -a "$BOOT_PARTITION" || EXIT_STATUS="$?"
                lk_console_detail "dosfsck exit status:" "$EXIT_STATUS"
            } &&
            mount -o "$BOOTSTRAP_MOUNT_OPTIONS${BOOT_OPTION_EXTRA:-}" "$BOOT_PARTITION" /mnt/boot || exit
    }
}
lk_console_message "Installing boot loader"
lk_file_keep_original "/mnt/etc/default/grub"
! lk_is_virtual || CMDLINE_EXTRA="console=tty0 console=ttyS0"
sed -Ei -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
    -e 's/^#?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
    -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet loglevel=3 audit=0${CMDLINE_EXTRA:+ $CMDLINE_EXTRA}${GRUB_CMDLINE:+ $GRUB_CMDLINE}\"/" \
    /mnt/etc/default/grub
install -v -d -m 00755 "/mnt/usr/local/bin"
install -v -m 00755 /dev/null "/mnt/usr/local/bin/update-grub"
cat <<EOF >"/mnt/usr/local/bin/update-grub"
#!/bin/bash

set -euo pipefail

[[ ! "\${1:-}" =~ ^(-i|--install)\$ ]] ||
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF
while :; do
    in_target update-grub --install &&
        GRUB_INSTALLED=1 &&
        break
    lk_console_message "Boot loader installation failed (exit status $?)"
    lk_confirm "Try again?" Y || break
done

if ! lk_is_true GRUB_INSTALLED; then
    lk_console_message "To install the boot loader manually:" \
        'arch-chroot /mnt update-grub --install'
fi
lk_console_success "Bootstrap complete"

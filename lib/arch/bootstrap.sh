#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2034,SC2124,SC2206,SC2207

# To install Arch Linux using the script below:
#   1. boot from an Arch Linux live CD
#   2. wget https://lkr.ms/bs
#   3. bash bs

set -euo pipefail
shopt -s nullglob

PING_HOSTNAME="one.one.one.one"   # see https://blog.cloudflare.com/dns-resolver-1-1-1-1/
NTP_SERVER="ntp.linacreative.com" #
MOUNT_OPTIONS="defaults"          # ",discard" is added automatically if TRIM support is detected (VMs only)
TIMEZONE="Australia/Sydney"       # see /usr/share/zoneinfo
LOCALES=("en_AU" "en_GB")         # UTF-8 is enforced
LANGUAGE="en_AU:en_GB:en"
LK_BASE="/opt/lk-platform"
MIRROR="http://archlinux.mirror.linacreative.com/archlinux/\$repo/os/\$arch"
CUSTOM_REPOS=("aur http://arch.repo.linacreative.com/aur")

# these will be added to the defaults in packages.sh
PACMAN_PACKAGES=()
PACMAN_DESKTOP_PACKAGES=()
AUR_PACKAGES=()
AUR_DESKTOP_PACKAGES=()

lk_die() { echo "${BS:+$BS: }$1" >&2 && exit 1; }
BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    SCRIPT_DIR="$(cd "$(dirname "$BS")" && pwd -P)" ||
    lk_die "unable to resolve path to script"

function usage() {
    echo "\
usage: $(basename "$0") <root_partition> <boot_partition> [<other_os_partition>...] <hostname> <username>
   or: $(basename "$0") <install_disk> <hostname> <username>

Current block devices:

$(lsblk --output "NAME,RM,RO,SIZE,TYPE,FSTYPE,MOUNTPOINT" --paths)" >&2
    exit 1
}

function exit_trap() {
    exec >&6 2>&7 6>&- 7>&-
    [ ! -d "/mnt/boot" ] || {
        install -v -d -m 0755 "/mnt/var/log"
        install -v -m 0750 -g "adm" "$LOG_FILE" "/mnt/var/log/lk-bootstrap.log"
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
    ping -c 1 "${PING_HOSTNAME:-one.one.one.one}" || lk_die "no network"

    configure_ntp "/etc/ntp.conf"
    timedatectl set-ntp true
}

function in_target() {
    arch-chroot /mnt "$@"
}

function configure_ntp() {
    [ -z "${NTP_SERVER:-}" ] || {
        lk_console_detail "Configuring NTP"
        lk_keep_original "$1"
        sed -Ei 's/^(server|pool)\b/#&/' "$1"
        echo "server $NTP_SERVER iburst" >>"$1"
    }
}

function configure_pacman() {
    local i REPO SIG_LEVEL
    lk_console_detail "Configuring pacman"
    lk_keep_original "$1"
    sed -Ei 's/^#(Color|TotalDownload)\b/\1/' "$1"
    for i in "${!CUSTOM_REPOS[@]}"; do
        REPO=(${CUSTOM_REPOS[$i]})
        SIG_LEVEL=("${REPO[@]:2}")
        cat <<EOF >>"$1"

[${REPO[0]}]
SigLevel = ${SIG_LEVEL[*]:-Optional TrustAll}
Server = ${REPO[1]}
EOF
    done
}

[ -d "/sys/firmware/efi/efivars" ] || lk_die "not booted in UEFI mode"
[ "$EUID" -eq "0" ] || lk_die "not running as root"
[ "$#" -ge "3" ] || usage

LOG_FILE="/tmp/lk-bootstrap.$(date +'%s').log"
exec 6>&1 7>&2
exec > >(tee "$LOG_FILE") 2>&1
trap "exit_trap" EXIT

for FILE_PATH in /lib/bash/core.sh /lib/arch/packages.sh; do
    FILE="$SCRIPT_DIR/$(basename "$FILE_PATH")"
    URL="https://raw.githubusercontent.com/lkrms/lk-platform/master$FILE_PATH"
    [ -e "$FILE" ] ||
        wget --output-document="$FILE" "$URL" ||
        lk_die "unable to download from GitHub: $URL"
done

. "$SCRIPT_DIR/core.sh"

S="[[:space:]]"

lk_console_message "Setting up live environment"
configure_pacman "/etc/pacman.conf"
[ -z "$MIRROR" ] ||
    # pacstrap will copy this to the new system
    echo "Server=$MIRROR" >"/etc/pacman.d/mirrorlist"

. "$SCRIPT_DIR/packages.sh" >&6 2>&7

# in case we're starting over after a failed attempt
if [ -d "/mnt/boot" ]; then
    OTHER_OS_MOUNTS=(/mnt/mnt/*)
    [ "${#OTHER_OS_MOUNTS[@]}" -eq "0" ] || {
        umount "${OTHER_OS_MOUNTS[@]}" &&
            rmdir "${OTHER_OS_MOUNTS[@]}" || exit
    }
    umount /mnt/boot &&
        umount /mnt || exit
fi

OTHER_OS_PARTITIONS=()

if [ "$#" -eq "3" ]; then

    check_devices disk "$1" || usage

    before_install

    lk_confirm "Repartition $1? ALL DATA WILL BE LOST." || exit

    lk_console_message "Partitioning $1"
    parted --script "$1" \
        mklabel gpt \
        mkpart fat32 2048s 260MiB \
        mkpart ext4 260MiB 100% \
        set 1 boot on &&
        partprobe "$1" &&
        PARTITIONS=($(_lsblk "TYPE,NAME" --paths "$1" | grep -Po '(?<=^part ).*')) &&
        [ "${#PARTITIONS[@]}" -eq "2" ] &&
        ROOT_PARTITION="${PARTITIONS[1]}" &&
        BOOT_PARTITION="${PARTITIONS[0]}" &&
        wipefs -a "$ROOT_PARTITION" &&
        wipefs -a "$BOOT_PARTITION"

    REPARTITIONED=1
    TARGET_HOSTNAME="$2"
    TARGET_USERNAME="$3"

elif [ "$#" -ge "4" ]; then

    check_devices part "${@:1:$#-2}" || usage

    before_install

    REPARTITIONED=0
    ROOT_PARTITION="$1"
    BOOT_PARTITION="$2"
    OTHER_OS_PARTITIONS=("${@:3:$#-4}")
    TARGET_HOSTNAME="${@: -2:1}"
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

ROOT_PARTITION_TYPE="$(_lsblk FSTYPE "$ROOT_PARTITION")" || lk_die "no block device at $ROOT_PARTITION"
BOOT_PARTITION_TYPE="$(_lsblk FSTYPE "$BOOT_PARTITION")" || lk_die "no block device at $BOOT_PARTITION"

KEEP_BOOT_PARTITION=0
case "$BOOT_PARTITION_TYPE" in
vfat)
    ! lk_confirm "$BOOT_PARTITION already has a vfat filesystem. Leave it as-is?" || KEEP_BOOT_PARTITION=1
    ;;&

vfat | "")
    if lk_is_false "$KEEP_BOOT_PARTITION"; then
        lk_is_true "$REPARTITIONED" ||
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

lk_is_true "$REPARTITIONED" ||
    lk_confirm "OK to format $ROOT_PARTITION as ext4?" || exit

lk_console_message "Formatting $ROOT_PARTITION"
mkfs.ext4 -vL root "$ROOT_PARTITION"

lk_console_message "Mounting partitions"
if lk_is_virtual; then
    ! is_ssd "$ROOT_PARTITION" || ROOT_OPTION_EXTRA=",discard"
    ! is_ssd "$BOOT_PARTITION" || BOOT_OPTION_EXTRA=",discard"
fi
mount -o "${MOUNT_OPTIONS:-defaults}${ROOT_OPTION_EXTRA:-}" "$ROOT_PARTITION" /mnt &&
    mkdir /mnt/boot &&
    mount -o "${MOUNT_OPTIONS:-defaults}${BOOT_OPTION_EXTRA:-}" "$BOOT_PARTITION" /mnt/boot || exit

lk_console_message "Installing system"
pacstrap /mnt "${PACMAN_PACKAGES[@]}" >&6 2>&7

lk_console_message "Setting up installed system"

lk_console_detail "Generating fstab"
lk_keep_original "/mnt/etc/fstab"
genfstab -U /mnt >>"/mnt/etc/fstab"

configure_pacman "/mnt/etc/pacman.conf"

configure_ntp "/mnt/etc/ntp.conf"
in_target systemctl enable ntpd.service

lk_console_detail "Setting the time zone"
ln -sfv "/usr/share/zoneinfo/${TIMEZONE:-UTC}" "/mnt/etc/localtime"

lk_console_detail "Configuring hardware clock"
in_target hwclock --systohc

LOCALES=(${LOCALES[@]+"${LOCALES[@]}"} "en_US")
IFS=$'\n'
lk_console_detail "Configuring locales"
unset IFS
lk_keep_original "/mnt/etc/locale.gen"
for _LOCALE in $(printf '%s\n' "${LOCALES[@]}" | sed 's/\..*$//' | sort | uniq); do
    sed -Ei "s/^#($(lk_escape_ere "$_LOCALE")\\.UTF-8$S+UTF-8)\\b/\\1/" "/mnt/etc/locale.gen"
done
in_target locale-gen

lk_keep_original "/mnt/etc/locale.conf"
cat <<EOF >"/mnt/etc/locale.conf"
LANG=${LOCALES[0]}.UTF-8${LANGUAGE:+
LANGUAGE=$LANGUAGE}
EOF

lk_console_detail "Setting hostname"
lk_keep_original "/mnt/etc/hostname"
echo "$TARGET_HOSTNAME" >"/mnt/etc/hostname"

lk_console_detail "Configuring hosts"
lk_keep_original "/mnt/etc/hosts"
cat <<EOF >>"/mnt/etc/hosts"
127.0.0.1 localhost
::1 localhost
127.0.1.1 $TARGET_HOSTNAME.localdomain $TARGET_HOSTNAME
EOF

if [ "${#PACMAN_DESKTOP_PACKAGES[@]}" -eq "0" ]; then
    in_target systemctl set-default multi-user.target
else
    in_target systemctl set-default graphical.target

    lk_console_detail "Enabling LightDM"
    in_target systemctl enable lightdm.service

    mkdir -p "/mnt/etc/skel/.config/xfce4" &&
        ln -s "$LK_BASE/etc/xfce4/xinitrc" \
            "/mnt/etc/skel/.config/xfce4/xinitrc"
fi

lk_console_detail "Setting default umask"
lk_keep_original "/mnt/etc/profile"
sed -Ei 's/^umask [0-9]+\b/umask 002/' "/mnt/etc/profile"
umask 002

lk_console_detail "Creating superuser:" "$TARGET_USERNAME"
in_target useradd -m "$TARGET_USERNAME" -G adm,wheel -s /bin/bash
echo -e "$TARGET_PASSWORD\n$TARGET_PASSWORD" | in_target passwd "$TARGET_USERNAME"

lk_console_detail "Configuring sudo"
cat <<EOF >"/mnt/etc/sudoers.d/lk-defaults"
Defaults umask = 0002
Defaults umask_override
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD:/usr/bin/pacman
EOF
chmod 600 "/mnt/etc/sudoers.d/lk-defaults"

lk_console_detail "Disabling root password"
in_target passwd -l root

lk_console_detail "Installing lk-platform to:" "$LK_BASE"
in_target install -v -d -m 2775 -o "$TARGET_USERNAME" -g "adm" \
    "$LK_BASE"
in_target sudo -H -u "$TARGET_USERNAME" \
    git clone "https://github.com/lkrms/lk-platform.git" "$LK_BASE"
echo "LK_BASE=\"$LK_BASE\"" >"/mnt/etc/default/lk-platform"

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
    cat <<EOF >"/mnt/etc/tlp.d/90-lk-defaults.conf"
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

if [ "${#AUR_PACKAGES[@]}" -gt "0" ]; then
    lk_console_message "Installing AUR packages"
    AUR_SCRIPT="{ $YAY_SCRIPT; } &&
    yay -Sy --aur --needed --noconfirm ${AUR_PACKAGES[*]}"
    in_target sudo -H -u "$TARGET_USERNAME" \
        bash -c "$AUR_SCRIPT" >&6 2>&7
fi

i=0
for PARTITION in ${OTHER_OS_PARTITIONS[@]+"${OTHER_OS_PARTITIONS[@]}"}; do
    MOUNT_DIR="/mnt/mnt/temp$i"
    mkdir -p "$MOUNT_DIR" &&
        mount "$PARTITION" "$MOUNT_DIR" || lk_console_warning "unable to mount partition $PARTITION"
    ((++i))
done

! lk_is_true "$KEEP_BOOT_PARTITION" || {
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
            mount -o "${MOUNT_OPTIONS:-defaults}${BOOT_OPTION_EXTRA:-}" "$BOOT_PARTITION" /mnt/boot || exit
    }
}
lk_console_message "Installing boot loader"
lk_keep_original "/mnt/etc/default/grub"
! lk_is_virtual || CMDLINE_EXTRA="console=tty0 console=ttyS0"
sed -Ei -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
    -e 's/^#?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
    -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet loglevel=3 audit=0${CMDLINE_EXTRA:+ $CMDLINE_EXTRA}\"/" \
    /mnt/etc/default/grub
install -v -d -m 0755 "/mnt/usr/local/bin"
install -v -m 0755 /dev/null "/mnt/usr/local/bin/update-grub"
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

lk_console_message "Bootstrap complete" "$LK_GREEN"
if lk_is_true "${GRUB_INSTALLED:-0}"; then
    lk_console_detail "Reboot at your leisure"
else
    lk_console_detail "To install the boot loader manually:" \
        'arch-chroot /mnt update-grub --install'
fi

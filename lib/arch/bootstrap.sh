#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2016,SC2034,SC2124,SC2206,SC2207

# To install Arch Linux using the script below:
#   1. boot from an Arch Linux live CD
#   2. wget https://lkr.ms/bootstrap
#   3. bash bootstrap

set -euo pipefail
shopt -s nullglob

PING_HOSTNAME="one.one.one.one"   # see https://blog.cloudflare.com/dns-resolver-1-1-1-1/
NTP_SERVER="ntp.linacreative.com" #
MOUNT_OPTIONS="defaults"          # ",discard" is added automatically if supported
TIMEZONE="Australia/Sydney"       # see /usr/share/zoneinfo
LOCALES=("en_AU" "en_GB")         # UTF-8 is enforced
LANGUAGE="en_AU:en_GB:en"
MIRROR="http://archlinux.mirror.linacreative.com/archlinux/\$repo/os/\$arch"

# these will be added to the defaults in packages.sh
PACMAN_PACKAGES=()
PACMAN_DESKTOP_PACKAGES=()
AUR_PACKAGES=()
AUR_DESKTOP_PACKAGES=()

lk_die() { echo "${BS:+$BS: }$1" >&2 && exit 1; }
BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    SCRIPT_DIR="$(cd "$(dirname "$BS")" && pwd -P)" ||
    lk_die "unable to identify script directory"

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
    lk_console_detail "Configuring pacman"
    lk_keep_original "$1"
    sed -Ei 's/^#(Color|TotalDownload)\b/\1/' "$1"
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
    # pacstrap copies this to the new system
    echo "Server=$MIRROR" >"/etc/pacman.d/mirrorlist"

. "$SCRIPT_DIR/packages.sh" >&6 2>&7

# in case we're starting over
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
[ -n "$TARGET_PASSWORD" ] || {
    while :; do
        TARGET_PASSWORD="$(lk_console_read_secret "Password for $TARGET_USERNAME:")" || lk_die
        [ -n "$TARGET_PASSWORD" ] || lk_warn "Password cannot be empty" || continue
        CONFIRM_PASSWORD="$(lk_console_read_secret "Password for $TARGET_USERNAME (again):")" || lk_die
        [ "$TARGET_PASSWORD" = "$CONFIRM_PASSWORD" ] || lk_warn "Passwords do not match" || continue
        break
    done
}

ROOT_PARTITION_TYPE="$(_lsblk FSTYPE "$ROOT_PARTITION")" || lk_die "no block device at $ROOT_PARTITION"
BOOT_PARTITION_TYPE="$(_lsblk FSTYPE "$BOOT_PARTITION")" || lk_die "no block device at $BOOT_PARTITION"

if [ "$BOOT_PARTITION_TYPE" = "vfat" ] &&
    ! lk_confirm "$BOOT_PARTITION already has a vfat filesystem. Leave it as-is?" ||
    [ -z "$BOOT_PARTITION_TYPE" ]; then

    [ "$REPARTITIONED" -eq "1" ] ||
        lk_confirm "OK to format $BOOT_PARTITION as FAT32?"

    lk_console_message "Formatting $BOOT_PARTITION"
    mkfs.fat -vn ESP -F 32 "$BOOT_PARTITION"

elif [ "$BOOT_PARTITION_TYPE" != "vfat" ]; then

    lk_die "unexpected filesystem at $BOOT_PARTITION: $BOOT_PARTITION_TYPE"

fi

[ -z "$ROOT_PARTITION_TYPE" ] ||
    lk_console_warning "Unexpected filesystem at $ROOT_PARTITION: $ROOT_PARTITION_TYPE"

[ "$REPARTITIONED" -eq "1" ] ||
    lk_confirm "OK to format $ROOT_PARTITION as ext4?" || exit

lk_console_message "Formatting $ROOT_PARTITION"
mkfs.ext4 -vL root "$ROOT_PARTITION"

lk_console_message "Mounting partitions"
! is_ssd "$ROOT_PARTITION" || ROOT_OPTION_EXTRA=",discard"
! is_ssd "$BOOT_PARTITION" || BOOT_OPTION_EXTRA=",discard"
mount -o "${MOUNT_OPTIONS:-defaults}${ROOT_OPTION_EXTRA:-}" "$ROOT_PARTITION" /mnt &&
    mkdir /mnt/boot &&
    mount -o "${MOUNT_OPTIONS:-defaults}${BOOT_OPTION_EXTRA:-}" "$BOOT_PARTITION" /mnt/boot || exit

i=0
for PARTITION in ${OTHER_OS_PARTITIONS[@]+"${OTHER_OS_PARTITIONS[@]}"}; do
    MOUNT_DIR="/mnt/mnt/temp$i"
    mkdir -p "$MOUNT_DIR" &&
        mount "$PARTITION" "$MOUNT_DIR" || lk_die "unable to mount partition $PARTITION"
    ((++i))
done

lk_console_message "Installing system"
pacstrap /mnt "${PACMAN_PACKAGES[@]}" >&6 2>&7

lk_console_message "Setting up installed system"

LOCALES=(${LOCALES[@]+"${LOCALES[@]}"} "en_US")
IFS=$'\n'
lk_console_detail "Enabling locales:" "${LOCALES[*]}"
unset IFS
lk_keep_original "/mnt/etc/locale.gen"
for _LOCALE in $(printf '%s\n' "${LOCALES[@]}" | sed 's/\..*$//' | sort | uniq); do
    sed -Ei "s/^#($(lk_escape_ere "$_LOCALE")\\.UTF-8$S+UTF-8)\\b/\\1/" "/mnt/etc/locale.gen"
done

lk_console_detail "Generating" "/etc/fstab"
lk_keep_original "/mnt/etc/fstab"
genfstab -U /mnt >>"/mnt/etc/fstab"

lk_console_detail "Configuring sudo"
cat <<EOF >"/mnt/etc/sudoers.d/90-wheel"
%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD:/usr/bin/pacman
EOF

lk_console_detail "Configuring languages"
lk_keep_original "/mnt/etc/locale.conf"
cat <<EOF >"/mnt/etc/locale.conf"
LANG=${LOCALES[0]}.UTF-8${LANGUAGE:+
LANGUAGE=$LANGUAGE}
EOF

lk_console_detail "Setting hostname"
lk_keep_original "/mnt/etc/hostname"
echo "$TARGET_HOSTNAME" >"/mnt/etc/hostname"

lk_console_detail "Configuring" "/etc/hosts"
lk_keep_original "/mnt/etc/hosts"
cat <<EOF >"/mnt/etc/hosts"
127.0.0.1 localhost
::1 localhost
127.0.1.1 $TARGET_HOSTNAME.localdomain $TARGET_HOSTNAME
EOF

lk_console_detail "Generating locales"
in_target locale-gen

if lk_is_qemu; then
    lk_console_detail "Enabling QEMU guest agent"
    in_target systemctl enable qemu-ga.service ||
        lk_console_warning "Could not enable qemu-ga.service"
fi

lk_console_detail "Enabling NetworkManager"
in_target systemctl enable NetworkManager.service

if [ "${#PACMAN_DESKTOP_PACKAGES[@]}" -eq "0" ]; then
    in_target systemctl set-default multi-user.target
else
    in_target systemctl set-default graphical.target

    lk_console_detail "Enabling LightDM"
    in_target systemctl enable lightdm.service

    mkdir -p "/mnt/etc/skel/.config/xfce4" &&
        cat <<EOF >"/mnt/etc/skel/.config/xfce4/xinitrc"
#!/bin/sh
xset -b
xset s 240 60
export XSECURELOCK_DIM_TIME_MS=750
export XSECURELOCK_WAIT_TIME_MS=60000

XSECURELOCK_FONT="$(xfconf-query -c xsettings -p /Gtk/MonospaceFontName)" &&
    export XSECURELOCK_FONT ||
    unset XSECURELOCK_FONT

export XSECURELOCK_SAVER="saver_blank"
export XSECURELOCK_SHOW_DATETIME=1
export XSECURELOCK_AUTH_TIMEOUT=20
xss-lock -n /usr/lib/xsecurelock/dimmer -l -- xsecurelock &

xfconf-query -c xfce4-session -p /general/LockCommand -n -t string -s "xset s activate"

. /etc/xdg/xfce4/xinitrc
EOF
fi

lk_console_detail "Setting time zone to" "${TIMEZONE:-UTC}"
ln -sfv "/usr/share/zoneinfo/${TIMEZONE:-UTC}" "/mnt/etc/localtime"

lk_console_detail "Configuring hardware clock"
in_target hwclock --systohc

lk_console_detail "Adding superuser" "$TARGET_USERNAME"
in_target useradd -m "$TARGET_USERNAME" -G adm,wheel -s /bin/bash
echo -e "$TARGET_PASSWORD\n$TARGET_PASSWORD" | in_target passwd "$TARGET_USERNAME"

lk_console_detail "Disabling root password"
in_target passwd -l root

configure_pacman "/mnt/etc/pacman.conf"

configure_ntp "/mnt/etc/ntp.conf"
in_target systemctl enable ntpd.service

if [ "${#AUR_PACKAGES[@]}" -gt "0" ]; then
    lk_console_message "Installing AUR packages"
    AUR_SCRIPT="$(
        cat <<EOF
YAY_DIR="\$(mktemp -d)" &&
    git clone "https://aur.archlinux.org/yay.git" "\$YAY_DIR" &&
    cd "\$YAY_DIR" && makepkg --install --noconfirm &&
    yay -Sy --aur --needed --noconfirm ${AUR_PACKAGES[*]}
EOF
    )"
    in_target sudo -H -u "$TARGET_USERNAME" bash -c "$AUR_SCRIPT"
fi

lk_console_message "Installing boot loader"
lk_keep_original "/mnt/etc/default/grub"
sed -Ei -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
    -e 's/^#?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
    -e 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 audit=0"/' \
    /mnt/etc/default/grub
while :; do
    in_target grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB &&
        in_target grub-mkconfig -o /boot/grub/grub.cfg &&
        break
    lk_confirm "Boot loader installation failed. Try again?" Y || exit
done

lk_console_message "Bootstrap complete" "$LK_GREEN"
lk_console_detail "Reboot at your leisure"

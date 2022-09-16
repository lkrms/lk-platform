#!/bin/bash

# To install Arch Linux using the script below:
# 1. boot from an Arch Linux live CD
# 2. wpa_supplicant -B -i wlan0 -c <(wpa_passphrase SSID passphrase)
# 3. bash -c "$(curl -fsSL http://lkr.ms/bs)" bootstrap.sh [OPTIONS...]
#
# e.g. to automatically partition `/dev/vda` and provision Xfce4 using hostname
# 'archlinux', default user 'susan', the `develop` branch of lk-platform, local
# mirror 'arch.mirror' and packages defined in `packages/arch/desktop.sh`:
#
#     LK_PLATFORM_BRANCH=develop \
#         LK_ARCH_MIRROR='http://arch.mirror/$repo/os/$arch' \
#         bash -c "$(curl -fsSL http://lkr.ms/bs-dev)" \
#         bootstrap.sh -xu susan -k desktop /dev/vda archlinux

LK_PATH_PREFIX=${LK_PATH_PREFIX:-lk-} &&
    _DIR=/tmp/${LK_PATH_PREFIX}install &&
    mkdir -p "$_DIR" || exit

[[ $- != *c* ]] ||
    { _FILE="$_DIR/bootstrap.sh" &&
        echo "$BASH_EXECUTION_STRING" >"$_FILE" &&
        { [[ $- != *x* ]] || export SHELLOPTS=xtrace; } &&
        exec "$BASH" "$_FILE" "$@" || exit; }

set -euo pipefail
lk_die() { s=$? && echo "$0: ${1-error $s}" >&2 && (exit $s) && false || exit; }
lk_log() { trap "" SIGINT && exec perl -pe 'BEGIN {
  $| = 1;
  use POSIX qw{strftime};
  use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );
s/.*\r(.)/\1/;'; }

LOG_FILE=$_DIR/install.$(date +%s)
exec 4> >(lk_log >"$LOG_FILE.trace")
BASH_XTRACEFD=4
set -x

shopt -s nullglob

DEFAULT_CMDLINE="quiet loglevel=3 audit=0$(! grep -q \
    '^flags[[:blank:]]*:.*\bhypervisor\b' /proc/cpuinfo &>/dev/null ||
    echo " console=tty0 console=ttyS0")"
BOOTSTRAP_PING_HOST=${BOOTSTRAP_PING_HOST:-one.one.one.one}            # https://blog.cloudflare.com/dns-resolver-1-1-1-1/
BOOTSTRAP_TIME_URL=${BOOTSTRAP_TIME_URL:-https://$BOOTSTRAP_PING_HOST} #
BOOTSTRAP_MOUNT_OPTIONS=${BOOTSTRAP_MOUNT_OPTIONS:-defaults}           # On VMs with TRIM support, "discard" is added automatically
BOOTSTRAP_USERNAME=${BOOTSTRAP_USERNAME:-arch}                         #
BOOTSTRAP_PASSWORD=${BOOTSTRAP_PASSWORD-}                              #
BOOTSTRAP_KEY=${BOOTSTRAP_KEY-}                                        #
BOOTSTRAP_FULL_NAME=${BOOTSTRAP_FULL_NAME:-Arch Linux}                 #
LK_IPV4_ADDRESS=${LK_IPV4_ADDRESS-}                                    #
LK_IPV4_GATEWAY=${LK_IPV4_GATEWAY-}                                    #
LK_DNS_SERVERS=${LK_DNS_SERVERS-}                                      # Space- or semicolon-delimited
LK_DNS_SEARCH=${LK_DNS_SEARCH-}                                        #
LK_BRIDGE_INTERFACE=${LK_BRIDGE_INTERFACE-}                            #
LK_WIFI_REGDOM=${LK_WIFI_REGDOM-}                                      # e.g. "AU"
LK_NODE_TIMEZONE=${LK_NODE_TIMEZONE:-UTC}                              # See `timedatectl list-timezones`
LK_NODE_SERVICES=${LK_NODE_SERVICES-}                                  #
LK_NODE_LOCALES=${LK_NODE_LOCALES-en_AU.UTF-8 en_GB.UTF-8}             # "en_US.UTF-8" is added automatically
LK_NODE_LANGUAGE=${LK_NODE_LANGUAGE-en_AU:en_GB:en}                    #
LK_SAMBA_WORKGROUP=${LK_SAMBA_WORKGROUP-}                              #
LK_GRUB_CMDLINE=${LK_GRUB_CMDLINE-$DEFAULT_CMDLINE}                    #
LK_NTP_SERVER=${LK_NTP_SERVER-time.apple.com}                          #
LK_ARCH_MIRROR=${LK_ARCH_MIRROR-}                                      #
LK_ARCH_REPOS=${LK_ARCH_REPOS-}                                        # REPO|SERVER|KEY_URL|KEY_ID|SIG_LEVEL,...
LK_ARCH_AUR_REPO_NAME=${LK_ARCH_AUR_REPO_NAME-}                        # If set, a local aurutils repo will be provisioned
LK_ARCH_AUR_CHROOT_DIR=${LK_ARCH_AUR_CHROOT_DIR-}                      # Default: /var/lib/aurbuild
LK_PLATFORM_BRANCH=${LK_PLATFORM_BRANCH:-main}
LK_PACKAGES_FILE=${LK_PACKAGES_FILE-}
export LK_BASE=${LK_BASE:-/opt/lk-platform}
export -n BOOTSTRAP_PASSWORD BOOTSTRAP_KEY

[ -d /sys/firmware/efi/efivars ] || lk_die "not booted in UEFI mode"
[ "$EUID" -eq 0 ] || lk_die "not running as root"
[ "$OSTYPE" = linux-gnu ] || lk_die "not running on Linux"
[ -f /etc/arch-release ] || lk_die "not running on Arch Linux"
[[ $- != *s* ]] || lk_die "cannot run from standard input"

LK_USAGE="\
Usage: ${0##*/} [OPTIONS] ROOT_PART BOOT_PART HOSTNAME[.DOMAIN]
   or: ${0##*/} [OPTIONS] INSTALL_DISK HOSTNAME[.DOMAIN]

Options:
  -u USERNAME       set the default user's login name (default: arch)
  -o PARTITION      add the operating system on PARTITION to the boot menu
                    (may be given multiple times)
  -c CMDLINE        set the default kernel command-line
                    (default: \"$DEFAULT_CMDLINE\")
  -p PARAMETER      add PARAMETER to the default kernel command-line
  -s SERVICE,...    enable each SERVICE
  -x                install Xfce (alias for: -s xfce4)
  -k FILE           set LK_PACKAGES_FILE
  -y                do not prompt for input

Useful kernel parameters:
  usbcore.autosuspend=5     wait 5 seconds to suspend (default: 2, never: -1)
  libata.force=3.00:noncq   disable NCQ on ATA device 3.00
  mce=dont_log_ce           do not log corrected machine check errors

Block devices:
$(lsblk --output NAME,RM,SIZE,RO,TYPE,FSTYPE,MOUNTPOINT --paths |
    sed 's/^/  /')"

ROOT_PART=
BOOT_PART=
INSTALL_DISK=
OTHER_OS_PARTITIONS=()
PAC_REPOS=()

CURL_OPTIONS=(
    --fail
    --header "Cache-Control: no-cache"
    --header "Pragma: no-cache"
    --location
    --retry 2
    --show-error
    --silent
)

YELLOW=$'\E[33m'
CYAN=$'\E[36m'
BOLD=$'\E[1m'
RESET=$'\E[m'
echo "$BOLD$CYAN==> $RESET${BOLD}Checking prerequisites$RESET" >&2
REPO_URL=https://raw.githubusercontent.com/lkrms/lk-platform
_LK_SOURCED=
for FILE_PATH in \
    /lib/bash/include/core.sh \
    /lib/bash/include/provision.sh \
    /lib/bash/include/linux.sh \
    /lib/bash/include/arch.sh \
    /lib/arch/packages.sh \
    /lib/awk/section-get.awk \
    /lib/awk/section-replace.awk \
    /share/sudoers.d/default; do
    FILE=$_DIR/${FILE_PATH##*/}
    URL=$REPO_URL/$LK_PLATFORM_BRANCH$FILE_PATH
    MESSAGE="$BOLD$YELLOW -> $RESET{}$YELLOW $URL$RESET"
    if [ ! -e "$FILE" ]; then
        echo "${MESSAGE/{\}/Downloading:}" >&2
        curl "${CURL_OPTIONS[@]}" --output "$FILE" "$URL" || {
            rm -f "$FILE"
            lk_die "unable to download: $URL"
        }
    else
        echo "${MESSAGE/{\}/Already downloaded:}" >&2
    fi
    [[ ! $FILE_PATH =~ /include/([a-z0-9_]+)\.sh$ ]] || {
        _LK_SOURCED+=,${BASH_REMATCH[1]}
        . "$FILE"
    }
done

while getopts ":u:o:c:p:s:xk:y" OPT; do
    case "$OPT" in
    u)
        BOOTSTRAP_USERNAME=$OPTARG
        ;;
    o)
        lk_block_device_is part "$OPTARG" ||
            lk_warn "invalid partition: $OPTARG" || lk_usage
        OTHER_OS_PARTITIONS+=("$OPTARG")
        ;;
    c)
        LK_GRUB_CMDLINE=$OPTARG
        ;;
    p)
        LK_GRUB_CMDLINE=${LK_GRUB_CMDLINE:+$LK_GRUB_CMDLINE }$OPTARG
        ;;
    s)
        [[ $OPTARG =~ ^[-a-z0-9+._]+(,[-a-z0-9+._]+)*$ ]] ||
            lk_warn "invalid service: $OPTARG" || lk_usage
        LK_NODE_SERVICES=${LK_NODE_SERVICES:+$LK_NODE_SERVICES,}$OPTARG
        ;;
    x)
        LK_NODE_SERVICES=${LK_NODE_SERVICES:+$LK_NODE_SERVICES,}xfce4
        ;;
    k)
        LK_PACKAGES_FILE=$OPTARG
        ;;
    y)
        LK_NO_INPUT=Y
        ;;
    \? | :)
        lk_usage
        ;;
    esac
done
shift $((OPTIND - 1))
case $# in
3)
    lk_block_device_is part "${@:1:2}" ||
        lk_warn "invalid partitions: ${*:1:2}" || lk_usage
    ROOT_PART=$1
    BOOT_PART=$2
    ;;
2)
    lk_block_device_is disk "$1" ||
        lk_warn "invalid disk: $1" || lk_usage
    INSTALL_DISK=$1
    ;;
*)
    lk_usage
    ;;
esac
LK_NODE_FQDN=${*: -1:1}
LK_NODE_HOSTNAME=${LK_NODE_FQDN%%.*}
[ "$LK_NODE_FQDN" != "$LK_NODE_HOSTNAME" ] ||
    LK_NODE_FQDN=
LK_NODE_SERVICES=$(IFS=, &&
    lk_echo_args $LK_NODE_SERVICES | sort -u | lk_implode_input ",")

PASSWORD_GENERATED=0
if [ -z "$BOOTSTRAP_KEY" ]; then
    if [ -z "$BOOTSTRAP_PASSWORD" ] && lk_no_input; then
        lk_tty_print \
            "Generating a random password for user" "$BOOTSTRAP_USERNAME"
        BOOTSTRAP_PASSWORD=$(lk_random_password 7)
        PASSWORD_GENERATED=1
        lk_tty_detail "Password:" "$BOOTSTRAP_PASSWORD"
        lk_tty_log "The password above will be repeated when ${0##*/} exits"
    fi
    while [ -z "$BOOTSTRAP_PASSWORD" ]; do
        lk_tty_read_silent \
            "Password for $BOOTSTRAP_USERNAME:" BOOTSTRAP_PASSWORD
        [ -n "$BOOTSTRAP_PASSWORD" ] ||
            lk_warn "Password cannot be empty" || continue
        lk_tty_read_silent \
            "Password for $BOOTSTRAP_USERNAME (again):" CONFIRM_PASSWORD
        [ "$BOOTSTRAP_PASSWORD" = "$CONFIRM_PASSWORD" ] || {
            BOOTSTRAP_PASSWORD=
            lk_warn "Passwords do not match"
            continue
        }
        break
    done
fi

lk_tty_print

function exit_trap() {
    local STATUS=$?
    [ "$BASH_SUBSHELL" -eq 0 ] || return "$STATUS"
    [ ! -d /mnt/boot ] || {
        set +x
        unset BASH_XTRACEFD
        exec 4>-
        lk_log_close || true
        local LOG FILE
        for LOG in "$LOG_FILE".{log,out,trace}; do
            FILE=/var/log/${LK_PATH_PREFIX}${LOG##*/}
            in_target install -m 00640 -g adm /dev/null "$FILE" &&
                cp -v --preserve=timestamps "$LOG" "/mnt/${FILE#/}" || break
        done
    }
    ((!PASSWORD_GENERATED)) ||
        lk_tty_log \
            "The random password generated for user '$BOOTSTRAP_USERNAME' is" \
            "$BOOTSTRAP_PASSWORD"
    return "$STATUS"
}

function in_target() {
    [ -d /mnt/boot ] || lk_die "no target mounted"
    if [ "${1-}" != -u ]; then
        arch-chroot /mnt "$@"
    else
        (unset _LK_{{TTY,LOG}_{OUT,ERR},LOG}_FD _LK_LOG2_FD &&
            arch-chroot /mnt runuser "${@:1:2}" -- "${@:3}")
    fi
}

function system_time() {
    date "$@" +"%a, %d %b %Y %H:%M:%S %Z"
}

lk_log_start "$LOG_FILE"
lk_log_tty_off
lk_trap_add EXIT exit_trap

# Clean up after failed attempts
if [ -d /mnt/boot ]; then
    OTHER_OS_MOUNTS=(/mnt/mnt/*)
    if [ ${#OTHER_OS_MOUNTS[@]} -gt 0 ]; then
        umount "${OTHER_OS_MOUNTS[@]}"
        rmdir "${OTHER_OS_MOUNTS[@]}"
    fi
    umount /mnt/boot
    umount /mnt
fi

lk_tty_log "Setting up live environment"
FILES=(/etc/pacman.conf{.orig,})
! lk_files_exist "${FILES[@]}" ||
    mv -fv "${FILES[@]}"
lk_arch_configure_pacman
if [ -n "$LK_ARCH_MIRROR" ]; then
    lk_systemctl_disable_now reflector || true
    echo "Server=$LK_ARCH_MIRROR" >/etc/pacman.d/mirrorlist
fi

lk_tty_print "Checking network connection"
ping -c 1 "$BOOTSTRAP_PING_HOST" || lk_die "no network"

lk_tty_print "Syncing system time"
lk_tty_detail "Before syncing:" "$(system_time)"
NOW=$(curl -fsSI "$BOOTSTRAP_TIME_URL" | awk '
    { $1 = tolower($1); if(sub(/^date:[[:blank:]]*/, "")) { d = $0 } }
END { if (d) { print d } else { exit 1 } }') &&
    NOW=$(system_time --set "$NOW") ||
    lk_die "unable to sync system time with $BOOTSTRAP_TIME_URL"
lk_tty_detail "After syncing with $BOOTSTRAP_TIME_URL:" "$NOW"

lk_tty_print "Checking pacman keyring"
DIR=/etc/pacman.d/gnupg/private-keys-v1.d
if ! MODIFIED=$(lk_file_modified "$DIR" 2>/dev/null); then
    lk_tty_detail "Initialising keyring"
    lk_arch_reset_pacman_keyring
elif [[ $(lk_timestamp) -lt $MODIFIED ]]; then
    lk_tty_warning "Master key was created in the future"
    lk_tty_detail "Resetting keyring"
    lk_arch_reset_pacman_keyring
fi
lk_pac_sync
if pacman -Sup --print-format "%n" | grep -Fx archlinux-keyring >/dev/null; then
    lk_log_bypass -o lk_faketty pacman -S --noconfirm archlinux-keyring
fi

. "$_DIR/packages.sh"

lk_tty_print
lk_tty_log "Checking disk partitions"
REPARTITIONED=0
if [ -n "$INSTALL_DISK" ]; then
    lk_tty_yn "Repartition $INSTALL_DISK? ALL DATA WILL BE LOST." Y
    lk_tty_print "Partitioning:" "$INSTALL_DISK"
    lk_tty_run_detail parted --script "$INSTALL_DISK" \
        "mklabel gpt" \
        "mkpart fat32 2048s 300MiB" \
        "mkpart ext4 300MiB 100%" \
        "set 1 boot on"
    partprobe "$INSTALL_DISK"
    sleep 1
    PARTITIONS=($(_lk_lsblk TYPE,NAME --paths "$INSTALL_DISK" |
        awk '$1=="part"{print $2}'))
    [ ${#PARTITIONS[@]} -eq 2 ] &&
        ROOT_PART=${PARTITIONS[1]} &&
        BOOT_PART=${PARTITIONS[0]} || lk_die "invalid partition table"
    lk_tty_run_detail wipefs -a "$ROOT_PART"
    lk_tty_run_detail wipefs -a "$BOOT_PART"
    REPARTITIONED=1
fi

ROOT_FSTYPE=$(_lk_lsblk FSTYPE "$ROOT_PART") ||
    lk_die "not a partition: $ROOT_PART"
SH="BOOT_TYPE=($(_lk_lsblk -q FSTYPE,FSVER,PARTTYPE "$BOOT_PART"))" &&
    eval "$SH" ||
    lk_die "not a partition: $BOOT_PART"

FORMAT_BOOT=1
if [ "${BOOT_TYPE[0]}" = vfat ] &&
    [ "${BOOT_TYPE[2]}" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]; then
    lk_tty_print \
        "ESP at $BOOT_PART already formatted as ${BOOT_TYPE[1]}; leaving as-is"
    FORMAT_BOOT=0
else
    [ -z "${BOOT_TYPE[0]}" ] ||
        lk_warn "Unexpected ${BOOT_TYPE[0]} filesystem at $BOOT_PART" || true
    ((REPARTITIONED)) ||
        lk_tty_yn "OK to format ESP at $BOOT_PART as fat32?" Y ||
        lk_die ""
fi

[ -z "$ROOT_FSTYPE" ] ||
    lk_warn "Unexpected $ROOT_FSTYPE filesystem at $ROOT_PART" || true
((REPARTITIONED)) ||
    lk_tty_yn "OK to format $ROOT_PART as ext4?" Y ||
    lk_die ""

lk_tty_print "Formatting:" \
    "$( ((!FORMAT_BOOT)) || echo "$BOOT_PART ")$ROOT_PART"
((!FORMAT_BOOT)) ||
    lk_tty_run_detail mkfs.fat -vn ESP -F 32 "$BOOT_PART"
lk_tty_run_detail mkfs.ext4 -vL root "$ROOT_PART"

if lk_is_virtual; then
    ! lk_block_device_is_ssd "$ROOT_PART" || ROOT_EXTRA=,discard
    ! lk_block_device_is_ssd "$BOOT_PART" || BOOT_EXTRA=,discard
fi
lk_tty_run_detail mount \
    -o "$BOOTSTRAP_MOUNT_OPTIONS${ROOT_EXTRA-}" \
    "$ROOT_PART" /mnt
install -d -m 00755 /mnt/boot
lk_tty_run_detail mount \
    -o "$BOOTSTRAP_MOUNT_OPTIONS${BOOT_EXTRA-}" \
    "$BOOT_PART" /mnt/boot

if ((!FORMAT_BOOT)); then
    lk_tty_print "Removing files from previous installations in ESP"
    rm -Rfv /mnt/boot/{syslinux,intel-ucode.img,amd-ucode.img}
fi

lk_tty_print
lk_tty_log "Installing system"
lk_log_bypass -o lk_faketty pacstrap /mnt "${PAC_PACKAGES[@]}"

lk_tty_print
lk_tty_log "Setting up installed system"
_LK_ARCH_ROOT=/mnt

lk_tty_print "Generating /etc/fstab"
FILE=/mnt/etc/fstab
lk_install -m 00644 "$FILE"
lk_file_keep_original "$FILE"
genfstab -U /mnt >>"$FILE"

lk_tty_print "Setting system time zone"
FILE=/usr/share/zoneinfo/$LK_NODE_TIMEZONE
LK_VERBOSE=1 \
    lk_symlink "$FILE" /mnt/etc/localtime

lk_tty_print "Setting locales"
_LK_PROVISION_ROOT=/mnt
lk_configure_locales
lk_tty_run_detail -1 in_target locale-gen

lk_tty_print "Configuring sudo"
FILE=/mnt/etc/sudoers.d/${LK_PATH_PREFIX}default
install -m 00440 /dev/null "$FILE"
lk_file_replace -f "$_DIR/default" "$FILE"

lk_tty_print "Creating administrator account:" "$BOOTSTRAP_USERNAME"
FILE=/mnt/etc/skel/.ssh/authorized_keys
lk_tty_run_detail install -d -m 00700 "${FILE%/*}"
lk_tty_run_detail install -m 00600 /dev/null "$FILE"
lk_tty_run_detail -1 in_target useradd \
    --groups adm,wheel \
    --create-home \
    --shell /bin/bash \
    --key UMASK=026 \
    "$BOOTSTRAP_USERNAME"
[ -z "$BOOTSTRAP_PASSWORD" ] ||
    printf '%s\n' "$BOOTSTRAP_PASSWORD" "$BOOTSTRAP_PASSWORD" |
    in_target passwd "$BOOTSTRAP_USERNAME"
FILE=/mnt/etc/sudoers.d/nopasswd-$BOOTSTRAP_USERNAME
install -m 00440 /dev/null "$FILE"
echo "$BOOTSTRAP_USERNAME ALL=(ALL) NOPASSWD:ALL" >"$FILE"
[ -z "$BOOTSTRAP_KEY" ] ||
    echo "$BOOTSTRAP_KEY" | in_target -u "$BOOTSTRAP_USERNAME" \
        bash -c "cat >~/.ssh/authorized_keys"
[ -z "$BOOTSTRAP_FULL_NAME" ] ||
    in_target chfn -f "$BOOTSTRAP_FULL_NAME" "$BOOTSTRAP_USERNAME"

export _LK_BOOTSTRAP=1

lk_tty_print "Installing lk-platform to" "$LK_BASE"
in_target install -d -m 02775 -o "$BOOTSTRAP_USERNAME" -g adm "$LK_BASE"
(umask 002 &&
    in_target -u "$BOOTSTRAP_USERNAME" \
        git clone -b "$LK_PLATFORM_BRANCH" \
        https://github.com/lkrms/lk-platform.git "$LK_BASE")
in_target install -d -m 02775 -g adm "$LK_BASE"/{etc{,/lk-platform},var}
in_target install -d -m 01777 -g adm "$LK_BASE"/var/log
in_target install -d -m 00750 -g adm "$LK_BASE"/var/backup
FILE=$LK_BASE/etc/lk-platform/lk-platform.conf
in_target install -m 00664 -g adm /dev/null "$FILE"
lk_var_sh \
    LK_BASE \
    LK_PATH_PREFIX \
    LK_NODE_HOSTNAME \
    LK_NODE_FQDN \
    LK_IPV4_ADDRESS \
    LK_IPV4_GATEWAY \
    LK_DNS_SERVERS \
    LK_DNS_SEARCH \
    LK_BRIDGE_INTERFACE \
    LK_WIFI_REGDOM \
    LK_NODE_TIMEZONE \
    LK_NODE_SERVICES \
    LK_NODE_LOCALES \
    LK_NODE_LANGUAGE \
    LK_SAMBA_WORKGROUP \
    LK_GRUB_CMDLINE \
    LK_NTP_SERVER \
    LK_ARCH_MIRROR \
    LK_ARCH_REPOS \
    LK_ARCH_AUR_REPO_NAME \
    LK_PLATFORM_BRANCH \
    LK_PACKAGES_FILE >"/mnt$FILE"

lk_log_tty_on
PROVISIONED=0
in_target -u "$BOOTSTRAP_USERNAME" \
    env BASH_XTRACEFD=$BASH_XTRACEFD SHELLOPTS=xtrace _LK_NO_LOG=1 \
    "$LK_BASE/bin/lk-provision-arch.sh" --yes && PROVISIONED=1 ||
    lk_tty_error "Provisioning failed"
lk_log_tty_off

lk_tty_print "Installing boot loader"
i=0
for PART in ${OTHER_OS_PARTITIONS[@]+"${OTHER_OS_PARTITIONS[@]}"}; do
    DIR=/mnt/mnt/temp$i
    ((i++)) || lk_tty_detail "Mounting other operating systems"
    install -d -m 00755 "$DIR" &&
        mount "$PART" "$DIR" ||
        lk_warn "unable to mount at $DIR: $PART" ||
        true
done
lk_arch_configure_grub
GRUB_INSTALLED=0
i=0
while :; do
    ((++i))
    in_target update-grub --install && GRUB_INSTALLED=1 && break
    lk_tty_error "Boot loader installation failed"
    ! lk_no_input || { [ "$i" -lt 2 ] &&
        { lk_tty_detail "Trying again in 5 seconds" &&
            sleep 5 &&
            continue; } || break; }
    lk_tty_yn "Try again?" Y || break
done
((GRUB_INSTALLED)) ||
    lk_tty_print "To install the boot loader manually:" \
        $'\n'"arch-chroot /mnt update-grub --install"

((PROVISIONED)) ||
    lk_tty_print "To provision the system manually:" \
        $'\n'"$(printf \
            'arch-chroot /mnt runuser -u %q -- %q/bin/lk-provision-arch.sh' \
            "$BOOTSTRAP_USERNAME" \
            "$LK_BASE")"

lk_tty_success "Bootstrap complete"

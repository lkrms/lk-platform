#!/bin/bash
# shellcheck disable=SC2015,SC2034,SC2207

function pacman_group_packages() {
    [ "$EUID" -ne "0" ] ||
        [ "${PACMAN_SYNC:-1}" -ne "1" ] || {
        pacman -Sy >&2 || return
        PACMAN_SYNC=0
    }
    pacman -Sgq "$@"
}

PACMAN_PACKAGES=(
    # bare minimum
    base
    linux
    mkinitcpio

    # boot
    grub
    efibootmgr

    # multi-boot
    os-prober
    ntfs-3g

    # bootstrap.sh dependencies
    sudo
    networkmanager
    openssh
    ntp
    git

    # basics
    bash-completion
    byobu
    curl
    diffutils
    dmidecode
    lftp
    nano
    ncdu
    ndisc6 # for rdisc6
    nmap
    openbsd-netcat
    ps_mem
    rsync
    tcpdump
    traceroute
    vim
    wget

    # == UNNECESSARY ON DISPOSABLE SERVERS
    #
    man-db
    man-pages
    texinfo

    # filesystems
    btrfs-progs
    dosfstools
    exfat-utils
    f2fs-tools
    jfsutils
    reiserfsprogs
    xfsprogs
    nfs-utils

    #
    ${PACMAN_PACKAGES[@]+"${PACMAN_PACKAGES[@]}"}
)

AUR_PACKAGES=(
    #
    ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
)

PACMAN_DESKTOP_PACKAGES=(
    xdg-user-dirs
    lightdm
    lightdm-gtk-greeter
    lightdm-gtk-greeter-settings
    xorg-server
    xorg-xrandr

    #
    cups
    gnome-keyring
    gvfs
    gvfs-smb
    network-manager-applet
    seahorse
    zenity

    #
    $(
        # xfce4-screensaver is buggy and insecure, and it autostarts
        # by default, so exclude it from xfce4-goodies
        pacman_group_packages xfce4 xfce4-goodies |
            grep -Fxv xfce4-screensaver
    )
    catfish
    engrampa
    pavucontrol
    libcanberra
    libcanberra-pulse
    plank

    # xfce4-screensaver replacement
    xsecurelock
    xss-lock

    #
    pulseaudio-alsa

    #
    ${PACMAN_DESKTOP_PACKAGES[@]+"${PACMAN_DESKTOP_PACKAGES[@]}"}
)

AUR_DESKTOP_PACKAGES=(
    mugshot
    xfce4-panel-profiles

    #
    ${AUR_DESKTOP_PACKAGES[@]+"${AUR_DESKTOP_PACKAGES[@]}"}
)

lk_is_virtual && {
    ! lk_is_qemu || {
        PACMAN_PACKAGES+=(qemu-guest-agent)
        PACMAN_DESKTOP_PACKAGES+=(spice-vdagent)
    }
} || {
    # VMs don't need these
    PACMAN_PACKAGES+=(
        linux-firmware
        linux-headers

        #
        hddtemp
        lm_sensors
        powertop
        tlp
        tlp-rdw

        #
        gptfdisk # provides sgdisk
        lvm2     #
        mdadm    # software RAID
        parted

        #
        ethtool
        hdparm
        nvme-cli
        smartmontools
        usb_modeswitch
        usbutils
        wpa_supplicant

        #
        fwupd

        #
        b43-fwcutter
        ipw2100-fw
        ipw2200-fw
    )
    ! grep -Eq '^vendor_id\s*:\s+GenuineIntel$' /proc/cpuinfo ||
        PACMAN_PACKAGES+=(intel-ucode)
    ! grep -Eq '^vendor_id\s*:\s+AuthenticAMD$' /proc/cpuinfo ||
        PACMAN_PACKAGES+=(amd-ucode)
    ! grep -iq 'thinkpad' /sys/devices/virtual/dmi/id/product_family ||
        PACMAN_PACKAGES+=(acpi_call)

    PACMAN_DESKTOP_PACKAGES+=(
        mesa
        libvdpau-va-gl

        #
        blueman
        pulseaudio-bluetooth
    )

    GRAPHICS_CONTROLLERS="$(lspci | grep -E 'VGA|3D')"
    ! grep -qi "Intel" <<<"$GRAPHICS_CONTROLLERS" ||
        PACMAN_DESKTOP_PACKAGES+=(
            intel-media-driver
            libva-intel-driver
        )
    ! grep -qi "NVIDIA" <<<"$GRAPHICS_CONTROLLERS" ||
        PACMAN_DESKTOP_PACKAGES+=(
            nvidia
            nvidia-utils
        )

    AUR_DESKTOP_PACKAGES+=(
        xiccd
    )
}

[ "${PACMAN_DESKTOP_APPS:-1}" -ne "1" ] ||
    PACMAN_DESKTOP_PACKAGES+=(
        # basics
        evince
        galculator
        geany
        gimp
        libreoffice-fresh
        samba

        # browsers
        falkon
        firefox
        lynx

        # will be reinstated when catfish conflict with zeitgeist is removed
        # (see https://bugzilla.xfce.org/show_bug.cgi?id=16419)
        #midori

        # multimedia
        libdvdcss
        libdvdnav
        libvpx
        vlc

        # remote desktop
        x11vnc

        #
        adapta-gtk-theme
        arc-gtk-theme
        arc-icon-theme
        arc-solid-gtk-theme
        breeze-gtk
        breeze-icons

        #
        gtk-engine-murrine
        materia-gtk-theme

        #
        elementary-icon-theme
        elementary-wallpapers
        gtk-theme-elementary
        sound-theme-elementary

        #
        moka-icon-theme
        papirus-icon-theme

        #
        noto-fonts
        noto-fonts-cjk
        noto-fonts-emoji
        noto-fonts-extra
        ttf-dejavu
        ttf-inconsolata
        ttf-jetbrains-mono
        ttf-lato
        ttf-opensans
        ttf-roboto
        ttf-roboto-mono
        ttf-ubuntu-font-family

        #
        archlinux-wallpaper
    )

pacman -Qq "xfce4-session" >/dev/null 2>&1 ||
    lk_confirm "Include Xfce?" ||
    {
        PACMAN_DESKTOP_PACKAGES=()
        AUR_DESKTOP_PACKAGES=()
    }

PACMAN_PACKAGES+=(${PACMAN_DESKTOP_PACKAGES[@]+"${PACMAN_DESKTOP_PACKAGES[@]}"})
AUR_PACKAGES+=(${AUR_DESKTOP_PACKAGES[@]+"${AUR_DESKTOP_PACKAGES[@]}"})
[ "${#AUR_PACKAGES[@]}" -eq "0" ] || {
    PACMAN_PACKAGES+=($(comm -12 <(pacman -Slq | sort | uniq) <(lk_echo_array "${AUR_PACKAGES[@]}" | sort | uniq)))
    AUR_PACKAGES=($(comm -13 <(pacman -Slq | sort | uniq) <(lk_echo_array "${AUR_PACKAGES[@]}" | sort | uniq)))
    [ "${#AUR_PACKAGES[@]}" -eq "0" ] || {
        lk_echo_array "${AUR_PACKAGES[@]}" | lk_console_list "Unable to install from configured repositories:" package packages
        ! lk_confirm "Manage the above using yay?" Y && AUR_PACKAGES=() || {
            PACMAN_PACKAGES+=($(pacman_group_packages base-devel))
            AUR_PACKAGES+=($(pacman -Qq yay 2>/dev/null || true))
        }
    }
}

YAY_SCRIPT="$(
    cat <<EOF
YAY_DIR="\$(mktemp -d)" &&
    git clone "https://aur.archlinux.org/yay.git" "\$YAY_DIR" &&
    cd "\$YAY_DIR" && makepkg --syncdeps --install --noconfirm
EOF
)"

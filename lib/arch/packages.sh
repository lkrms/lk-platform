#!/bin/bash

# shellcheck disable=SC2015,SC2016,SC2034,SC2206,SC2207

IFS=','
PAC_REPOS=(
    ${LK_ARCH_REPOS:-}
    ${PAC_REPOS[@]+"${PAC_REPOS[@]}"}
)
unset IFS

lk_pacman_add_repo "${PAC_REPOS[@]}"

PAC_REJECT=(
    xfce4-screensaver # Buggy and insecure

    #
    ${PAC_REJECT[@]+"${PAC_REJECT[@]}"}
)

PAC_PACKAGES=(
    # Bare minimum
    base
    linux
    mkinitcpio
    grub
    efibootmgr

    # Basics
    bash-completion
    bc
    bind # dig
    byobu
    curl
    diffutils
    dmidecode
    git
    glances
    htop
    inetutils # telnet
    jq
    lftp
    libnewt # whiptail
    logrotate
    lsof
    mediainfo
    nano
    ncdu
    ndisc6 # rdisc6
    networkmanager
    nfs-utils
    nmap
    ntp
    openbsd-netcat
    openssh
    p7zip
    pcp
    ps_mem
    pv
    rsync
    stow
    sudo
    sysstat
    tcpdump
    traceroute
    unzip
    vim
    wget
    whois
    yq

    # Documentation
    man-db
    man-pages
    texinfo

    # Filesystems
    btrfs-progs
    dosfstools
    e2fsprogs
    exfatprogs
    f2fs-tools
    jfsutils
    nilfs-utils
    ntfs-3g
    reiserfsprogs
    udftools
    xfsprogs

    #
    ${PAC_PACKAGES[@]+"${PAC_PACKAGES[@]}"}
)

AUR_PACKAGES=(
    networkmanager-dispatcher-ntpd

    #
    ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
)

PAC_DESKTOP_PACKAGES=(
    xdg-user-dirs
    lightdm
    lightdm-gtk-greeter
    lightdm-gtk-greeter-settings
    xorg-server
    xorg-xinput
    xorg-xrandr

    #
    cups
    gnome-keyring
    gvfs
    gvfs-smb
    libcanberra
    libcanberra-pulse
    network-manager-applet
    pavucontrol
    pulseaudio-alsa
    seahorse
    zenity

    #
    $(lk_pacman_group_packages xfce4 xfce4-goodies |
        grep -Fxv xfce4-screensaver)
    catfish
    engrampa
    plank
    xsecurelock
    xss-lock

    #
    ${PAC_DESKTOP_PACKAGES[@]+"${PAC_DESKTOP_PACKAGES[@]}"}
)

AUR_DESKTOP_PACKAGES=(
    autorandr-git
    mugshot
    xfce4-panel-profiles
    xrandr-invert-colors

    #
    ${AUR_DESKTOP_PACKAGES[@]+"${AUR_DESKTOP_PACKAGES[@]}"}
)

if lk_is_virtual; then
    if lk_is_qemu; then
        PAC_PACKAGES+=(qemu-guest-agent)
        PAC_DESKTOP_PACKAGES+=(spice-vdagent)
    fi
else
    PAC_PACKAGES+=(
        linux-firmware
        linux-headers

        #
        hddtemp
        lm_sensors
        powertop
        tlp
        tlp-rdw

        #
        gptfdisk # sgdisk
        lvm2
        mdadm
        parted

        #
        crda
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
        PAC_PACKAGES+=(intel-ucode)
    ! grep -Eq '^vendor_id\s*:\s+AuthenticAMD$' /proc/cpuinfo ||
        PAC_PACKAGES+=(amd-ucode)
    ! grep -iq 'thinkpad' /sys/devices/virtual/dmi/id/product_family ||
        PAC_PACKAGES+=(acpi_call)

    PAC_DESKTOP_PACKAGES+=(
        os-prober

        #
        mesa
        libvdpau-va-gl

        #
        blueman
        pulseaudio-bluetooth
    )

    GRAPHICS_CONTROLLERS=$(lspci | grep -E 'VGA|3D')
    ! grep -qi "Intel" <<<"$GRAPHICS_CONTROLLERS" ||
        PAC_DESKTOP_PACKAGES+=(
            intel-media-driver
            libva-intel-driver
        )
    ! grep -qi "NVIDIA" <<<"$GRAPHICS_CONTROLLERS" ||
        PAC_DESKTOP_PACKAGES+=(
            nvidia
            nvidia-utils
        )

    AUR_DESKTOP_PACKAGES+=(
        xiccd
    )
fi

PAC_DESKTOP_PACKAGES+=(
    # Basics
    evince
    galculator
    geany
    gimp
    gnome-font-viewer
    libreoffice-fresh
    samba

    # Browsers
    falkon
    firefox
    lynx
    midori

    # Multimedia
    libdvdcss
    libdvdnav
    libvpx
    vlc

    # Remote desktop
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
    terminus-font
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

pacman -Qq xfce4-session >/dev/null 2>&1 ||
    lk_confirm "Include Xfce?" ||
    {
        PAC_DESKTOP_PACKAGES=()
        AUR_DESKTOP_PACKAGES=()
    }

PAC_PACKAGES+=(${PAC_DESKTOP_PACKAGES[@]+"${PAC_DESKTOP_PACKAGES[@]}"})
AUR_PACKAGES+=(${AUR_DESKTOP_PACKAGES[@]+"${AUR_DESKTOP_PACKAGES[@]}"})
[ ${#AUR_PACKAGES[@]} -eq 0 ] || {
    NOT_AUR=($(comm -12 \
        <(pacman -Slq core extra community | sort -u) \
        <(lk_echo_array AUR_PACKAGES | sort -u)))
    [ ${#NOT_AUR[@]} -eq 0 ] ||
        lk_console_warning "Moved from AUR to repo:" $'\n'"$(lk_echo_array NOT_AUR)"
}
CUSTOM_REPO_PACKAGES=($(comm -13 \
    <(pacman -Slq core extra community | sort -u) \
    <(pacman -Slq | sort -u)))
for SUFFIX in -lk -git ""; do
    CUSTOM_PACKAGES=($(comm -12 \
        <(lk_echo_array CUSTOM_REPO_PACKAGES | sort -u) \
        <(lk_echo_array AUR_PACKAGES ${SUFFIX:+PAC_PACKAGES} |
            sed "s/\$/$SUFFIX/" | sort -u)))
    [ ${#CUSTOM_PACKAGES[@]} -eq 0 ] || {
        AUR_PACKAGES=($(comm -13 \
            <(lk_echo_array CUSTOM_PACKAGES | sed "s/$SUFFIX\$//" | sort -u) \
            <(lk_echo_array AUR_PACKAGES | sort -u)))
        [ -z "$SUFFIX" ] || {
            PAC_PACKAGES=($(comm -13 \
                <(lk_echo_array CUSTOM_PACKAGES | sed "s/$SUFFIX\$//" | sort -u) \
                <(lk_echo_array PAC_PACKAGES | sort -u)))
        }
        PAC_PACKAGES+=("${CUSTOM_PACKAGES[@]}")
    }
done
[ ${#AUR_PACKAGES[@]} -eq 0 ] || {
    lk_echo_array AUR_PACKAGES | lk_console_list "Unable to install from configured repositories:" package packages
    ! lk_confirm "Manage the above using yay?" Y && AUR_PACKAGES=() || {
        PAC_PACKAGES+=($(lk_pacman_group_packages base-devel))
        AUR_PACKAGES+=($(pacman -Qq yay 2>/dev/null || true))
    }
}

YAY_SCRIPT="$(
    cat <<EOF
YAY_DIR="\$(mktemp -d)" &&
    git clone "https://aur.archlinux.org/yay.git" "\$YAY_DIR" &&
    cd "\$YAY_DIR" && script -qfc "makepkg --syncdeps --install --noconfirm" /dev/null
EOF
)"

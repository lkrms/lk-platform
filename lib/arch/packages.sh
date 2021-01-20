#!/bin/bash

# shellcheck disable=SC2015,SC2016,SC2034,SC2206,SC2207

# References:
# - https://wiki.archlinux.org/index.php/Installation_guide
# - https://gitlab.archlinux.org/archlinux/archiso/-/raw/master/configs/releng/packages.x86_64

IFS=','
PAC_REPOS=(
    ${LK_ARCH_REPOS:-}
    ${PAC_REPOS[@]+"${PAC_REPOS[@]}"}
)
unset IFS

PAC_PACKAGES=(
    #### Bare necessities
    #
    base
    linux
    mkinitcpio
    grub
    efibootmgr

    #### lk-platform requirements
    #
    sudo
    networkmanager
    git
    openssh

    ### Services
    #
    logrotate
    ntp

    ### Utilities
    #
    bc
    diffutils
    file
    mediainfo
    pv
    rsync

    # Shell
    bash-completion
    byobu
    libnewt # whiptail

    # Documentation
    man-db
    man-pages
    texinfo

    # Editors
    nano
    vim

    # System
    dmidecode
    glances
    ncdu
    htop
    lsof
    pcp
    ps_mem
    sysstat

    # Network
    bind # dig
    curl
    inetutils # hostname, telnet
    lftp
    lynx
    ndisc6 # rdisc6 (IPv6 router discovery)
    nfs-utils
    nmap
    openbsd-netcat
    samba
    tcpdump
    traceroute
    wget
    whois

    # 7z/zip
    p7zip
    unzip

    # json/yml/xml
    jq
    yq

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

PAC_REJECT=(
    #
    ${PAC_REJECT[@]+"${PAC_REJECT[@]}"}
)

PAC_KEEP=(
    #
    ${PAC_KEEP[@]+"${PAC_KEEP[@]}"}
)

AUR_PACKAGES=(
    #
    ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
)

if lk_node_service_enabled desktop; then
    PAC_PACKAGES+=(
        xf86-video-vesa
        xorg-apps
        xorg-fonts
        xorg-fonts-75dpi
        xorg-fonts-100dpi
        xorg-server
        xorg-server-xvfb

        #
        lightdm
        lightdm-gtk-greeter
        lightdm-gtk-greeter-settings

        #
        cups
        gnome-keyring
        gvfs
        gvfs-afc # Apple devices
        gvfs-mtp # Other devices
        gvfs-nfs
        gvfs-smb
        network-manager-applet
        seahorse
        x11vnc
        xdg-user-dirs # Manage ~/Desktop, ~/Templates, etc.
        zenity

        #
        adapta-gtk-theme
        arc-gtk-theme
        arc-icon-theme
        arc-solid-gtk-theme
        breeze-gtk
        breeze-icons
        elementary-icon-theme
        elementary-wallpapers
        gtk-engine-murrine # GTK 2 support
        gtk-theme-elementary
        materia-gtk-theme
        moka-icon-theme
        papirus-icon-theme
        sound-theme-elementary

        #
        galculator
        geany
        pinta
        vlc

        #
        gst-plugins-good
        libdvdcss

        #
        chromium
        epiphany
        firefox

        #
        evince
        libreoffice-fresh

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
    )

    AUR_PACKAGES+=(
        autorandr-git
        networkmanager-dispatcher-ntpd
        xrandr-invert-colors
    )
fi

if lk_node_service_enabled xfce4; then
    PAC_PACKAGES+=(
        xfce4
        xfce4-goodies

        #
        catfish
        engrampa
        libcanberra
        libcanberra-pulse
        pavucontrol
        plank
        pulseaudio-alsa
        xsecurelock
        xss-lock
    )
    PAC_REJECT+=(
        xfce4-screensaver # Buggy and insecure
    )
    AUR_PACKAGES+=(
        mugshot
        xfce4-panel-profiles
    )
fi

if lk_is_virtual; then
    if lk_is_qemu; then
        PAC_PACKAGES+=(
            qemu-guest-agent
        )
        if lk_node_service_enabled desktop; then
            PAC_PACKAGES+=(
                spice-vdagent
            )
        fi
    fi
else
    PAC_PACKAGES+=(
        linux-firmware

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

        #
        fwupd
    )

    if lk_node_service_enabled desktop; then
        PAC_PACKAGES+=(
            os-prober
            mesa
            libvdpau-va-gl
        )
    fi

    if lk_node_service_enabled xfce4; then
        PAC_PACKAGES+=(
            blueman
            pulseaudio-bluetooth
        )
        AUR_PACKAGES+=(
            xiccd
        )
    fi

    grep -Eq "^vendor_id[[:blank:]:]+GenuineIntel$" /proc/cpuinfo &&
        PAC_PACKAGES+=(intel-ucode) ||
        ! grep -Eq "^vendor_id[[:blank:]:]+AuthenticAMD$" /proc/cpuinfo ||
        PAC_PACKAGES+=(amd-ucode)
    ! grep -iq "^ThinkPad" /sys/class/dmi/id/product_family ||
        PAC_PACKAGES+=(tpacpi-bat)
    ! lk_system_has_intel_graphics ||
        PAC_PACKAGES+=(intel-media-driver libva-intel-driver)
    ! lk_system_has_nvidia_graphics ||
        PAC_PACKAGES+=(nvidia nvidia-utils)
fi

####
#

PAC_REJECT=($(lk_echo_array PAC_REJECT | sort -u))
PAC_REJECT_REGEX=$(lk_regex_implode ${PAC_REJECT[@]+"${PAC_REJECT[@]}"})

IFS=$'\n'
PAC_REPOS=($(lk_echo_array PAC_REPOS | sort -u))
unset IFS
[ ${#PAC_REPOS[@]} -eq 0 ] ||
    lk_arch_add_repo "${PAC_REPOS[@]}"

lk_pac_sync

# If any AUR_PACKAGES now appear in core, extra, community or multilib, move
# them to PAC_PACKAGES and notify the user
if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
    AUR_MOVED=$(lk_pac_available_list -o "${AUR_PACKAGES[@]}")
    [ -z "$AUR_MOVED" ] || {
        lk_console_warning "Moved from AUR to repo:" "$AUR_MOVED"
        PAC_PACKAGES+=($AUR_MOVED)
        AUR_PACKAGES=($(lk_pac_unavailable_list -o "${AUR_PACKAGES[@]}"))
    }
fi

PAC_GROUPS=($(comm -12 \
    <(lk_echo_array PAC_PACKAGES | sort -u) \
    <(lk_pac_groups | sort -u)))
if [ ${#PAC_GROUPS[@]} -gt 0 ]; then
    lk_console_message "Resolving package groups"
    PAC_PACKAGES=($(comm -13 \
        <(lk_echo_array PAC_GROUPS | sort -u) \
        <(lk_echo_array PAC_PACKAGES | sort -u)))
    for PAC_GROUP in "${PAC_GROUPS[@]}"; do
        GROUP_PACKAGES=($(lk_pac_groups "$PAC_GROUP"))
        PAC_PACKAGES+=(${GROUP_PACKAGES[@]+"${GROUP_PACKAGES[@]}"})
        ! lk_verbose || lk_console_detail \
            "$PAC_GROUP:" "${#GROUP_PACKAGES[@]} $(lk_maybe_plural \
                ${#GROUP_PACKAGES[@]} package packages)"
    done
fi

if [ -n "$PAC_REJECT_REGEX" ]; then
    PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES | sed "/^${PAC_REJECT_REGEX}\$/d"))
    AUR_PACKAGES=($(lk_echo_array AUR_PACKAGES | sed "/^${PAC_REJECT_REGEX}\$/d"))
fi

# For any packages in custom repos named as follows, replace PACKAGE in
# PAC_PACKAGES and AUR_PACKAGES:
# - ${PREFIX}PACKAGE
# - ${PREFIX}PACKAGE-git
# - PACKAGE-${PREFIX%-}
# - PACKAGE-git
# - PACKAGE-git-${PREFIX%-}
PAC_AVAILABLE=($(lk_pac_available_list))
PAC_UNOFFICIAL=($(comm -13 \
    <(lk_pac_available_list -o | sort -u) \
    <(lk_echo_array PAC_AVAILABLE | sort -u)))
PAC_REPLACE=$(lk_echo_array PAC_UNOFFICIAL | awk \
    -v "p=^$LK_PATH_PREFIX" \
    -v "s=-${LK_PATH_PREFIX%-}\$" \
    'BEGIN {
    a[1] = s; a[2] = p; a[3] = "-git$"
}
$0 ~ s || $0 ~ p || /-git$/ {
    l = $0
    for (i in a)
        if (sub(a[i], "", l)) print l, $0
}')
if [ -n "$PAC_REPLACE" ]; then
    SED_COMMAND=(sed -E)
    while read -r PACKAGE NEW_PACKAGE; do
        SED_COMMAND+=(-e "s/^$(lk_escape_ere \
            "$PACKAGE")\$/$(lk_escape_ere_replace "$NEW_PACKAGE")/")
    done <<<"$PAC_REPLACE"
    PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES | "${SED_COMMAND[@]}"))
    AUR_PACKAGES=($(lk_echo_array AUR_PACKAGES | "${SED_COMMAND[@]}"))
fi

# Move any AUR_PACKAGES that can be installed from a repo to PAC_PACKAGES
if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
    PAC_PACKAGES+=($(lk_pac_available_list "${AUR_PACKAGES[@]}"))
    AUR_PACKAGES=($(lk_pac_unavailable_list "${AUR_PACKAGES[@]}"))
    [ ${#AUR_PACKAGES[@]} -eq 0 ] ||
        PAC_PACKAGES+=($(lk_pac_groups base-devel))
fi

# Reduce PAC_KEEP to installed packages not present in PAC_PACKAGES
if [ ${#PAC_KEEP[@]} -gt 0 ]; then
    PAC_KEEP=($(comm -23 \
        <(lk_echo_array PAC_KEEP | sort -u) \
        <(lk_echo_array PAC_PACKAGES | sort -u)))
    if [ ${#PAC_KEEP[@]} -gt 0 ]; then
        PAC_KEEP=($(comm -12 \
            <(lk_echo_array PAC_KEEP | sort -u) \
            <(lk_pac_installed_list | sort -u)))
    fi
fi

# If any AUR_PACKAGES remain, lk_pac_unavailable_list has already sorted them
PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES | sort -u))

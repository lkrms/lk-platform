#!/bin/bash

# References:
# - https://wiki.archlinux.org/index.php/Installation_guide
# - https://gitlab.archlinux.org/archlinux/archiso/-/raw/master/configs/releng/packages.x86_64

IFS=,
PAC_REPOS=(
    ${LK_ARCH_REPOS-}
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
    perl

    ### Services
    #
    atop
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
    time
    trash-cli
    unison

    # Shell
    bash-completion
    byobu
    libnewt # whiptail
    shfmt

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
    htop
    hwinfo
    iotop
    lsof
    ncdu
    pcp
    ps_mem
    s-tui
    sysfsutils
    sysstat

    # Network
    bind # dig
    conntrack-tools
    curl
    inetutils # hostname, telnet
    iptables-nft
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

    # Network monitoring
    iftop   # traffic by service and host
    nethogs # traffic by process ('nettop')
    nload   # traffic by interface

    # 7z/zip/wimextract
    p7zip
    unzip
    wimlib

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
    # System
    rdfind

    # Utilities
    icdiff

    #
    ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
)

if lk_node_service_enabled lighttpd; then
    PAC_PACKAGES+=(lighttpd)
fi

if lk_node_service_enabled squid; then
    PAC_PACKAGES+=(squid)
fi

if lk_node_service_enabled libvirt; then
    PAC_PACKAGES+=(
        libvirt
        qemu
        dnsmasq
        edk2-ovmf
        libguestfs
        cpio
        virt-install
    )
fi

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

    if lk_echo_array PAC_PACKAGES AUR_PACKAGES | grep -E \
        '(^ttf-joypixels$|^ttf-.*\<(tw)?emoji\>|\<fonts-emoji\>)' \
        >/dev/null; then
        PAC_REJECT+=(noto-fonts-emoji)
    else
        PAC_PACKAGES+=(noto-fonts-emoji)
    fi

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
        pavucontrol
        plank
        pulseaudio-alsa # Alternative: pipewire-alsa
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
        cpupower
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
        udisks2
    )

    AUR_PACKAGES+=(
        powercap
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
            bluez
            blueman
            pulseaudio-bluetooth # Alternative: pipewire-pulse
        )
    fi

    if grep -Eq '\<GenuineIntel\>' /proc/cpuinfo; then
        PAC_PACKAGES+=(intel-ucode)
    elif grep -Eq '\<AuthenticAMD\>' /proc/cpuinfo; then
        PAC_PACKAGES+=(amd-ucode)
        ! grep -Eq '\<Ryzen\>' /proc/cpuinfo ||
            AUR_PACKAGES+=(ryzenadj-git)
    fi
    ! grep -iq "^ThinkPad" /sys/class/dmi/id/product_family ||
        PAC_PACKAGES+=(tpacpi-bat)
    ! lk_system_has_intel_graphics ||
        PAC_PACKAGES+=(intel-media-driver libva-intel-driver)
    ! lk_system_has_nvidia_graphics ||
        PAC_PACKAGES+=(nvidia nvidia-utils)
    ! lk_system_has_amd_graphics ||
        PAC_PACKAGES+=(xf86-video-amdgpu libva-mesa-driver mesa-vdpau)
fi

####

PAC_REJECT_REGEX=$(lk_echo_array PAC_REJECT | sort -u | lk_implode_input "|")
PAC_REJECT_REGEX=${PAC_REJECT_REGEX:+"($PAC_REJECT_REGEX)"}

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
        lk_console_warning "Moved from AUR to official repos:" "$AUR_MOVED"
        PAC_PACKAGES+=($AUR_MOVED)
        AUR_PACKAGES=($(lk_pac_unavailable_list -o "${AUR_PACKAGES[@]}"))
    }
fi

PAC_GROUPS=($(comm -12 \
    <(lk_echo_array PAC_PACKAGES | sort -u) \
    <(lk_pac_groups | sort -u)))
if [ ${#PAC_GROUPS[@]} -gt 0 ]; then
    PAC_PACKAGES=($(comm -13 \
        <(lk_echo_array PAC_GROUPS) \
        <(lk_echo_array PAC_PACKAGES | sort -u)))
    PAC_PACKAGES+=($(comm -12 \
        <(lk_pac_groups "${PAC_GROUPS[@]}" | sort -u) \
        <(lk_pac_available_list -o | sort -u)))
fi

# Check for PAC_PACKAGES removed from official repos
PAC_MOVED=$(lk_pac_unavailable_list -o "${PAC_PACKAGES[@]}")
[ -z "$PAC_MOVED" ] || {
    lk_console_warning "Removed from official repos:" "$PAC_MOVED"
    AUR_PACKAGES+=($PAC_MOVED)
    PAC_PACKAGES=($(lk_pac_available_list -o "${PAC_PACKAGES[@]}"))
}

if [ -n "$PAC_REJECT_REGEX" ]; then
    PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES |
        sed -E "/^${PAC_REJECT_REGEX}\$/d"))
    AUR_PACKAGES=($(lk_echo_array AUR_PACKAGES |
        sed -E "/^${PAC_REJECT_REGEX}\$/d"))
fi

# Use unofficial packages named PACKAGE-git, PACKAGE-lk or PACKAGE-git-lk
# instead of PACKAGE
lk_mktemp_with PAC_UNOFFICIAL comm -13 \
    <(lk_pac_available_list -o | sort -u) \
    <(lk_pac_available_list | sort -u)
lk_mktemp_with PAC_REPLACE awk -v "suffix=-${LK_PATH_PREFIX%-}\$" '
function save() {
    if (_prio[pkg] < prio) {
        _replace[pkg] = $0
        _prio[pkg] = prio
    }
}
$0 ~ suffix || /-git$/ {
    pkg = $0
    prio = 0
    # -lk beats -git, -git-lk beats -lk and -git
    if (sub(suffix, "", pkg)) {
        prio += 2
        save()
    }
    if (sub(/-git$/, "", pkg)) {
        prio += 1
        save()
    }
}
END {
    for (pkg in _replace) {
        print pkg, _replace[pkg]
    }
}' "$PAC_UNOFFICIAL"
if [ -s "$PAC_REPLACE" ]; then
    SED_SCRIPT=
    while read -r PACKAGE NEW_PACKAGE; do
        PACKAGE=$(lk_escape_ere "$PACKAGE")
        NEW_PACKAGE=$(lk_escape_ere_replace "$NEW_PACKAGE")
        SED_SCRIPT+="${SED_SCRIPT:+;}s/^$PACKAGE\$/$NEW_PACKAGE/"
    done <"$PAC_REPLACE"
    PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES | sed -E "$SED_SCRIPT"))
    AUR_PACKAGES=($(lk_echo_array AUR_PACKAGES | sed -E "$SED_SCRIPT"))
fi

# Move any AUR_PACKAGES that can be installed from a repo to PAC_PACKAGES
if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
    PAC_PACKAGES+=($(lk_pac_available_list "${AUR_PACKAGES[@]}"))
    AUR_PACKAGES=($(lk_pac_unavailable_list "${AUR_PACKAGES[@]}"))
fi

if [ ${#AUR_PACKAGES[@]} -gt 0 ] ||
    { pacman-conf --repo=aur |
        awk -F"$S*=$S*" '$1=="Server"{print$2}' |
        grep -E '^file://'; } &>/dev/null; then
    PAC_BASE_DEVEL=($(lk_pac_groups base-devel))
    PAC_PACKAGES+=("${PAC_BASE_DEVEL[@]}" devtools pacutils vifm)
    PAC_KEEP+=(aurutils aurutils-git)
fi

# Reduce PAC_KEEP to packages not present in PAC_PACKAGES
if [ ${#PAC_KEEP[@]} -gt 0 ]; then
    PAC_KEEP=($(comm -23 \
        <(lk_echo_array PAC_KEEP | sort -u) \
        <(lk_echo_array PAC_PACKAGES | sort -u)))
fi

# If any AUR_PACKAGES remain, lk_pac_unavailable_list has already sorted them
PAC_PACKAGES=($(lk_echo_array PAC_PACKAGES | sort -u))

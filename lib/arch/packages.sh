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
    kernel-modules-hook

    #### Bootstrap requirements
    #
    sudo
    networkmanager
    git
    openssh
    perl

    ### Essential services
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

    # Shell
    bash-completion
    byobu
    libnewt # Provides whiptail
    zsh

    # Documentation
    man-db
    man-pages
    texinfo

    # Editors
    nano
    vim

    # System
    dmidecode
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
    bind # Provides dig
    conntrack-tools
    curl
    inetutils # Provides hostname, telnet
    iptables-nft
    lftp
    lynx
    ndisc6 # Provides rdisc6
    nfs-utils
    nmap
    openbsd-netcat
    tcpdump
    traceroute
    wget
    whois
    wol

    # Network monitoring
    iftop   # Reports on traffic by service and host
    nethogs # Reports on traffic by process ('nettop')
    nload   # Reports on traffic by interface

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

PAC_NO_REPLACE=(
    #
    ${PAC_NO_REPLACE[@]+"${PAC_NO_REPLACE[@]}"}
)

AUR_PACKAGES=(
    # System
    rdfind

    # Utilities
    icdiff
    jc

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
        edk2-ovmf # UEFI firmware
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
        autorandr
        cups
        gnome-keyring
        gvfs
        gvfs-afc # Apple devices
        gvfs-mtp # Others
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
        #arc-icon-theme
        arc-solid-gtk-theme
        #breeze-gtk
        #breeze-icons
        #elementary-icon-theme
        #elementary-wallpapers
        gtk-engine-murrine # GTK 2 support
        #gtk-theme-elementary
        papirus-icon-theme
        #sound-theme-elementary

        #
        galculator
        geany
        pinta
        vlc

        #
        gst-plugins-good
        libdvdcss

        #
        epiphany

        #
        evince

        #
        inter-font
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

    if lk_arr PAC_PACKAGES AUR_PACKAGES | grep -E \
        '(^ttf-joypixels$|^ttf-.*\<(tw)?emoji\>|\<fonts-emoji\>)' \
        >/dev/null; then
        PAC_REJECT+=(noto-fonts-emoji)
    else
        PAC_PACKAGES+=(noto-fonts-emoji)
    fi

    AUR_PACKAGES+=(
        networkmanager-dispatcher-ntpd
        xrandr-invert-colors

        #
        #numix-gtk-theme-git
        #sound-theme-smooth
        wiki-loves-earth-wallpapers
        wiki-loves-monuments-wallpapers
        #zuki-themes
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
        xfce4-screensaver
    )
    AUR_PACKAGES+=(
        mugshot
        xfce4-panel-profiles

        #
        #elementary-xfce-icons
        #xfce-theme-greybird
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
        gptfdisk # Provides sgdisk
        lvm2
        mdadm
        parted

        #
        ethtool
        hdparm
        nvme-cli
        smartmontools
        wireless-regdb

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
        PAC_PACKAGES+=(amd-ucode linux-headers)
        AUR_PACKAGES+=(zenpower-dkms)
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

SUFFIX=-${LK_PATH_PREFIX%-}

if [ ${#PAC_REPOS[@]} -gt 0 ]; then
    PAC_REPOS=($(lk_arr PAC_REPOS | sort -u))
    lk_arch_add_repo "${PAC_REPOS[@]}"
fi

lk_pac_sync

# To minimise expensive pacman calls, create lists and filter with grep/awk/sed
lk_mktemp_with _PAC_ALL pacman -Sl
lk_mktemp_with _PAC_ALL_GROUPS pacman -Sgg
lk_mktemp_with _PAC_PACKAGES sort -u <(awk '{ print $2 }' "$_PAC_ALL")
lk_mktemp_with _PAC_GROUPS sort -u <(awk '{ print $1 }' "$_PAC_ALL_GROUPS")
lk_mktemp_with _PAC_OFFICIAL sort -u \
    <(awk '$1 ~ /^(core|extra|community|multilib)$/ { print $2 }' "$_PAC_ALL")
lk_mktemp_with _PAC_UNOFFICIAL sort -u \
    <(awk '$1 !~ /^(core|extra|community|multilib)$/ { print $2 }' "$_PAC_ALL")

# If any AUR_PACKAGES now appear in core, extra, community or multilib, move
# them to PAC_PACKAGES and notify the user
if AUR_MOVED=$(grep -Fxf <(lk_arr AUR_PACKAGES) "$_PAC_OFFICIAL"); then
    lk_tty_warning "Moved from AUR to official repos:" "$AUR_MOVED"
    PAC_PACKAGES+=($AUR_MOVED)
fi

# Check for PAC_PACKAGES removed from official repos
if PAC_MOVED=$(lk_arr PAC_PACKAGES |
    grep -Fxvf "$_PAC_OFFICIAL" -f "$_PAC_GROUPS"); then
    lk_tty_warning "Removed from official repos:" "$PAC_MOVED"
    AUR_PACKAGES+=($PAC_MOVED)
fi

# If PAC_PACKAGES contains group names, replace them with their packages
if PAC_GROUPS=$(lk_arr PAC_PACKAGES | grep -Fxf "$_PAC_GROUPS"); then
    PAC_PACKAGES=($({
        lk_arr PAC_PACKAGES | grep -Fxvf "$_PAC_GROUPS" || true
        awk -v "re=$(lk_ere_implode_input <<<"$PAC_GROUPS")" \
            '$1 ~ "^" re "$" { print $2 }' "$_PAC_ALL_GROUPS"
    } | sort -u))
fi

if [ -n "${PAC_REJECT+1}" ]; then
    REJECT=(
        "${PAC_REJECT[@]}"
        "${PAC_REJECT[@]/%/-git}"
        "${PAC_REJECT[@]/%/-git$SUFFIX}"
        "${PAC_REJECT[@]/%/$SUFFIX}"
    )
    PAC_PACKAGES=($(lk_arr PAC_PACKAGES | grep -Fxvf <(lk_arr REJECT) || true))
    AUR_PACKAGES=($(lk_arr AUR_PACKAGES | grep -Fxvf <(lk_arr REJECT) || true))
fi

# Use unofficial packages named PACKAGE-git, PACKAGE-lk or PACKAGE-git-lk
# instead of PACKAGE, unless PACKAGE appears in PAC_NO_REPLACE
lk_mktemp_with PAC_REPLACE awk \
    -v "suffix=$SUFFIX\$" \
    -v "no_replace=$(lk_ere_implode_arr PAC_NO_REPLACE)" '
function save(_p) {
    if (_prio[pkg] < prio) {
        if (_replace[pkg]) {
            _replace[_replace[pkg]] = $0
        }
        _replace[pkg] = $0
        _prio[pkg] = prio
    } else {
        _replace[$0] = _replace[pkg]
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
        if (!no_replace || pkg !~ no_replace) {
            print pkg, _replace[pkg]
        }
    }
}' "$_PAC_UNOFFICIAL"
if [ -s "$PAC_REPLACE" ]; then
    lk_mktemp_with SED \
        awk -v "suffix=$SUFFIX" \
        '{print "s/^" $1 "(-git)?(" suffix ")?$/" $2 "/"}' "$PAC_REPLACE"
    PAC_REJECT+=($(lk_arr PAC_PACKAGES AUR_PACKAGES |
        grep -Fxf <(awk '{print $1}' "$PAC_REPLACE")))
    PAC_PACKAGES=($(lk_arr PAC_PACKAGES | sed -Ef "$SED" | sort -u))
    AUR_PACKAGES=($(lk_arr AUR_PACKAGES | sed -Ef "$SED" | sort -u))
fi

# Move any AUR_PACKAGES that can be installed from a repo to PAC_PACKAGES, and
# vice-versa
ALL_PACKAGES=(
    ${PAC_PACKAGES+"${PAC_PACKAGES[@]}"}
    ${AUR_PACKAGES+"${AUR_PACKAGES[@]}"}
)
PAC_PACKAGES=($(lk_arr ALL_PACKAGES | grep -Fxf "$_PAC_PACKAGES" || true))
AUR_PACKAGES=($(lk_arr ALL_PACKAGES | grep -Fxvf "$_PAC_PACKAGES" || true))

if [ ${#AUR_PACKAGES[@]} -gt 0 ] ||
    [ -n "${LK_ARCH_AUR_REPO_NAME-}" ] ||
    { pacman-conf --repo="${LK_ARCH_AUR_REPO_NAME:-aur}" |
        awk -F"$S*=$S*" '$1=="Server"{print$2}' |
        grep -E '^file://'; } &>/dev/null; then
    PAC_BASE_DEVEL=($(lk_pac_groups base-devel))
    PAC_PACKAGES+=("${PAC_BASE_DEVEL[@]}" devtools pacutils vifm)
    PAC_KEEP+=(aurutils aurutils-git aurutils{,-git}"$SUFFIX")
fi

# Reduce PAC_KEEP to packages not present in PAC_PACKAGES
if [ ${#PAC_KEEP[@]} -gt 0 ]; then
    PAC_KEEP=($(lk_arr PAC_KEEP | grep -Fxvf <(lk_arr PAC_PACKAGES) || true))
fi

PAC_PACKAGES=($(lk_arr PAC_PACKAGES | sort -u))
AUR_PACKAGES=($(lk_arr AUR_PACKAGES | sort -u))

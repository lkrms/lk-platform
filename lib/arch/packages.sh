#!/bin/bash

# References:
# - https://wiki.archlinux.org/index.php/Installation_guide
# - https://gitlab.archlinux.org/archlinux/archiso/-/raw/master/configs/releng/packages.x86_64

IFS=,
PAC_REPOS=(
    ${LK_ARCH_REPOS-}
    ${PAC_REPOS+"${PAC_REPOS[@]}"}
)
unset IFS

PAC_PACKAGES=(${PAC_PACKAGES+"${PAC_PACKAGES[@]}"})
PAC_REJECT=(${PAC_REJECT+"${PAC_REJECT[@]}"})
PAC_KEEP=(${PAC_KEEP+"${PAC_KEEP[@]}"})
PAC_NO_REPLACE=(${PAC_NO_REPLACE+"${PAC_NO_REPLACE[@]}"})
AUR_PACKAGES=(${AUR_PACKAGES+"${AUR_PACKAGES[@]}"})

# - `:BM` = bare metal, i.e. only installed on physical hardware
PAC_PACKAGES+=(
    # Essentials
    base                 # Includes coreutils, findutils, glibc, procps-ng, psmisc, util-linux, ...
    linux                #
    linux-firmware:BM    #
    mkinitcpio           # Specify preferred initramfs package explicitly
    kernel-modules-hook- # Keep the running kernel's modules installed after the kernel package is upgraded
    grub
    efibootmgr

    # Services
    networkmanager
    ntp
    logrotate

    # Utilities
    bc
    curl
    diffutils
    file
    git
    inetutils # Provides hostname, telnet
    jc
    jq
    lftp
    lynx
    mediainfo
    ncdu-
    openbsd-netcat
    openssh #
    p7zip   # Provides 7z
    perl
    pv
    rsync
    sudo
    time
    trash-cli #
    unzip     # Provides zip
    wget      #
    wimlib    # Provides wimextract
    yq

    # Shell
    bash-completion
    byobu-
    fzf
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
    acpi-        # Show battery status
    cpupower-:BM # Show and set processor frequency- and power-related values
    dmidecode    #
    ethtool:BM
    fwupd:BM
    hddtemp:BM
    hdparm:BM
    hwinfo-       # openSUSE's hardware information tool
    lm_sensors:BM #
    msr-tools     # Access processor MSRs ("Model Specific Registers") like BD PROCHOT
    nvme-cli:BM
    powertop:BM
    smartmontools:BM #
    sysfsutils       # e.g. to list options set for a loaded kernel module: `systool -v -m iwlwifi`
    tlp:BM
    tlp-rdw:BM
    udisks2:BM # Allow fwupd to perform UEFI firmware upgrades
    usbutils
    wireless-regdb:BM

    # Monitoring
    atop-
    htop-
    iotop
    lsof
    ps_mem-
    s-tui    # Monitor CPU frequency and temperature while toggling between stressed and regular operation
    sysstat- # Provides iostat, pidstat, sar

    # Networking
    bind             # Provides dig
    conntrack-tools- #
    ipset-           # Used in conjunction with iptables by fail2ban
    iptables-nft     #
    ndisc6-          # Provides rdisc6
    nmap-
    tcpdump
    traceroute
    whois
    wol-

    # Network monitoring
    iftop-  # Monitor traffic by service and host
    nethogs # Monitor traffic by process (similar to nettop on macOS)
    nload-  # Monitor traffic by interface

    # Partitions
    gptfdisk:BM # Provides sgdisk
    lvm2-:BM
    mdadm-:BM
    parted:BM

    # Filesystems
    btrfs-progs-
    dosfstools
    e2fsprogs
    exfatprogs
    f2fs-tools-
    jfsutils-
    nilfs-utils-
    ntfs-3g
    reiserfsprogs-
    udftools-
    xfsprogs-

    # Network filesystems
    nfs-utils-
)

! lk_system_has_intel_cpu || PAC_PACKAGES+=(
    intel-ucode:BM
)

! lk_system_has_amd_cpu || PAC_PACKAGES+=(
    amd-ucode:BM
)

AUR_PACKAGES+=(
    # Utilities
    icdiff-
    rdfind-

    # System
    powercap-:BM
)

! lk_node_service_enabled lighttpd || PAC_PACKAGES+=(
    lighttpd
)

! lk_node_service_enabled squid || PAC_PACKAGES+=(
    squid
)

! lk_node_service_enabled docker || PAC_PACKAGES+=(
    docker
)

! lk_node_service_enabled libvirt || PAC_PACKAGES+=(
    libvirt
    qemu-desktop
    dnsmasq
    edk2-ovmf # UEFI firmware
    libguestfs
    cpio
    virt-install
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

        lightdm
        lightdm-gtk-greeter
        lightdm-gtk-greeter-settings

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

        adapta-gtk-theme
        arc-gtk-theme
        #arc-icon-theme
        arc-solid-gtk-theme
        #breeze-gtk
        #breeze-icons
        capitaine-cursors
        #elementary-icon-theme
        #elementary-wallpapers
        #gtk-theme-elementary
        papirus-icon-theme
        #sound-theme-elementary

        # GTK 2 support
        gtk-engine-murrine
        gtk-engines

        galculator
        geany
        pinta
        vlc

        gst-libav
        gst-plugins-good
        libdvdcss

        epiphany

        evince

        # adobe-source-* packages have been replaced with aur/ttf-adobe-source-*
        # because adobe-source-sans-fonts OTFs have rendering issues below ~12px
        inter-font
        noto-fonts
        noto-fonts-cjk
        terminus-font
        ttf-dejavu
        ttf-fantasque-sans-mono
        ttf-inconsolata
        ttf-jetbrains-mono
        ttf-lato
        ttf-opensans
        ttf-roboto
        ttf-roboto-mono
        ttf-ubuntu-font-family
    )

    if ! lk_is_virtual && lk_is_portable; then
        # The deprecated synaptics touchpad driver is (still) better than xinput
        PAC_PACKAGES+=(xf86-input-synaptics)
    fi

    if lk_arr PAC_PACKAGES AUR_PACKAGES | grep -E \
        '(^ttf-joypixels-?($|:)|^ttf-.*\<(tw)?emoji\>|\<fonts-emoji\>)' \
        >/dev/null; then
        PAC_REJECT+=(noto-fonts-emoji)
    else
        PAC_PACKAGES+=(noto-fonts-emoji)
    fi

    AUR_PACKAGES+=(
        networkmanager-dispatcher-ntpd
        xrandr-invert-colors

        ttf-adobe-source-code-pro-fonts
        ttf-adobe-source-sans-fonts
        ttf-adobe-source-serif-fonts

        # Selected works of https://github.com/vinceliuice
        qogir-gtk-theme
        #qogir-icon-theme
        tela-icon-theme
        #vimix-cursors

        #whitesur-gtk-theme
        #whitesur-icon-theme
        #whitesur-cursor-theme-git
        #mojave-gtk-theme
        #mcmojave-circle-icon-theme # Requires numix-gtk-theme-git
        #mcmojave-cursors

        #numix-gtk-theme-git
        #sound-theme-smooth
        #zuki-themes

        #wiki-loves-earth-wallpapers
        #wiki-loves-monuments-wallpapers
    )
fi

if lk_node_service_enabled xfce4; then
    PAC_PACKAGES+=(
        xfce4
        xfce4-goodies

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

    ! lk_system_is_thinkpad || PAC_PACKAGES+=(
        tpacpi-bat
    )

    ! lk_system_has_intel_graphics || PAC_PACKAGES+=(
        intel-media-driver
        libva-intel-driver
    )
    ! lk_system_has_nvidia_graphics || PAC_PACKAGES+=(
        nvidia
        nvidia-utils
    )
    ! lk_system_has_amd_graphics || PAC_PACKAGES+=(
        xf86-video-amdgpu
        libva-mesa-driver
        mesa-vdpau
    )
fi

####

for ARR in PAC_PACKAGES AUR_PACKAGES; do
    lk_mapfile "$ARR" < <(lk_arr "$ARR" |
        if lk_is_virtual; then
            gnu_sed -E '/:BM\>/d'
        else
            gnu_sed -E 's/:BM\>//'
        fi |
        if lk_node_service_enabled minimal; then
            sed -E '/-$/d'
        else
            sed -E 's/-$//'
        fi)
done

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
        grep -Fxf <(awk '{print $1}' "$PAC_REPLACE") || true))
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

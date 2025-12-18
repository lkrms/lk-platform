#!/usr/bin/env bash

# shellcheck disable=SC2206,SC2207 # IFS is carefully managed here.

# Inputs:
#
# - `PAC_REPOS=("<name>|<server>|<key_id>|<key_url>" ...)`: unofficial package
#   repositories. Applied after repositories in `LK_ARCH_REPOS` and before
#   official Arch Linux repositories.
# - `PAC_PACKAGES=(<package> ...)`: packages to install from official
#   repositories. Each packages must be available in core, extra or multilib,
#   even if it is overridden by a custom build in an unofficial repository.
# - `AUR_PACKAGES=(<package> ...)`: packages to install from unofficial
#   repositories or build locally from the AUR (Arch User Repository).
# - `PAC_EXCEPT=(<package> ...)`: packages to exclude, e.g. from groups they
#   appear in. Packages in this list are only installed as dependencies of other
#   packages.
# - `PAC_OFFER=(<package> ...)`: packages not installed by default that are not
#   removed if present.
#
# Entries in `PAC_PACKAGES` and `AUR_PACKAGES` may have one or more of the
# following suffixes:
#
# - `-`  = do not install when `minimal` feature is enabled
# - `:H` = only install on physical Hardware
# - `:P` = only install on Portable devices
# - `:Q` = only install on QEMU guests

# add_package_if QUOTED_COMMAND PACKAGE...
function add_package_if() {
    if $1; then
        shift
        PAC_PACKAGES+=("$@")
    fi
}

# add_package_if_feature_enabled "FEATURE..." PACKAGE...
function add_package_if_feature_enabled() {
    # shellcheck disable=SC2086 # Multiple features may be given.
    if lk_feature_enabled $1; then
        shift
        PAC_PACKAGES+=("$@")
    fi
}

IFS=,
PAC_REPOS=(
    ${LK_ARCH_REPOS-}
    ${PAC_REPOS+"${PAC_REPOS[@]}"}
)
IFS=$' \t\n'

PAC_PACKAGES=(${PAC_PACKAGES+"${PAC_PACKAGES[@]}"})
AUR_PACKAGES=(${AUR_PACKAGES+"${AUR_PACKAGES[@]}"})
PAC_EXCEPT=(${PAC_EXCEPT+"${PAC_EXCEPT[@]}"})
PAC_OFFER=(${PAC_OFFER+"${PAC_OFFER[@]}"})

# References:
#
# - https://wiki.archlinux.org/title/Installation_guide
# - https://gitlab.archlinux.org/archlinux/archiso/-/raw/ab176d19b0caeb1fcd9452161c7dc133f674cca2/configs/releng/packages.x86_64

PAC_PACKAGES+=(
    ## Essentials
    #
    # - `base` dependencies (since 2022-01-26): `archlinux-keyring`, `bash`,
    #   `bzip2`, `coreutils`, `file`, `filesystem`, `findutils`, `gawk`,
    #   `gcc-libs`, `gettext`, `glibc`, `grep`, `gzip`, `iproute2`, `iputils`,
    #   `licenses`, `pacman`, `pciutils`, `procps-ng`, `psmisc`, `sed`,
    #   `shadow`, `systemd`, `systemd-sysvcompat`, `tar`, `util-linux`, `xz`
    # - `terminus-font`: Bitmap font for use with GRUB
    # - `kernel-modules-hook`: Restores the running kernel's modules between
    #   upgrade and reboot

    base
    linux
    linux-firmware:H
    mkinitcpio

    grub
    efibootmgr
    os-prober
    terminus-font-

    edk2-shell-
    kernel-modules-hook-

    ## System
    #
    # - `bolt`: Thunderbolt device manager and CLI
    # - `udisks2`: Required by `fwupd` for UEFI firmware upgrades
    # - `acpi`: Checks battery status
    # - `cpupower`: Manipulates processor frequency and power settings
    # - `msr-tools`: Manipulates processor MSRs ("Model-Specific Registers"),
    #   e.g. `BD PROCHOT`

    bolt
    dmidecode
    ethtool
    hwinfo
    networkmanager
    sysfsutils-
    usbutils

    conntrack-tools-
    ipset-
    iptables-nft

    fwupd:H
    udisks2:H

    acpi:H
    hddtemp:H
    hdparm-:H
    lm_sensors:H
    nvme-cli-:H
    powertop:H
    smartmontools:H
    tlp:H
    tlp-rdw:H
    wireless-regdb:H

    cpupower-:H
    msr-tools-:H

    ## VM guest integration
    #
    # - `open-vm-tools`, `virtualbox-guest-utils-nox` and `hyperv` will be added
    #   when VMware, VirtualBox and Hyper-V guest detection is implemented

    qemu-guest-agent:Q

    ## Filesystems
    #
    # - `gptfdisk`: Provides `sgdisk`

    gptfdisk
    parted

    btrfs-progs
    dosfstools
    e2fsprogs
    exfatprogs
    f2fs-tools-
    fatresize
    jfsutils-
    mtools-
    nbd-
    nfs-utils-
    nilfs-utils-
    ntfs-3g
    udftools-
    xfsprogs-

    lvm2-:H
    mdadm-:H

    ## Utilities
    #
    # - `bind`: Provides `dig`
    # - `fclones`: Performs file de-duplication
    # - `iftop`: Reports network traffic by service and host
    # - `inetutils`: Provides `hostname`, `telnet`
    # - `libnewt`: Provides `whiptail`
    # - `ndisc6`: Provides `rdisc6`
    # - `nethogs`: Reports network traffic by process (similar to `nettop`)
    # - `nload`: Reports network traffic by interface
    # - `s-tui`: CPU stress test and monitoring tool
    # - `sysstat`: Provides `iostat`, `pidstat`, `sar`
    # - `unzip`: Provides `zip`
    # - `wimlib`: Provides `wimextract`
    # - `pacman-contrib`: Provides `paccache`
    # - `pacutils`: Provides `paccheck`

    atop-
    bash-completion
    bc
    bind
    byobu-
    curl
    ddrescue-
    diffutils
    dos2unix
    fclones
    file
    fzf
    git
    git-delta
    grml-zsh-config
    htop
    iftop
    inetutils
    iotop
    jc
    jq
    less
    lf
    lftp
    libnewt
    logrotate
    lsof
    lynx
    mediainfo
    nano
    ncdu
    ndisc6-
    nethogs
    nload
    nmap-
    ntp
    openbsd-netcat
    openssh
    pv
    ranger
    rsync
    s-tui
    sudo
    sysstat
    tcpdump
    time
    tmux
    traceroute
    trash-cli
    vim
    wget
    whois
    wol
    xdelta3
    yq
    zsh

    7zip
    cabextract-
    innoextract-
    msitools-
    rpm-tools-
    unshield-
    unzip
    wimlib

    expac
    pacman-contrib
    pacutils
    rebuild-detector

    perl

    man-db
    man-pages
    texinfo
)

AUR_PACKAGES+=(
    ## System
    powercap-:H

    ## Utilities
    icdiff-
    ps_mem-
)

# - `edk2-ovmf`: UEFI firmware
# - `swtpm`: TPM emulator
add_package_if lk_system_has_intel_cpu intel-ucode:H
add_package_if lk_system_has_amd_cpu amd-ucode:H
add_package_if_feature_enabled lighttpd lighttpd
add_package_if_feature_enabled squid squid
add_package_if_feature_enabled apache2 apache
add_package_if_feature_enabled php-fpm php-fpm fcgi
add_package_if_feature_enabled mariadb mariadb
add_package_if_feature_enabled docker docker docker-buildx-
add_package_if_feature_enabled libvirt \
    libvirt qemu-desktop dnsmasq edk2-ovmf swtpm libguestfs cpio virt-install
add_package_if_feature_enabled "libvirt desktop" virt-manager virt-viewer

if lk_feature_enabled desktop; then
    PAC_PACKAGES+=(
        xorg-server
        xorg-apps # Provides setxkbmap, xrandr, xrdb, xdpyinfo, ...
        xorg-fonts-100dpi

        xf86-input-synaptics:P # The deprecated synaptics touchpad driver is (still) better than xinput

        bluez:H
        bluez-utils-:H
        blueman:H

        libva-utils- # Provides vainfo
        mesa         # Includes iris, nouveau, virtio_gpu, ...
        mesa-utils-  # Provides glxinfo
        spice-vdagent:Q
        vdpauinfo-

        lightdm
        lightdm-gtk-greeter
        lightdm-gtk-greeter-settings

        xsecurelock
        xss-lock

        autorandr
        cups
        gnome-disk-utility # Provides gnome-disk-image-mounter
        gnome-keyring
        gvfs
        gvfs-afc # Apple devices
        gvfs-mtp # Others
        gvfs-nfs-
        gvfs-smb
        network-manager-applet
        seahorse
        x11vnc
        xdg-user-dirs # Manage ~/Desktop, ~/Templates, etc.
        yad

        capitaine-cursors-
        papirus-icon-theme-
        vimix-cursors-

        epiphany # WebKit-based web browser
        evince   # Document viewer
        galculator
        geany # notepadqq is smaller but depends on Qt
        gimp-
        mpv
        qalculate-gtk-
        speedcrunch-
        vlc-
        vlc-plugin-ffmpeg-

        pipewire
        pipewire-audio      # Supports Bluetooth audio
        pipewire-alsa       # Supports ALSA clients
        pipewire-jack       # Supports JACK clients
        pipewire-pulse      # Supports PulseAudio clients
        gst-plugin-pipewire # Supports GStreamer clients
        wireplumber         # Starts PipeWire via a systemd user unit

        gst-libav         # "libav-based plugin containing many decoders and encoders"
        gst-plugins-bad-  # "Plugins that need more quality, testing or documentation"
        gst-plugins-base  # "Essential exemplary set of elements"
        gst-plugins-good  # "Good-quality plugins under LGPL license"
        gst-plugins-ugly- # "Good-quality plugins that might pose distribution problems"
        libdvdcss-

        # adobe-source-* packages have been replaced with aur/ttf-adobe-source-*
        # because adobe-source-sans-fonts OTFs have rendering issues below ~12px
        noto-fonts
        noto-fonts-cjk
        ttf-dejavu
        ttf-fantasque-sans-mono- # For programming
        ttf-inconsolata          # For terminals and programming
        ttf-jetbrains-mono-      # For programming
        ttf-lato
        ttf-opensans
        ttf-roboto
        ttf-roboto-mono
        ttf-ubuntu-font-family
    )

    # Hardware video acceleration
    #
    # - VA-API and VDPAU are the main hardware-accelerated video
    #   encoding/decoding libraries
    # - Intel drivers only support VA-API, but `libvdpau-va-gl` can be installed
    #   to translate VDPAU to VA-API for VDPAU-only software
    # - AMD drivers support VA-API and VDPAU
    # - NVIDIA drivers also support both, but proprietary firmware must be
    #   installed
    ! lk_system_has_intel_graphics || PAC_PACKAGES+=(
        # xf86-video-intel hasn't been recommended since Gen4
        intel-media-driver # For Broadwell (2014) and newer
        libva-intel-driver # For GMA 4500 (2008) and newer, up to Coffee Lake (2017)
        intel-gpu-tools-   # Provides intel_gpu_top
    )
    ! lk_system_has_amd_graphics || PAC_PACKAGES+=(
        xf86-video-amdgpu
        mesa
        radeontop- # Equivalent to intel_gpu_top
    )
    ! lk_system_has_nvidia_graphics || PAC_PACKAGES+=(
        nvidia
        nvidia-utils
    )

    # Install noto-fonts-emoji unless an emoji font is already being installed
    lk_arr PAC_PACKAGES AUR_PACKAGES |
        grep -E \
            '(^ttf-joypixels-?($|:)|^ttf-.*\<(tw)?emoji\>|\<fonts-emoji\>)' >/dev/null ||
        PAC_PACKAGES+=(noto-fonts-emoji)

    AUR_PACKAGES+=(
        pinta-
        xrandr-invert-colors-

        ttf-adobe-source-code-pro-fonts-
        ttf-adobe-source-sans-fonts-
        ttf-adobe-source-serif-fonts-

        # Selected works of https://github.com/vinceliuice
        qogir-gtk-theme-
        qogir-icon-theme-
        tela-icon-theme-
    )
fi

if lk_feature_enabled xfce4; then
    PAC_PACKAGES+=(
        xfce4
        xfce4-goodies
        xfce4-panel-profiles-

        catfish
        engrampa
        mugshot
        pavucontrol
        plank
    )

    PAC_EXCEPT+=(
        xfce4-screensaver
    )

    AUR_PACKAGES+=(
        xfce-theme-greybird- # Xubuntu's default theme
    )
fi

####

for ARR in PAC_PACKAGES AUR_PACKAGES; do
    lk_mapfile "$ARR" < <(
        lk_arr "$ARR" |
            if lk_system_is_qemu; then
                # Keep QEMU, remove bare metal and portable
                gnu_sed -E 's/:Q\>//; /:(H|P)\>/d'
            elif lk_system_is_vm; then
                # Remove bare metal, portable and QEMU
                gnu_sed -E '/:(H|P|Q)\>/d'
            elif lk_is_portable; then
                # Keep bare metal and portable, remove QEMU
                gnu_sed -E 's/:(H|P)\>//; /:Q\>/d'
            else
                # Keep bare metal, remove portable and QEMU
                gnu_sed -E 's/:H\>//; /:(P|Q)\>/d'
            fi
    )
    if lk_feature_enabled minimal; then
        # Add optional to PAC_OFFER
        lk_mapfile PAC_OFFER < <(
            { lk_arr PAC_OFFER &&
                lk_arr "$ARR" | sed -En 's/-$//p'; } | sort -u
        )
        # Remove optional
        lk_mapfile "$ARR" < <(
            lk_arr "$ARR" | sed -E '/-$/d' | sort -u
        )
    else
        # Keep optional
        lk_mapfile "$ARR" < <(
            lk_arr "$ARR" | sed -E 's/-$//' | sort -u
        )
    fi
done

if [[ -n ${PAC_REPOS+1} ]]; then
    PAC_REPOS=($(lk_arr PAC_REPOS | lk_uniq))
    lk_arch_add_repo "${PAC_REPOS[@]}"
    # TODO: check order of repos here
fi

lk_pac_sync

# Get package and group lists to minimise calls to pacman
declare _repo_pkg _group_pkg _pkg _group _official_pkg _official_group
lk_mktemp_with _repo_pkg pacman -Sl                                                                    # <repo> <package> <version>
lk_mktemp_with _group_pkg pacman -Sgg                                                                  # <group> <package>
lk_mktemp_with _pkg sort -u <(awk '{ print $2 }' "$_repo_pkg")                                         # <package>
lk_mktemp_with _group sort -u <(awk '{ print $1 }' "$_group_pkg" | grep -Fxvf "$_pkg")                 # <group>
lk_mktemp_with _official_pkg sort -u <(awk '$1 ~ /^(core|extra|multilib)$/ { print $2 }' "$_repo_pkg") # <package>
lk_mktemp_with _official_group sort -u <(
    regex=$(lk_ere_implode_input -e < <(awk '{ print $2 }' "$_group_pkg" | grep -Fxf "$_official_pkg"))
    awk -v "regex=^${regex//\\/\\\\}\$" '$2 ~ regex { print $1 }' "$_group_pkg"
)

# Check for PAC_PACKAGES removed from official repos
if removed=$(lk_arr PAC_PACKAGES | grep -Fxvf "$_official_pkg" -f "$_official_group"); then
    lk_tty_warning "Ignoring (removed from official repos):" "$removed"
    PAC_PACKAGES=($(lk_arr PAC_PACKAGES | grep -Fxf "$_official_pkg" -f "$_official_group"))
fi

# Check for AUR_PACKAGES that are now in an official repo
if moved=$(grep -Fxf <(lk_arr AUR_PACKAGES) "$_official_pkg"); then
    lk_tty_warning "Moved from AUR to official repos:" "$moved"
    PAC_PACKAGES+=($moved)
fi

# Replace groups in PAC_PACKAGES with the packages they contain
if group=$(lk_arr PAC_PACKAGES | grep -Fxf "$_group"); then
    PAC_PACKAGES=($({
        lk_arr PAC_PACKAGES | grep -Fxvf "$_group" || true
        regex=$(lk_ere_implode_input -e <<<"$group")
        awk -v "regex=^${regex//\\/\\\\}\$" '$1 ~ regex { print $2 }' "$_group_pkg"
    } | sort -u))
fi

# Remove packages in PAC_EXCEPT from PAC_PACKAGES and AUR_PACKAGES
if [[ -n ${PAC_EXCEPT+1} ]]; then
    PAC_PACKAGES=($(lk_arr PAC_PACKAGES | grep -Fxvf <(lk_arr PAC_EXCEPT) || true))
    AUR_PACKAGES=($(lk_arr AUR_PACKAGES | grep -Fxvf <(lk_arr PAC_EXCEPT) || true))
fi

# Move AUR_PACKAGES that can be installed from a repo to PAC_PACKAGES
PAC_PACKAGES=($(lk_arr PAC_PACKAGES AUR_PACKAGES | grep -Fxf "$_pkg" || true))
AUR_PACKAGES=($(lk_arr AUR_PACKAGES | grep -Fxvf "$_pkg" || true))

if [[ -n ${AUR_PACKAGES+1} ]] ||
    [[ -n ${LK_ARCH_AUR_REPO_NAME-} ]] ||
    { pacman-conf --repo="${LK_ARCH_AUR_REPO_NAME:-aur}" |
        awk -F '[ \t]*=[ \t]*' '$1 == "Server" && $2 ~ /^[fF][iI][lL][eE]:\/\//' |
        grep .; } &>/dev/null; then
    # Add makepkg essentials
    PAC_PACKAGES+=(base-devel devtools)
    # Don't remove aurutils packages
    PAC_OFFER+=(aurutils vifm)
fi

# Remove packages in PAC_PACKAGES or AUR_PACKAGES from PAC_OFFER
if [[ -n ${PAC_OFFER+1} ]]; then
    PAC_OFFER=($(lk_arr PAC_OFFER | grep -Fxvf <(lk_arr PAC_PACKAGES AUR_PACKAGES) || true))
fi

PAC_PACKAGES=($(lk_arr PAC_PACKAGES | sort -u))
AUR_PACKAGES=($(lk_arr AUR_PACKAGES | sort -u))

#### Reviewed: 2025-06-19 (except desktop packages)

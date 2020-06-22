#!/bin/bash
# shellcheck disable=SC1090,SC2015,SC2016,SC2034,SC2046,SC2174,SC2207

set -euo pipefail
lk_die() { echo "$1" >&2 && exit 1; }
[ -n "${LK_BASE:-}" ] || { BS="${BASH_SOURCE[0]}" && [ ! -L "$BS" ] &&
    LK_BASE="$(cd "$(dirname "$BS")/.." && pwd -P)" &&
    [ -d "$LK_BASE/lib/bash" ] || lk_die "${BS:+$BS: }LK_BASE not set"; }

include=deploy,php,httpd . "$LK_BASE/lib/bash/common.sh"

lk_assert_not_root

PACMAN_PACKAGES=()
AUR_PACKAGES=()

# if installed, won't be marked as a dependency
PAC_KEEP=(
    aurutils

    #
    azure-cli
    sfdx-cli

    #
    mongodb-bin

    #
    asciicast2gif
    chromium
    woeusb
)

PAC_REMOVE=(
    # buggy and insecure
    xfce4-screensaver

    # vscodium-bin is preferred
    code
    visual-studio-code-bin
)

# hardware-related
lk_is_virtual || {
    PACMAN_PACKAGES+=(
        guvcview # webcam utility
        linssid  # wireless scanner

        # "general-purpose computing on graphics processing units" (GPGPU)
        # required to run GPU benchmarks, e.g. in Geekbench
        clinfo
        $(
            GRAPHICS_CONTROLLERS="$(lspci | grep -E 'VGA|3D')" || return 0
            ! grep -qi "Intel" <<<"$GRAPHICS_CONTROLLERS" ||
                echo "intel-compute-runtime"
            ! grep -qi "NVIDIA" <<<"$GRAPHICS_CONTROLLERS" ||
                echo "opencl-nvidia"
        )
        i2c-tools # provides i2c-dev module (required by ddcutil)
    )
    AUR_PACKAGES+=(
        ddcutil
        r8152-dkms # common USB / USB-C NIC
    )
}
AUR_PACKAGES+=(
    brother-hl5450dn
    brother-hll3230cdw
)

# terminal-based
PACMAN_PACKAGES+=(
    # shells
    asciinema
    ksh
    zsh

    # utilities
    bc
    cdrtools
    jq
    mediainfo
    p7zip
    pv
    stow
    unison
    unzip
    wimlib
    yq

    # networking
    bridge-utils
    openconnect
    whois

    # monitoring
    atop
    glances
    htop # 'top' alternative
    iotop
    lsof

    # network monitoring
    iftop   # shows network traffic by service and host
    nethogs # groups bandwidth by process ('nettop')
    nload   # shows bandwidth by interface

    # system
    acme.sh
    at
    cloud-utils
    cronie
    hwinfo
    mlocate
    sysfsutils
)

AUR_PACKAGES+=(
    vpn-slice
)

# desktop
PACMAN_PACKAGES+=(
    caprine
    copyq
    firefox-i18n-en-gb
    flameshot
    freerdp
    gucharmap
    inkscape
    keepassxc
    libreoffice-fresh-en-gb
    nextcloud-client
    nomacs
    qpdfview
    remmina
    scribus
    simplescreenrecorder
    speedcrunch
    system-config-printer
    thunderbird
    thunderbird-i18n-en-gb
    transmission-cli
    transmission-gtk
    trash-cli

    # because there's always That One Website
    flashplugin

    # PDF
    ghostscript  # PDF/PostScript processor
    mupdf-tools  # PDF manipulation tools
    pandoc       # text conversion tool (e.g. Markdown to PDF)
    poppler      # PDF tools like pdfimages
    pstoedit     # converts PDF/PostScript to vector formats
    texlive-core # required for PDF output from pandoc

    # photography
    geeqie
    rapid-photo-downloader

    # search (Recoll)
    antiword            # Word
    aspell-en           # English stemming
    catdoc              # Excel, Powerpoint
    perl-image-exiftool # EXIF metadata
    python-lxml         # spreadsheets
    recoll
    unrtf

    # multimedia - playback
    clementine
    gst-plugins-bad

    # multimedia - audio
    abcde
    audacity
    python-eyed3
    sox

    # multimedia - video
    ffmpeg
    handbrake
    handbrake-cli
    mkvtoolnix-cli
    mkvtoolnix-gui
    mpv
    openshot
    rtmpdump
    youtube-dl

    # system
    dconf-editor
    displaycal
    gparted
    guake
    libsecret   # secret-tool
    libva-utils # vainfo
    syslinux
    vdpauinfo

    # automation
    sxhkd
    wmctrl
    xautomation
    xclip
    xdotool
    xorg-xev
)

AUR_PACKAGES+=(
    espanso
    ghostwriter
    google-chrome
    masterpdfeditor-free
    skypeforlinux-stable-bin
    spotify
    teams
    todoist-electron
    trimage
    ttf-ms-win10
    typora

    # multimedia - video
    makemkv

    # system
    hfsprogs

    # automation
    devilspie2
    quicktile-git
)

# development
PACMAN_PACKAGES+=(
    autopep8
    bash-language-server
    dbeaver
    eslint
    geckodriver
    python-pylint
    qcachegrind
    tidy
    ttf-font-awesome
    ttf-ionicons

    # email
    msmtp     # smtp client
    msmtp-mta # sendmail alias for msmtp
    s-nail    # mail and mailx commands

    #
    git-filter-repo
    meld

    #
    jdk11-openjdk
    jre11-openjdk

    #
    nodejs
    npm
    yarn

    #
    composer
    php
    php-gd
    php-imagick
    php-imap
    php-intl
    php-memcache
    php-memcached
    php-sqlite
    xdebug

    #
    mysql-python
    python
    python-acme # for working with Let's Encrypt
    python-dateutil
    python-pip
    python-requests
    python-virtualenv
    python2

    #
    shellcheck
    shfmt

    #
    lua
    lua-penlight

    # platforms
    aws-cli
)

AUR_PACKAGES+=(
    sublime-text-dev
    trickle
    vscodium-bin

    #
    git-cola
    sublime-merge

    # platforms
    wp-cli
)

# development services
PACMAN_PACKAGES+=(
    apache
    mariadb
    php-fpm
)

# VMs and containers
PACMAN_PACKAGES+=(
    # KVM/QEMU
    dnsmasq
    ebtables
    edk2-ovmf # UEFI firmware
    libvirt
    qemu
    virt-manager

    #
    docker
)

. "$LK_BASE/lib/arch/packages.sh"

{
    ! lk_sudo_offer_nopasswd ||
        {
            PASSWORD_STATUS="$(sudo passwd -S root | cut -d' ' -f2)"
            [ "$PASSWORD_STATUS" = "L" ] || {
                lk_console_message "Disabling password-based login as root"
                sudo passwd -l root
            }

            ! sudo test -d "/etc/polkit-1/rules.d" ||
                sudo test -e "/etc/polkit-1/rules.d/49-wheel.rules" || {
                lk_console_message "Disabling polkit password prompts"
                sudo tee "/etc/polkit-1/rules.d/49-wheel.rules" <<EOF >/dev/null
// Allow any user in the 'wheel' group to take any action without
// entering a password.
polkit.addRule(function (action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
            }
        }

    PAC_TO_REMOVE=($(comm -12 <(pacman -Qq | sort | uniq) <(lk_echo_array "${PAC_REMOVE[@]}" | sort | uniq)))
    [ "${#PAC_TO_REMOVE[@]}" -eq "0" ] || {
        lk_console_message "Removing packages"
        sudo pacman -R "${PAC_TO_REMOVE[@]}"
    }

    lk_console_message "Checking install reasons"
    PAC_EXPLICIT=($(lk_echo_array "${PACMAN_PACKAGES[@]}" "${AUR_PACKAGES[@]}" ${PAC_KEEP[@]+"${PAC_KEEP[@]}"} | sort | uniq))
    PAC_TO_MARK_ASDEPS=($(comm -23 <(pacman -Qeq | sort | uniq) <(lk_echo_array "${PAC_EXPLICIT[@]}")))
    PAC_TO_MARK_EXPLICIT=($(comm -12 <(pacman -Qdq | sort | uniq) <(lk_echo_array "${PAC_EXPLICIT[@]}")))
    [ "${#PAC_TO_MARK_ASDEPS[@]}" -eq "0" ] ||
        sudo pacman -D --asdeps "${PAC_TO_MARK_ASDEPS[@]}"
    [ "${#PAC_TO_MARK_EXPLICIT[@]}" -eq "0" ] ||
        sudo pacman -D --asexplicit "${PAC_TO_MARK_EXPLICIT[@]}"

    PAC_TO_INSTALL=($(comm -13 <(pacman -Qeq | sort | uniq) <(lk_echo_array "${PACMAN_PACKAGES[@]}" | sort | uniq)))
    [ "${#PAC_TO_INSTALL[@]}" -eq "0" ] || {
        lk_console_message "Installing new packages from repo"
        sudo pacman -Sy "${PAC_TO_INSTALL[@]}"
    }

    lk_console_message "Upgrading installed packages"
    sudo pacman -Syu

    if [ "${#AUR_PACKAGES[@]}" -gt "0" ]; then
        lk_command_exists yay || {
            lk_console_message "Installing yay to manage AUR packages"
            eval "$YAY_SCRIPT"
        }
        AUR_TO_INSTALL=($(comm -13 <(pacman -Qeq | sort | uniq) <(lk_echo_array "${AUR_PACKAGES[@]}" | sort | uniq)))
        [ "${#AUR_TO_INSTALL[@]}" -eq "0" ] || {
            lk_console_message "Installing new packages from AUR"
            yay -Sy --aur "${AUR_TO_INSTALL[@]}"
        }
        lk_console_message "Upgrading installed AUR packages"
        yay -Syu --aur
    fi

    ! PAC_TO_PURGE=($(pacman -Qdttq)) ||
        [ "${#PAC_TO_PURGE[@]}" -eq "0" ] ||
        {
            lk_echo_array "${PAC_TO_PURGE[@]}" |
                lk_console_list "Installed but no longer required:" package packages
            ! lk_confirm "Remove the above?" Y ||
                sudo pacman -Rns "${PAC_TO_PURGE[@]}"
        }

    SUDO_OR_NOT=1

    lk_apply_setting "/etc/ssh/sshd_config" "PasswordAuthentication" "no" " " "#" " " &&
        lk_apply_setting "/etc/ssh/sshd_config" "AcceptEnv" "LANG LC_*" " " "#" " " &&
        sudo systemctl enable --now sshd || true

    sudo systemctl enable --now atd || true

    sudo systemctl enable --now cronie || true

    sudo systemctl enable --now ntpd || true

    sudo systemctl enable --now org.cups.cupsd || true

    lk_apply_setting "/etc/bluetooth/main.conf" "AutoEnable" "true" "=" "#" &&
        sudo systemctl enable --now bluetooth

    lk_apply_setting "/etc/conf.d/libvirt-guests" "ON_SHUTDOWN" "shutdown" "=" "# " &&
        lk_apply_setting "/etc/conf.d/libvirt-guests" "SHUTDOWN_TIMEOUT" "300" "=" "# " &&
        sudo usermod --append --groups libvirt,kvm "$USER" &&
        {
            [ -e "/etc/qemu/bridge.conf" ] || {
                sudo mkdir -p "/etc/qemu" &&
                    echo "allow all" | sudo tee "/etc/qemu/bridge.conf" >/dev/null
            }
        } &&
        sudo systemctl enable --now libvirtd libvirt-guests || true

    sudo usermod --append --groups docker "$USER" &&
        sudo systemctl enable --now docker || true

    { sudo test -d "/var/lib/mysql/mysql" ||
        sudo mariadb-install-db --user="mysql" --basedir="/usr" --datadir="/var/lib/mysql"; } &&
        sudo systemctl enable --now mysqld || true

    PHP_INI_FILE=/etc/php/php.ini
    for PHP_EXT in bcmath curl gd gettext imap intl mysqli pdo_sqlite soap sqlite3 xmlrpc zip; do
        lk_enable_php_entry "extension=$PHP_EXT"
    done
    lk_enable_php_entry "zend_extension=opcache"
    sudo install -d -m 0700 -o "http" -g "http" "/var/cache/php/opcache"
    lk_apply_php_setting "memory_limit" "128M"
    lk_apply_php_setting "error_reporting" "E_ALL"
    lk_apply_php_setting "display_errors" "On"
    lk_apply_php_setting "display_startup_errors" "On"
    lk_apply_php_setting "log_errors" "Off"
    lk_apply_php_setting "opcache.memory_consumption" "512"
    lk_apply_php_setting "opcache.file_cache" "/var/cache/php/opcache"
    [ ! -f "/etc/php/conf.d/imagick.ini" ] ||
        PHP_INI_FILE="/etc/php/conf.d/imagick.ini" \
            lk_enable_php_entry "extension=imagick"
    [ ! -f "/etc/php/conf.d/memcache.ini" ] ||
        PHP_INI_FILE="/etc/php/conf.d/memcache.ini" \
            lk_enable_php_entry "extension=memcache.so"
    [ ! -f "/etc/php/conf.d/memcached.ini" ] ||
        PHP_INI_FILE="/etc/php/conf.d/memcached.ini" \
            lk_enable_php_entry "extension=memcached.so"
    [ ! -f "/etc/php/conf.d/xdebug.ini" ] || {
        install -d -m 0777 "$HOME/.tmp/cachegrind"
        install -d -m 0777 "$HOME/.tmp/trace"
        PHP_INI_FILE="/etc/php/conf.d/xdebug.ini"
        lk_enable_php_entry "zend_extension=xdebug.so"
        lk_apply_php_setting "xdebug.remote_enable" "On"
        lk_apply_php_setting "xdebug.remote_autostart" "Off"
        lk_apply_php_setting "xdebug.profiler_enable_trigger" "On"
        lk_apply_php_setting "xdebug.profiler_output_dir" "$HOME/.tmp/cachegrind"
        lk_apply_php_setting "xdebug.profiler_output_name" "callgrind.out.%H.%R.%u"
        lk_apply_php_setting "xdebug.trace_enable_trigger" "On"
        lk_apply_php_setting "xdebug.collect_params" "4"
        lk_apply_php_setting "xdebug.collect_return" "On"
        lk_apply_php_setting "xdebug.trace_output_dir" "$HOME/.tmp/trace"
        lk_apply_php_setting "xdebug.trace_output_name" "trace.%H.%R.%u"
    }
    [ ! -f "/etc/php/php-fpm.conf" ] ||
        {
            PHP_INI_FILE="/etc/php/php-fpm.conf"
            lk_apply_php_setting "emergency_restart_threshold" "10" # restart FPM if 10 children are gone in 60 seconds
            lk_apply_php_setting "emergency_restart_interval" "60"  #
            lk_apply_php_setting "events.mechanism" "epoll"         # don't rely on auto detection
        }
    [ ! -f "/etc/php/php-fpm.d/www.conf" ] ||
        {
            sudo chgrp http "/var/log/httpd" &&
                sudo chmod g+w "/var/log/httpd"
            PHP_INI_FILE="/etc/php/php-fpm.d/www.conf"
            lk_apply_php_setting "pm" "static"             # ondemand can't handle bursts: https://github.com/php/php-src/pull/1308
            lk_apply_php_setting "pm.max_children" "50"    # MUST be >= MaxRequestWorkers in httpd.conf
            lk_apply_php_setting "pm.max_requests" "0"     # don't respawn automatically
            lk_apply_php_setting "rlimit_files" "524288"   # check `ulimit -Hn` and raise for user http in /etc/security/limits.d/ if required
            lk_apply_php_setting "rlimit_core" "unlimited" # as above, but check `ulimit -Hc` instead
            lk_apply_php_setting "pm.status_path" "/status"
            lk_apply_php_setting "ping.path" "/ping"
            lk_apply_php_setting "access.log" '/var/log/httpd/php-fpm-$pool.access.log'
            lk_apply_php_setting "access.format" '"%R - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'
            lk_apply_php_setting "catch_workers_output" "yes"
            lk_apply_php_setting "php_admin_value[error_log]" '/var/log/httpd/php-fpm-$pool.error.log'
            lk_apply_php_setting "php_admin_flag[log_errors]" "On"
            lk_apply_php_setting "php_flag[display_errors]" "Off"
            lk_apply_php_setting "php_flag[display_startup_errors]" "Off"
        }
    sudo systemctl enable --now php-fpm || true

    HTTPD_CONF_FILE="/etc/httpd/conf/httpd.conf"
    sudo install -d -m 0755 -o "$USER" -g "$(id -gn)" "/srv/http" &&
        mkdir -p "/srv/http/localhost/html" "/srv/http/127.0.0.1" &&
        { [ -e "/srv/http/127.0.0.1/html" ] || ln -s "../localhost/html" "/srv/http/127.0.0.1/html"; } &&
        lk_safe_symlink "$LK_ROOT/etc/httpd/dev-defaults.conf" "/etc/httpd/conf/extra/httpd-dev-defaults.conf" &&
        lk_enable_httpd_entry "Include conf/extra/httpd-vhost-alias.conf" &&
        lk_enable_httpd_entry "LoadModule alias_module modules/mod_alias.so" &&
        lk_enable_httpd_entry "LoadModule dir_module modules/mod_dir.so" &&
        lk_enable_httpd_entry "LoadModule headers_module modules/mod_headers.so" &&
        lk_enable_httpd_entry "LoadModule info_module modules/mod_info.so" &&
        lk_enable_httpd_entry "LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so" &&
        lk_enable_httpd_entry "LoadModule proxy_module modules/mod_proxy.so" &&
        lk_enable_httpd_entry "LoadModule rewrite_module modules/mod_rewrite.so" &&
        lk_enable_httpd_entry "LoadModule status_module modules/mod_status.so" &&
        lk_enable_httpd_entry "LoadModule vhost_alias_module modules/mod_vhost_alias.so" &&
        sudo usermod --append --groups "http" "$USER" &&
        sudo usermod --append --groups "$(id -gn)" "http" &&
        sudo systemctl enable --now httpd || true

    ! lk_command_exists vim || lk_safe_symlink "$(command -v vim)" "/usr/local/bin/vi"
    ! lk_command_exists xfce4-terminal || lk_safe_symlink "$(command -v xfce4-terminal)" "/usr/local/bin/xterm"
    lk_install_gnu_commands

    unset SUDO_OR_NOT

    exit
}

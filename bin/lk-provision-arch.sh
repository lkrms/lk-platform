#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2016,SC2031,SC2034,SC2206,SC2207,SC2046,SC2086

set -euo pipefail
_DEPTH=1
_FILE=${BASH_SOURCE[0]}
lk_die() { s=$? && echo "$_FILE: $1" >&2 && (exit $s) && false || exit; }
{ type -P realpath || { type -P python && realpath() { python -c \
    "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }; }; } \
    >/dev/null || lk_die "command not found: realpath"
_FILE=$(realpath "$_FILE") && _DIR=${_FILE%/*} &&
    LK_BASE=$(realpath "$_DIR$(eval printf '/..%.s' $(seq 1 "$_DEPTH"))") &&
    [ -d "$LK_BASE/lib/bash" ] ||
    lk_die "unable to locate LK_BASE"
export LK_BASE

include=arch,git,linux,provision . "$LK_BASE/lib/bash/common.sh"

! lk_in_chroot || LK_BOOTSTRAP=1

function is_bootstrap() {
    [ -n "${LK_BOOTSTRAP:-}" ]
}

if is_bootstrap; then
    function systemctl_enable() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        [ ! -e "/usr/lib/systemd/system/$1" ] &&
            [ ! -e "/etc/systemd/system/$1" ] || {
            lk_console_detail "Enabling service:" "${2:-$1}"
            sudo systemctl enable "$1"
        }
    }
    function systemctl_mask() {
        [[ $1 == *.* ]] || set -- "$1.service" "${@:2}"
        lk_console_detail "Masking service:" "${2:-$1}"
        sudo systemctl mask "$1"
    }
    lk_console_blank
else
    function systemctl_enable() {
        ! lk_systemctl_exists "$1" || {
            lk_systemctl_running "$1" || SERVICE_STARTED+=("$1")
            lk_systemctl_enable_now ${2:+-n "$2"} "$1"
        }
    }
    function systemctl_mask() {
        lk_systemctl_mask ${2:+-n "$2"} "$1"
    }
fi

function service_apply() {
    local i EXIT_STATUS=0
    lk_console_message "Checking services"
    is_bootstrap || ! lk_is_true DAEMON_RELOAD ||
        lk_run_detail sudo systemctl daemon-reload || EXIT_STATUS=$?
    [ ${#SERVICE_ENABLE[@]} -eq 0 ] ||
        for i in $(seq 0 2 $((${#SERVICE_ENABLE[@]} - 1))); do
            systemctl_enable "${SERVICE_ENABLE[@]:$i:2}" || EXIT_STATUS=$?
        done
    is_bootstrap || [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
        SERVICE_RESTART=($(comm -23 \
            <(lk_echo_array SERVICE_RESTART | sort -u) \
            <(lk_echo_array SERVICE_STARTED | sort -u))) && {
            [ ${#SERVICE_RESTART[@]} -eq 0 ] || {
                lk_console_message "Restarting services with changed settings"
                for SERVICE in "${SERVICE_RESTART[@]}"; do
                    lk_systemctl_restart "$SERVICE" || EXIT_STATUS=$?
                done
            } || EXIT_STATUS=$?
        }
    }
    DAEMON_RELOAD=
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    SERVICE_STARTED=()
    return "$EXIT_STATUS"
}

function file_delete() {
    local FILES=("$@")
    LK_FILE_REPLACE_NO_CHANGE=${LK_FILE_REPLACE_NO_CHANGE:-1}
    lk_remove_missing FILES
    [ ${#FILES[@]} -eq 0 ] || {
        LK_FILE_REPLACE_NO_CHANGE=0
        sudo rm -fv "${FILES[@]}"
    }
}

function is_desktop() {
    lk_node_service_enabled desktop
}

function memory_at_least() {
    _LK_SYSTEM_MEMORY=${_LK_SYSTEM_MEMORY:-$(lk_system_memory)}
    [ "$_LK_SYSTEM_MEMORY" -ge "$1" ]
}

shopt -s nullglob

lk_assert_not_root
lk_assert_is_arch

lk_sudo_offer_nopasswd || lk_die "unable to run commands as root"

LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE:-}}
if [ -n "$LK_PACKAGES_FILE" ]; then
    if [ ! -f "$LK_PACKAGES_FILE" ]; then
        FILE=${LK_PACKAGES_FILE##*/}
        FILE=${FILE#packages-arch-}
        FILE=${FILE%.sh}
        FILE=$LK_BASE/share/packages/arch/$FILE.sh
        [ -f "$FILE" ] || lk_die "file not found: $LK_PACKAGES_FILE"
        LK_PACKAGES_FILE=$FILE
    fi
    export LK_PACKAGES_FILE
fi

lk_log_output

{
    lk_console_log "Provisioning Arch Linux"
    ! is_bootstrap || lk_console_detail "Bootstrap environment detected"
    MEMORY=$(lk_system_memory 2)
    lk_console_detail "System memory:" "${MEMORY}M"

    LK_SUDO=1

    EXIT_STATUS=0
    SERVICE_STARTED=()
    SERVICE_ENABLE=()
    SERVICE_RESTART=()
    DAEMON_RELOAD=

    # Try to detect missing settings
    if ! is_bootstrap; then
        [ -n "${LK_NODE_TIMEZONE:-}" ] || ! _TZ=$(lk_system_timezone) ||
            export LK_NODE_TIMEZONE=$_TZ
        [ -n "${LK_NODE_HOSTNAME:-}" ] || ! _HN=$(lk_hostname) ||
            export LK_NODE_HOSTNAME=$_HN
        [ -n "${LK_NODE_LOCALES+1}" ] ||
            LK_NODE_LOCALES="en_AU.UTF-8 en_GB.UTF-8"
        [ -n "${LK_NODE_LANGUAGE+1}" ] ||
            LK_NODE_LANGUAGE=en_AU:en_GB:en
    fi

    if [ -n "${LK_NODE_TIMEZONE:-}" ]; then
        lk_console_message "Checking system time zone"
        FILE=/usr/share/zoneinfo/$LK_NODE_TIMEZONE
        lk_symlink "$FILE" /etc/localtime
    fi

    if [ ! -e /etc/adjtime ]; then
        lk_console_message "Setting hardware clock"
        lk_run_detail sudo hwclock --systohc
    fi

    lk_console_message "Checking locales"
    lk_configure_locales

    if [ -n "${LK_NODE_HOSTNAME:-}" ]; then
        lk_console_message "Checking system hostname"
        FILE=/etc/hostname
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" "$LK_NODE_HOSTNAME"

        lk_console_message "Checking hosts file"
        FILE=/etc/hosts
        _FILE=$(HOSTS="# Generated by ${0##*/} at $(lk_date_log)
127.0.0.1 localhost
::1 localhost
${LK_NODE_IPV4_ADDRESS:-127.0.1.1} \
${LK_NODE_FQDN:-$LK_NODE_HOSTNAME.localdomain} \
$LK_NODE_HOSTNAME" &&
            awk \
                -v "HOSTS=$HOSTS" \
                -v "FIRST=^(# Generated by |127.0.0.1 localhost($S|\$))" \
                -v "LAST=^127.0.1.1 " \
                -v "BREAK=^$S*\$" \
                -v "MAX_LINES=4" \
                -f "$LK_BASE/lib/awk/hosts-update.awk" \
                "$FILE" && printf .)
        _FILE=${_FILE%.}
        lk_file_keep_original "$FILE"
        lk_file_replace -i "^(#|$S*\$)" "$FILE" "$_FILE"
    else
        lk_console_error \
            "Cannot check hostname or /etc/hosts: LK_NODE_HOSTNAME is not set"
    fi

    lk_console_message "Checking systemd default target"
    is_desktop &&
        DEFAULT_TARGET=graphical.target ||
        DEFAULT_TARGET=multi-user.target
    CURRENT_DEFAULT_TARGET=$(${LK_BOOTSTRAP:+sudo} systemctl get-default)
    [ "$CURRENT_DEFAULT_TARGET" = "$DEFAULT_TARGET" ] ||
        lk_run_detail sudo systemctl set-default "$DEFAULT_TARGET"

    SERVICE_ENABLE+=(
        NetworkManager "Network Manager"
    )

    lk_console_message "Checking root account"
    lk_user_lock_passwd root

    lk_console_message "Checking sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default-arch
    lk_install -m 00440 "$FILE"
    lk_file_replace -f "$LK_BASE/share/sudoers.d/default-arch" "$FILE"

    lk_console_message "Checking default umask"
    FILE=/etc/profile.d/Z90-${LK_PATH_PREFIX}umask.sh
    lk_install -m 00644 "$FILE"
    lk_file_replace -f "$LK_BASE/share/profile.d/umask.sh" "$FILE"

    if [ -d /etc/polkit-1/rules.d ]; then
        lk_console_message "Checking polkit rules"
        FILE=/etc/polkit-1/rules.d/49-wheel.rules
        lk_install -m 00640 "$FILE"
        lk_file_replace \
            -f "$LK_BASE/share/polkit-1/rules.d/default-arch.rules" \
            "$FILE"
    fi

    lk_console_message "Checking kernel parameters"
    unset LK_FILE_REPLACE_NO_CHANGE
    for FILE in default.conf $(lk_is_virtual || lk_echo_args sysrq.conf); do
        TARGET=/etc/sysctl.d/90-${FILE/default/${LK_PATH_PREFIX}default}
        FILE=$LK_BASE/share/sysctl.d/$FILE
        lk_install -m 00644 "$TARGET"
        lk_file_replace -f "$FILE" "$TARGET"
    done
    lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
        sudo sysctl --system

    if lk_pac_installed tlp; then
        lk_console_message "Checking TLP"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/tlp.d/90-${LK_PATH_PREFIX}default.conf
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/tlp.d/default.conf" "$FILE"
        systemctl_mask systemd-rfkill.service
        systemctl_mask systemd-rfkill.socket
        file_delete "/etc/tlp.d/90-${LK_PATH_PREFIX}defaults.conf"
        SERVICE_ENABLE+=(
            NetworkManager-dispatcher "Network Manager dispatcher"
            tlp "TLP"
        )
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(tlp)
    fi

    lk_console_message "Checking console display power management"
    unset LK_FILE_REPLACE_NO_CHANGE
    FILE=/etc/systemd/system/setterm-enable-blanking.service
    lk_install -m 00644 "$FILE"
    lk_file_replace \
        -f "$LK_BASE/share/systemd/setterm-enable-blanking.service" \
        "$FILE"
    SERVICE_ENABLE+=(
        setterm-enable-blanking "setterm blanking"
    )
    lk_is_true LK_FILE_REPLACE_NO_CHANGE || {
        DAEMON_RELOAD=1
        SERVICE_RESTART+=(setterm-enable-blanking)
    }

    ROOT_DEVICE=$(findmnt --list --noheadings --target / --output SOURCE)
    if lk_block_device_is_ssd "$ROOT_DEVICE"; then
        lk_console_message "Checking fstrim"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/systemd/system/fstrim.timer
        lk_install -m 00644 "$FILE"
        lk_file_replace -f "$LK_BASE/share/systemd/fstrim.timer" "$FILE"
        SERVICE_ENABLE+=(
            fstrim.timer "fstrim"
        )
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            DAEMON_RELOAD=1
    fi

    if [ -n "${LK_NTP_SERVER:-}" ]; then
        lk_console_message "Checking NTP"
        unset LK_FILE_REPLACE_NO_CHANGE
        FILE=/etc/ntp.conf
        lk_file_keep_original "$FILE"
        _FILE=$(awk \
            -v "NTP_SERVER=server $LK_NTP_SERVER iburst" \
            -f "$LK_BASE/lib/awk/ntp-set-server.awk" \
            "$FILE")
        lk_file_replace "$FILE" "$_FILE"
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(ntpd)
    fi
    SERVICE_ENABLE+=(
        ntpd "NTP"
    )

    lk_console_message "Checking SSH server"
    unset LK_FILE_REPLACE_NO_CHANGE
    LK_CONF_OPTION_FILE=/etc/ssh/sshd_config
    lk_ssh_set_option PermitRootLogin "no"
    [ ! -s ~/.ssh/authorized_keys ] ||
        lk_ssh_set_option PasswordAuthentication "no"
    lk_ssh_set_option AcceptEnv "LANG LC_*"
    SERVICE_ENABLE+=(
        sshd "SSH server"
    )
    lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
        SERVICE_RESTART+=(sshd)

    SERVICE_ENABLE+=(
        qemu-guest-agent "QEMU Guest Agent"
        lightdm "LightDM"
        cups "CUPS"
    )

    service_apply

    if ! is_bootstrap && lk_pac_installed grub; then
        lk_console_message "Checking boot loader"
        unset LK_FILE_REPLACE_NO_CHANGE
        lk_arch_configure_grub
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            sudo update-grub --install
    fi

    lk_console_blank
    lk_maybe_trace "$LK_BASE/bin/lk-platform-configure.sh" --no-log

    lk_console_blank
    lk_console_log "Checking packages"
    lk_arch_configure_pacman
    [ -z "$LK_PACKAGES_FILE" ] ||
        . "$LK_PACKAGES_FILE"
    . "$LK_BASE/lib/arch/packages.sh"

    lk_console_message "Checking install reasons"
    PAC_EXPLICIT=$(lk_echo_array PAC_PACKAGES AUR_PACKAGES PAC_KEEP | sort -u)
    PAC_MARK_EXPLICIT=($(comm -12 \
        <(lk_echo_array PAC_EXPLICIT) \
        <(lk_pac_installed_not_explicit | sort -u)))
    PAC_UNMARK_EXPLICIT=($(comm -13 \
        <(lk_echo_array PAC_EXPLICIT) \
        <(lk_pac_installed_explicit | sort -u)))
    [ ${#PAC_MARK_EXPLICIT[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asexplicit "${PAC_MARK_EXPLICIT[@]}"
    [ ${#PAC_UNMARK_EXPLICIT[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asdeps "${PAC_UNMARK_EXPLICIT[@]}"

    [ ${#PAC_KEEP[@]} -eq 0 ] ||
        lk_echo_array PAC_KEEP |
        lk_console_list "Not uninstalling:" package packages
    PAC_INSTALL=($(comm -23 \
        <(lk_echo_array PAC_PACKAGES | sort -u) \
        <(lk_pac_installed_list | sort -u)))
    [ ${#PAC_INSTALL[@]} -eq 0 ] ||
        lk_echo_array PAC_INSTALL |
        lk_console_list "Installing:" package packages
    PAC_UPGRADE=($(pacman -Sup --print-format %n))
    [ ${#PAC_UPGRADE[@]} -eq 0 ] ||
        lk_echo_array PAC_UPGRADE |
        lk_console_list "Upgrading:" package packages
    [ ${#PAC_INSTALL[@]}${#PAC_UPGRADE[@]} = 00 ] ||
        lk_tty sudo pacman -Su ${PAC_INSTALL[@]+"${PAC_INSTALL[@]}"}

    REMOVE_MESSAGE=()
    ! PAC_REMOVE=($(pacman -Qdttq)) || [ ${#PAC_REMOVE[@]} -eq 0 ] || {
        lk_echo_array PAC_REMOVE |
            lk_console_list "Orphaned:" package packages
        lk_confirm "Remove the above?" N &&
            REMOVE_MESSAGE+=("orphaned") ||
            PAC_REMOVE=()
    }
    PAC_REJECT=($(comm -12 \
        <(lk_echo_array PAC_REJECT | sort -u) \
        <(lk_pac_installed_list | sort -u)))
    [ ${#PAC_REJECT[@]} -eq 0 ] || {
        REMOVE_MESSAGE+=("blacklisted")
        PAC_REMOVE+=("${PAC_REJECT[@]}")
    }
    [ ${#PAC_REMOVE[@]} -eq 0 ] || {
        lk_console_message \
            "Removing $(lk_implode " and " REMOVE_MESSAGE) packages"
        lk_tty sudo pacman -Rs --noconfirm "${PAC_REMOVE[@]}"
    }

    lk_symlink_bin codium code
    lk_symlink_bin vim vi
    lk_symlink_bin xfce4-terminal xterm

    lk_console_blank
    lk_console_log "Checking installed packages and services"
    SERVICE_ENABLE+=(
        atd "at"
        cronie "cron"
    )

    if lk_pac_installed mariadb; then
        sudo test -d /var/lib/mysql/mysql ||
            sudo mariadb-install-db \
                --user=mysql \
                --basedir=/usr \
                --datadir=/var/lib/mysql
        SERVICE_ENABLE+=(
            mariadb "MariaDB"
        )
    fi

    if lk_pac_installed php; then
        unset LK_FILE_REPLACE_NO_CHANGE
        LK_CONF_OPTION_FILE=/etc/php/php.ini
        PHP_EXT=(
            bcmath
            curl
            exif
            gd
            gettext
            iconv
            imap
            intl
            mysqli
            pdo_sqlite
            soap
            sqlite3
            xmlrpc
            zip
        )
        for EXT in ${PHP_EXT[@]+"${PHP_EXT[@]}"}; do
            lk_php_enable_option extension "$EXT"
        done
        STANDALONE_PHP_EXT=(
            imagick
            memcache.so
            memcached.so
        )
        for EXT in ${STANDALONE_PHP_EXT[@]+"${STANDALONE_PHP_EXT[@]}"}; do
            FILE=/etc/php/conf.d/${EXT%.*}.ini
            [ -f "$FILE" ] || continue
            lk_php_enable_option extension "$EXT" "$FILE"
        done
        if is_desktop; then
            lk_php_set_option error_reporting E_ALL
            lk_php_set_option display_errors On
            lk_php_set_option display_startup_errors On
            lk_php_set_option log_errors Off

            (
                LK_CONF_OPTION_FILE=/etc/php/conf.d/xdebug.ini
                [ -f "$LK_CONF_OPTION_FILE" ] || exit 0
                lk_install -d -m 00777 ~/.xdebug
                lk_php_set_option xdebug.output_dir ~/.xdebug
                # Alternative values: profile, trace
                lk_php_set_option xdebug.mode debug
                lk_php_set_option xdebug.start_with_request trigger
                lk_php_set_option xdebug.profiler_output_name callgrind.out.%H.%R.%u
                lk_php_set_option xdebug.collect_return On
                lk_php_set_option xdebug.trace_output_name trace.%H.%R.%u
                lk_php_enable_option zend_extension xdebug.so
            )
        fi
    fi

    if lk_pac_installed php-fpm apache; then
        lk_install -d -m 00700 -o http -g http /var/cache/php/opcache
        lk_php_set_option opcache.file_cache /var/cache/php/opcache
        lk_php_set_option opcache.validate_permission On
        lk_php_enable_option zend_extension opcache
        if is_desktop; then
            lk_php_set_option max_execution_time 0
            lk_php_set_option opcache.enable Off
        fi
        lk_install -d -m 00775 -o root -g http /var/log/php-fpm
        FILE=/etc/logrotate.d/php-fpm
        lk_install -m 00644 "$FILE"
        lk_file_replace "$FILE" <<"EOF"
/var/log/php-fpm/*.access.log {
    missingok
    sharedscripts
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
    su root root
}
/var/log/php-fpm/*.error.log {
    missingok
    sharedscripts
    postrotate
        /usr/bin/systemctl kill --kill-who=main --signal=SIGUSR1 php-fpm.service 2>/dev/null || true
    endscript
    su http http
}
EOF
        LK_CONF_OPTION_FILE=/etc/php/php-fpm.d/www.conf
        lk_php_set_option pm static
        lk_php_set_option pm.status_path /php-fpm-status
        lk_php_set_option ping.path /php-fpm-ping
        lk_php_set_option access.log '/var/log/php-fpm/php-fpm-$pool.access.log'
        lk_php_set_option access.format '"%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'
        lk_php_set_option catch_workers_output yes
        lk_php_set_option 'php_admin_value[error_log]' '/var/log/php-fpm/php-fpm-$pool.error.log'
        lk_php_set_option 'php_admin_flag[log_errors]' On
        lk_php_set_option 'php_flag[display_errors]' Off
        lk_php_set_option 'php_flag[display_startup_errors]' Off
        if is_desktop; then
            lk_php_set_option pm.max_children 5
            lk_php_set_option pm.max_requests 0
            lk_php_set_option request_terminate_timeout 0
        else
            lk_php_set_option pm.max_children 50
            lk_php_set_option pm.max_requests 10000
            lk_php_set_option request_terminate_timeout 300
        fi
        SERVICE_ENABLE+=(
            php-fpm "PHP-FPM"
        )
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(php-fpm)

        unset LK_FILE_REPLACE_NO_CHANGE
        LK_CONF_OPTION_FILE=/etc/httpd/conf/httpd.conf
        GROUP=$(id -gn)
        lk_install -d -m 00755 -o "$USER" -g "$GROUP" /srv/http/{,localhost/{,html},127.0.0.1}
        [ -e /srv/http/127.0.0.1/html ] ||
            ln -sfT ../localhost/html /srv/http/127.0.0.1/html
        lk_httpd_enable_option LoadModule "alias_module modules/mod_alias.so"
        lk_httpd_enable_option LoadModule "dir_module modules/mod_dir.so"
        lk_httpd_enable_option LoadModule "headers_module modules/mod_headers.so"
        lk_httpd_enable_option LoadModule "info_module modules/mod_info.so"
        lk_httpd_enable_option LoadModule "rewrite_module modules/mod_rewrite.so"
        lk_httpd_enable_option LoadModule "status_module modules/mod_status.so"
        lk_httpd_enable_option LoadModule "vhost_alias_module modules/mod_vhost_alias.so"
        if is_desktop; then
            FILE=/etc/httpd/conf/extra/${LK_PATH_PREFIX}default-dev-arch.conf
            lk_install -m 00644 "$FILE"
            lk_file_replace \
                -f "$LK_BASE/share/apache2/default-dev-arch.conf" \
                "$FILE"
            lk_httpd_enable_option Include "${FILE#/etc/httpd/}"
            lk_httpd_enable_option LoadModule "proxy_module modules/mod_proxy.so"
            lk_httpd_enable_option LoadModule "proxy_fcgi_module modules/mod_proxy_fcgi.so"
            lk_user_in_group http ||
                sudo usermod --append --groups http "$USER"
            lk_user_in_group "$GROUP" http ||
                sudo usermod --append --groups "$GROUP" http
            lk_httpd_remove_option Include conf/extra/httpd-dev-defaults.conf
            file_delete /etc/httpd/conf/extra/httpd-dev-defaults.conf
        fi
        SERVICE_ENABLE+=(
            httpd "Apache"
        )
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(httpd)

        lk_git_provision_repo -s \
            -o "$USER:adm" \
            -n "opcache-gui" \
            https://github.com/lkrms/opcache-gui.git \
            /opt/opcache-gui
    fi

    if lk_pac_installed bluez; then
        unset LK_FILE_REPLACE_NO_CHANGE
        lk_conf_set_option AutoEnable true /etc/bluetooth/main.conf
        SERVICE_ENABLE+=(
            bluetooth "Bluetooth"
        )
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            SERVICE_RESTART+=(bluetooth)
    fi

    if lk_pac_installed libvirt; then
        ! is_desktop ||
            { lk_user_in_group libvirt && lk_user_in_group kvm; } ||
            sudo usermod --append --groups libvirt,kvm "$USER"
        LIBVIRT_USERS=$(lk_get_users_in_group libvirt)
        LIBVIRT_USERS=$([ -z "$LIBVIRT_USERS" ] || id -u $LIBVIRT_USERS)
        LK_CONF_OPTION_FILE=/etc/conf.d/libvirt-guests
        lk_conf_set_option URIS \
            "'default${LIBVIRT_USERS:+$(printf \
                ' qemu:///session?socket=/run/user/%s/libvirt/libvirt-sock' \
                $LIBVIRT_USERS)}'"
        if is_desktop; then
            lk_conf_set_option ON_BOOT ignore
            lk_conf_set_option SHUTDOWN_TIMEOUT 120
            FILE=/etc/qemu/bridge.conf
            lk_install -d -m 00755 "${FILE%/*}"
            lk_install -m 00644 "$FILE"
            lk_file_replace "$FILE" "allow all"
        else
            lk_conf_set_option ON_BOOT start
            lk_conf_set_option SHUTDOWN_TIMEOUT 300
        fi
        lk_conf_set_option ON_SHUTDOWN shutdown
        lk_conf_set_option SYNC_TIME 1
        ! memory_at_least 7 || SERVICE_ENABLE+=(
            libvirtd "libvirt"
            libvirt-guests "libvirt-guests"
        )
    fi

    if lk_pac_installed docker; then
        lk_user_in_group docker ||
            sudo usermod --append --groups docker "$USER"
        ! memory_at_least 7 || SERVICE_ENABLE+=(
            docker "Docker"
        )
    fi

    if lk_pac_installed xfce4-session; then
        lk_symlink "$LK_BASE/lib/xfce4/startxfce4" /usr/local/bin/startxfce4
        SH=$(sudo bash -c 'shopt -s nullglob &&
        a=({/etc/skel*,/home/*}/.config/xfce4/xinitrc) &&
        { [ ${#a[@]} -eq 0 ] || printf "%q\n" "${a[@]}"; }')
        [ -z "$SH" ] ||
            eval "file_delete $SH"
    fi

    service_apply || EXIT_STATUS=$?

    (exit "$EXIT_STATUS") &&
        lk_console_success "Provisioning complete" ||
        lk_console_error -r "Provisioning completed with errors"

    exit
}

#!/bin/bash

# shellcheck disable=SC1090,SC2015,SC2016,SC2031,SC2034,SC2206,SC2207

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
        [[ $1 == *.* ]] || set -- "$1.service"
        [ ! -e "/usr/lib/systemd/system/$1" ] || {
            lk_console_detail "Enabling service:" "${2:-$1}"
            sudo systemctl enable "$1"
        }
    }
    lk_console_blank
else
    function systemctl_enable() {
        ! lk_systemctl_exists "$1" ||
            lk_systemctl_enable_now ${2:+-n "$2"} "$1"
    }
fi

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
    lk_node_service_enabled desktop &&
        DEFAULT_TARGET=graphical.target ||
        DEFAULT_TARGET=multi-user.target
    CURRENT_DEFAULT_TARGET=$(${LK_BOOTSTRAP:+sudo} systemctl get-default)
    [ "$CURRENT_DEFAULT_TARGET" = "$DEFAULT_TARGET" ] ||
        lk_run_detail sudo systemctl set-default "$DEFAULT_TARGET"

    lk_console_message "Checking root account"
    lk_user_lock_passwd root

    lk_console_message "Checking sudo"
    FILE=/etc/sudoers.d/${LK_PATH_PREFIX}default-arch
    lk_install -m 00440 "$FILE"
    lk_file_replace -f "$LK_BASE/share/sudoers.d/default-arch" "$FILE"

    if [ -d /etc/polkit-1/rules.d ]; then
        lk_console_message "Checking polkit rules"
        lk_file_replace \
            -f "$LK_BASE/share/polkit-1/rules.d/default-arch.rules" \
            /etc/polkit-1/rules.d/49-wheel.rules
    fi

    lk_console_message "Checking kernel parameters"
    unset LK_FILE_REPLACE_NO_CHANGE
    for FILE in default.conf $(lk_is_virtual || lk_echo_args sysrq.conf); do
        TARGET=/etc/sysctl.d/90-${FILE/default/${LK_PATH_PREFIX}default}
        FILE=$LK_BASE/share/sysctl.d/$FILE
        lk_file_replace -f "$FILE" "$TARGET"
    done
    lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
        sudo sysctl --system

    if [ -n "${LK_NTP_SERVER:-}" ]; then
        lk_console_message "Checking NTP"
        FILE=/etc/ntp.conf
        lk_file_keep_original "$FILE"
        _FILE=$(awk \
            -v "NTP_SERVER=server $LK_NTP_SERVER iburst" \
            -f "$LK_BASE/lib/awk/ntp-set-server.awk" \
            "$FILE")
        lk_file_replace "$FILE" "$_FILE"
    fi

    lk_console_message "Checking SSH server"
    LK_CONF_OPTION_FILE=/etc/ssh/sshd_config
    lk_ssh_set_option PermitRootLogin "no"
    [ ! -s ~/.ssh/authorized_keys ] ||
        lk_ssh_set_option PasswordAuthentication "no"
    lk_ssh_set_option AcceptEnv "LANG LC_*"

    lk_console_message "Checking essential services"
    systemctl_enable NetworkManager "Network Manager"
    systemctl_enable ntpd "NTP"
    systemctl_enable sshd "SSH server"

    systemctl_enable lightdm "LightDM"
    systemctl_enable cups "CUPS"

    ! lk_is_qemu ||
        systemctl_enable qemu-guest-agent "QEMU Guest Agent"

    if lk_pac_installed grub; then
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
        lk_console_detail_list \
            "Not installed as dependency because of PAC_KEEP:" package packages

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

    lk_console_blank
    lk_console_log "Checking installed packages and services"
    systemctl_enable atd "at"
    systemctl_enable cronie "cron"

    if lk_pac_installed mariadb; then
        sudo test -d /var/lib/mysql/mysql ||
            sudo mariadb-install-db \
                --user=mysql \
                --basedir=/usr \
                --datadir=/var/lib/mysql
        systemctl_enable mariadb "MariaDB"
    fi

    if lk_pac_installed php-fpm; then
        lk_git_provision_repo -s \
            -o "$USER:adm" \
            -n "opcache-gui" \
            https://github.com/lkrms/opcache-gui.git \
            /opt/opcache-gui
    fi

    if ! lk_is_virtual; then

        if lk_node_service_enabled desktop; then

            [ ! -f "/etc/bluetooth/main.conf" ] || {
                lk_conf_set_option AutoEnable "true" /etc/bluetooth/main.conf &&
                    systemctl_enable bluetooth || exit
            }

            LK_CONF_OPTION_FILE=/etc/conf.d/libvirt-guests
            lk_conf_set_option URIS \
                '"default$(for i in /run/user/*/libvirt/libvirt-sock; do [ ! -e "$i" ] || printf " qemu:///session?socket=%s" "$i"; done)"'
            lk_conf_set_option ON_BOOT "ignore"
            lk_conf_set_option ON_SHUTDOWN "shutdown"
            lk_conf_set_option SHUTDOWN_TIMEOUT "300"
            sudo usermod --append --groups libvirt,kvm "$USER"
            [ -e "/etc/qemu/bridge.conf" ] || {
                sudo install -d -m 00755 "/etc/qemu" &&
                    echo "allow all" |
                    sudo tee "/etc/qemu/bridge.conf" >/dev/null || exit
            }
            ! memory_at_least 7 || {
                systemctl_enable libvirtd
                systemctl_enable libvirt-guests
            }

            sudo usermod --append --groups docker "$USER"
            ! memory_at_least 7 ||
                systemctl_enable docker

        fi

    fi

    if lk_node_service_enabled desktop; then

        LK_CONF_OPTION_FILE=/etc/php/php.ini
        for PHP_EXT in bcmath curl exif gd gettext iconv imap intl mysqli pdo_sqlite soap sqlite3 xmlrpc zip; do
            lk_php_enable_option "extension" "$PHP_EXT"
        done
        lk_php_enable_option "zend_extension" "opcache"
        sudo install -d -m 00700 -o "http" -g "http" "/var/cache/php/opcache"
        lk_php_set_option "max_execution_time" "0"
        lk_php_set_option "memory_limit" "128M"
        lk_php_set_option "error_reporting" "E_ALL"
        lk_php_set_option "display_errors" "On"
        lk_php_set_option "display_startup_errors" "On"
        lk_php_set_option "log_errors" "Off"
        lk_php_set_option "opcache.enable" "Off"
        lk_php_set_option "opcache.file_cache" "/var/cache/php/opcache"
        [ ! -f "/etc/php/conf.d/imagick.ini" ] ||
            LK_CONF_OPTION_FILE="/etc/php/conf.d/imagick.ini" \
                lk_php_enable_option "extension" "imagick"
        [ ! -f "/etc/php/conf.d/memcache.ini" ] ||
            LK_CONF_OPTION_FILE="/etc/php/conf.d/memcache.ini" \
                lk_php_enable_option "extension" "memcache.so"
        [ ! -f "/etc/php/conf.d/memcached.ini" ] ||
            LK_CONF_OPTION_FILE="/etc/php/conf.d/memcached.ini" \
                lk_php_enable_option "extension" "memcached.so"
        [ ! -f "/etc/php/conf.d/xdebug.ini" ] || {
            [ ! -d "$HOME/.tmp/cachegrind" ] ||
                rmdir -v "$HOME/.tmp/cachegrind" || true
            [ ! -d "$HOME/.tmp/trace" ] ||
                rmdir -v "$HOME/.tmp/trace" || true
            install -d -m 00777 "$HOME/.xdebug"
            LK_CONF_OPTION_FILE="/etc/php/conf.d/xdebug.ini"
            grep -q '^xdebug\.mode=' "$LK_CONF_OPTION_FILE" ||
                [ ! -e "$LK_CONF_OPTION_FILE.orig" ] || {
                lk_file_backup "$LK_CONF_OPTION_FILE" &&
                    sudo mv -fv "$LK_CONF_OPTION_FILE.orig" "$LK_CONF_OPTION_FILE"
            }
            lk_php_enable_option "zend_extension" "xdebug.so"
            # Alternatives: profile, trace
            lk_php_set_option "xdebug.mode" "debug"
            lk_php_set_option "xdebug.start_with_request" "trigger"
            lk_php_set_option "xdebug.output_dir" "$HOME/.xdebug"
            lk_php_set_option "xdebug.profiler_output_name" "callgrind.out.%H.%R.%u"
            lk_php_set_option "xdebug.collect_return" "On"
            lk_php_set_option "xdebug.trace_output_name" "trace.%H.%R.%u"
        }
        if [ -f /etc/php/php-fpm.d/www.conf ]; then
            # Reverse a previous change that broke logrotate
            sudo install -d -m 00755 -o root -g root /var/log/httpd
            sudo install -d -m 00775 -o root -g http /var/log/php-fpm
            FILE=/etc/logrotate.d/php-fpm
            [ -e "$FILE" ] ||
                sudo install -m 00644 /dev/null "$FILE"
            lk_file_replace "$FILE" "\
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
}"
            LK_CONF_OPTION_FILE=/etc/php/php-fpm.d/www.conf
            lk_php_set_option "pm" "static"
            lk_php_set_option "pm.max_children" "4"
            lk_php_set_option "pm.max_requests" "0"
            lk_php_set_option "request_terminate_timeout" "0"
            lk_php_set_option "pm.status_path" "/php-fpm-status"
            lk_php_set_option "ping.path" "/php-fpm-ping"
            lk_php_set_option "access.log" '/var/log/php-fpm/php-fpm-$pool.access.log'
            lk_php_set_option "access.format" '"%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'
            lk_php_set_option "catch_workers_output" "yes"
            lk_php_set_option "php_admin_value[memory_limit]" "128M"
            lk_php_set_option "php_admin_value[error_log]" '/var/log/php-fpm/php-fpm-$pool.error.log'
            lk_php_set_option "php_admin_flag[log_errors]" "On"
            lk_php_set_option "php_flag[display_errors]" "Off"
            lk_php_set_option "php_flag[display_startup_errors]" "Off"
            if ! is_bootstrap; then
                OLD_LOGS=(/var/log/httpd/php-fpm-*.log)
                if [ ${#OLD_LOGS[@]} -gt 0 ] && [ -z "$(ls -A /var/log/php-fpm)" ]; then
                    lk_systemctl_stop php-fpm
                    sudo mv -v "${OLD_LOGS[@]}" /var/log/php-fpm/
                fi
            fi
        fi
        ! memory_at_least 7 ||
            systemctl_enable php-fpm

        LK_CONF_OPTION_FILE="/etc/httpd/conf/httpd.conf"
        sudo install -d -m 00755 -o "$USER" -g "$(id -gn)" "/srv/http"
        mkdir -p "/srv/http/localhost/html" "/srv/http/127.0.0.1"
        [ -e "/srv/http/127.0.0.1/html" ] ||
            ln -sfT "../localhost/html" "/srv/http/127.0.0.1/html"
        lk_symlink "$LK_BASE/etc/httpd/dev-defaults.conf" "/etc/httpd/conf/extra/httpd-dev-defaults.conf"
        lk_httpd_enable_option Include "conf/extra/httpd-dev-defaults.conf"
        lk_httpd_enable_option LoadModule "alias_module modules/mod_alias.so"
        lk_httpd_enable_option LoadModule "dir_module modules/mod_dir.so"
        lk_httpd_enable_option LoadModule "headers_module modules/mod_headers.so"
        lk_httpd_enable_option LoadModule "info_module modules/mod_info.so"
        lk_httpd_enable_option LoadModule "proxy_fcgi_module modules/mod_proxy_fcgi.so"
        lk_httpd_enable_option LoadModule "proxy_module modules/mod_proxy.so"
        lk_httpd_enable_option LoadModule "rewrite_module modules/mod_rewrite.so"
        lk_httpd_enable_option LoadModule "status_module modules/mod_status.so"
        lk_httpd_enable_option LoadModule "vhost_alias_module modules/mod_vhost_alias.so"
        sudo usermod --append --groups "http" "$USER"
        sudo usermod --append --groups "$(id -gn)" "http"
        ! memory_at_least 7 ||
            systemctl_enable httpd

    fi

    lk_console_success "Provisioning complete"

    exit
}

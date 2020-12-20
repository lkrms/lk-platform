#!/bin/bash

# shellcheck disable=SC1090,SC2016,SC2031,SC2034,SC2207

lk_bin_depth=1 include=provision,linux,arch . lk-bash-load.sh || exit

shopt -s nullglob

lk_assert_not_root
lk_assert_is_arch

lk_log_output

{
    LK_SUDO=1

    if lk_sudo_offer_nopasswd; then
        lk_console_message "Checking root account"
        PASSWORD_STATUS=$(sudo passwd -S root | cut -d' ' -f2)
        [ "$PASSWORD_STATUS" = L ] || {
            lk_console_detail "Locking password"
            sudo passwd -l root
        }

        ! sudo test -d /etc/polkit-1/rules.d || {
            lk_console_message "Checking polkit rules"
            lk_file_replace /etc/polkit-1/rules.d/49-wheel.rules "\
// Authorize all actions by users in 'wheel' without authentication
polkit.addRule(function (action, subject) {
    if (subject.isInGroup(\"wheel\")) {
        return polkit.Result.YES;
    }
});"
        }
    fi

    export LK_PACKAGES_FILE=${1:-${LK_PACKAGES_FILE:-}}
    if [ -n "$LK_PACKAGES_FILE" ]; then
        if [ ! -f "$LK_PACKAGES_FILE" ]; then
            case "$LK_PACKAGES_FILE" in
            /*/*)
                CONTRIB_PACKAGES_FILE=${LK_PACKAGES_FILE:1}
                ;;
            */*)
                CONTRIB_PACKAGES_FILE=$LK_PACKAGES_FILE
                ;;
            *)
                lk_die "$1: file not found"
                ;;
            esac
            LK_PACKAGES_FILE=$LK_BASE/$CONTRIB_PACKAGES_FILE
        fi
        LK_PACKAGES_FILE=$(realpath "$LK_PACKAGES_FILE")
        . "$LK_PACKAGES_FILE"
    fi
    . "$LK_BASE/lib/arch/packages.sh"

    "$LK_BASE/bin/lk-platform-configure.sh" --no-log

    PAC_TO_REMOVE=($(comm -12 \
        <(pacman -Qq | sort -u) \
        <(lk_echo_array PAC_REMOVE | sort -u)))
    [ ${#PAC_TO_REMOVE[@]} -eq 0 ] || {
        lk_console_message "Removing packages"
        lk_tty sudo pacman -R --noconfirm "${PAC_TO_REMOVE[@]}"
    }

    lk_console_message "Checking install reasons"
    PAC_EXPLICIT=($(lk_echo_array PACMAN_PACKAGES AUR_PACKAGES PAC_KEEP |
        sort -u))
    PAC_TO_MARK_ASDEPS=($(comm -23 \
        <(pacman -Qeq | sort -u) \
        <(lk_echo_array PAC_EXPLICIT)))
    PAC_TO_MARK_EXPLICIT=($(comm -12 \
        <(pacman -Qdq | sort -u) \
        <(lk_echo_array PAC_EXPLICIT)))
    [ ${#PAC_TO_MARK_ASDEPS[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asdeps "${PAC_TO_MARK_ASDEPS[@]}"
    [ ${#PAC_TO_MARK_EXPLICIT[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asexplicit "${PAC_TO_MARK_EXPLICIT[@]}"

    ! PAC_TO_PURGE=($(pacman -Qdttq)) ||
        [ ${#PAC_TO_PURGE[@]} -eq 0 ] || {
        lk_echo_array PAC_TO_PURGE |
            lk_console_list \
                "Installed but no longer required:" package packages
        ! lk_confirm "Remove the above?" N ||
            lk_tty sudo pacman -Rs --noconfirm "${PAC_TO_PURGE[@]}"
    }

    lk_console_message "Upgrading installed packages"
    lk_tty sudo pacman -Syu

    PAC_TO_INSTALL=($(comm -13 \
        <(pacman -Qeq | sort -u) \
        <(lk_echo_array PACMAN_PACKAGES | sort -u)))
    [ ${#PAC_TO_INSTALL[@]} -eq 0 ] || {
        lk_console_message "Installing new packages from repo"
        lk_tty sudo pacman -S "${PAC_TO_INSTALL[@]}"
    }

    if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
        lk_command_exists yay || {
            lk_console_message "Installing yay to manage AUR packages"
            eval "$YAY_SCRIPT"
        }
        AUR_TO_INSTALL=($(comm -13 \
            <(pacman -Qeq | sort -u) \
            <(lk_echo_array AUR_PACKAGES | sort -u)))
        [ ${#AUR_TO_INSTALL[@]} -eq 0 ] || {
            lk_console_message "Installing new packages from AUR"
            lk_tty yay -Sy --aur "${AUR_TO_INSTALL[@]}"
        }
        lk_console_message "Upgrading installed AUR packages"
        lk_tty yay -Syu --aur
    fi

    PAC_KEPT=($(comm -12 \
        <(pacman -Qeq | sort -u) \
        <(lk_echo_array PAC_KEEP | sort -u)))
    [ ${#PAC_KEPT[@]} -eq 0 ] ||
        lk_echo_array PAC_KEPT |
        lk_console_list "Retained because of PAC_KEEP:" package packages

    [[ ${LK_PACKAGES_FILE##*/} != *-dev* ]] ||
        [ -e /opt/opcache-gui ] || {
        lk_console_message "Installing opcache-gui"
        sudo install -d -m 00755 -o "$USER" -g "$(id -gn)" /opt/opcache-gui &&
            git clone https://github.com/lkrms/opcache-gui.git \
                /opt/opcache-gui
    }

    MINIMAL=0
    MEMORY=$(lk_system_memory)
    [ "$MEMORY" -ge 7 ] || {
        lk_console_warning "Low-memory system detected"
        MINIMAL=1
    }

    if ! lk_command_exists code &&
        TARGET=$(type -P codium); then
        LK_VERBOSE=${LK_VERBOSE-1} \
            lk_symlink "$TARGET" /usr/local/bin/code
    fi

    ###

    LK_CONF_OPTION_FILE=/etc/ssh/sshd_config
    lk_ssh_set_option PasswordAuthentication "no"
    lk_ssh_set_option AcceptEnv "LANG LC_*"
    lk_systemctl_enable sshd

    lk_systemctl_enable atd

    lk_systemctl_enable cronie

    lk_systemctl_enable ntpd

    lk_systemctl_enable cups

    if ! lk_is_virtual; then
        lk_console_message "Checking kernel parameters"
        lk_file_replace /etc/sysctl.d/90-sysrq.conf "\
# Enable Alt+SysRq shortcuts (e.g. for REISUB)
kernel.sysrq = 1"
        lk_is_true LK_FILE_REPLACE_NO_CHANGE ||
            sudo sysctl --system

        [ ! -f "/etc/bluetooth/main.conf" ] || {
            lk_conf_set_option AutoEnable "true" /etc/bluetooth/main.conf &&
                lk_systemctl_enable bluetooth || exit
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
        lk_is_true MINIMAL || {
            lk_systemctl_enable libvirtd
            lk_systemctl_enable libvirt-guests
        }

        sudo usermod --append --groups docker "$USER"
        lk_is_true MINIMAL || lk_systemctl_enable docker
    fi

    sudo test -d "/var/lib/mysql/mysql" ||
        sudo mariadb-install-db --user="mysql" --basedir="/usr" --datadir="/var/lib/mysql"
    lk_is_true MINIMAL || lk_systemctl_enable mariadb

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
        OLD_LOGS=(/var/log/httpd/php-fpm-*.log)
        if [ ${#OLD_LOGS[@]} -gt 0 ] && [ -z "$(ls -A /var/log/php-fpm)" ]; then
            lk_systemctl_stop php-fpm
            sudo mv -v "${OLD_LOGS[@]}" /var/log/php-fpm/
        fi
    fi
    lk_is_true MINIMAL || lk_systemctl_enable php-fpm

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
    lk_is_true MINIMAL || lk_systemctl_enable httpd

    exit
}

#!/bin/bash
# shellcheck disable=SC1090,SC2016,SC2031,SC2034,SC2207

lk_bin_depth=1 include=provision,linux,arch,httpd,php . lk-bash-load.sh || exit

lk_assert_not_root
lk_assert_is_arch

lk_log_output

{
    if lk_sudo_offer_nopasswd; then
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

    ! LK_PACKAGES=$(pacman -Slq | grep -- '-lk$') || {
        PAC_REPLACE=($(comm -12 \
            <(lk_echo_array LK_PACKAGES | sed 's/-lk$//' | sort -u) \
            <(lk_echo_array PACMAN_PACKAGES | sort -u)))
        [ ${#PAC_REPLACE[@]} -eq 0 ] || {
            PACMAN_PACKAGES=($(comm -13 \
                <(lk_echo_array PAC_REPLACE | sort -u) \
                <(lk_echo_array PACMAN_PACKAGES | sort -u)))
            PACMAN_PACKAGES+=("${PAC_REPLACE[@]/%/-lk}")
        }
    }

    "$LK_BASE/bin/lk-platform-configure-system.sh" --no-log

    PAC_TO_REMOVE=($(comm -12 <(pacman -Qq | sort | uniq) <(lk_echo_array PAC_REMOVE | sort | uniq)))
    [ ${#PAC_TO_REMOVE[@]} -eq 0 ] || {
        lk_console_message "Removing packages"
        lk_tty sudo pacman -R --noconfirm "${PAC_TO_REMOVE[@]}"
    }

    lk_console_message "Checking install reasons"
    PAC_EXPLICIT=($(lk_echo_args "${PACMAN_PACKAGES[@]}" "${AUR_PACKAGES[@]}" ${PAC_KEEP[@]+"${PAC_KEEP[@]}"} | sort | uniq))
    PAC_TO_MARK_ASDEPS=($(comm -23 <(pacman -Qeq | sort | uniq) <(lk_echo_array PAC_EXPLICIT)))
    PAC_TO_MARK_EXPLICIT=($(comm -12 <(pacman -Qdq | sort | uniq) <(lk_echo_array PAC_EXPLICIT)))
    [ ${#PAC_TO_MARK_ASDEPS[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asdeps "${PAC_TO_MARK_ASDEPS[@]}"
    [ ${#PAC_TO_MARK_EXPLICIT[@]} -eq 0 ] ||
        lk_tty sudo pacman -D --asexplicit "${PAC_TO_MARK_EXPLICIT[@]}"

    ! PAC_TO_PURGE=($(pacman -Qdttq)) ||
        [ ${#PAC_TO_PURGE[@]} -eq 0 ] ||
        {
            lk_echo_array PAC_TO_PURGE |
                lk_console_list "Installed but no longer required:" package packages
            ! lk_confirm "Remove the above?" N ||
                lk_tty sudo pacman -R --noconfirm "${PAC_TO_PURGE[@]}"
        }

    lk_console_message "Upgrading installed packages"
    lk_pacman_add_repo ${CUSTOM_REPOS[@]+"${CUSTOM_REPOS[@]}"}
    lk_tty sudo pacman -Syu

    PAC_TO_INSTALL=($(comm -13 <(pacman -Qeq | sort | uniq) <(lk_echo_array PACMAN_PACKAGES | sort | uniq)))
    [ ${#PAC_TO_INSTALL[@]} -eq 0 ] || {
        lk_console_message "Installing new packages from repo"
        lk_tty sudo pacman -S "${PAC_TO_INSTALL[@]}"
    }

    if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
        lk_command_exists yay || {
            lk_console_message "Installing yay to manage AUR packages"
            eval "$YAY_SCRIPT"
        }
        AUR_TO_INSTALL=($(comm -13 <(pacman -Qeq | sort | uniq) <(lk_echo_array AUR_PACKAGES | sort | uniq)))
        [ ${#AUR_TO_INSTALL[@]} -eq 0 ] || {
            lk_console_message "Installing new packages from AUR"
            lk_tty yay -Sy --aur "${AUR_TO_INSTALL[@]}"
        }
        lk_console_message "Upgrading installed AUR packages"
        lk_tty yay -Syu --aur
    fi

    PAC_KEPT=($(comm -12 <(pacman -Qeq | sort | uniq) <(lk_echo_array PAC_KEEP | sort | uniq)))
    [ ${#PAC_KEPT[@]} -eq 0 ] ||
        lk_echo_array PAC_KEPT |
        lk_console_list "Marked 'explicitly installed' because of PAC_KEEP:" package packages

    [ -e "/opt/opcache-gui" ] || {
        lk_console_message "Installing opcache-gui"
        sudo install -d -m 00755 -o "$USER" -g "$(id -gn)" "/opt/opcache-gui" &&
            git clone "https://github.com/lkrms/opcache-gui.git" \
                "/opt/opcache-gui" || exit
    }

    MINIMAL=0
    [ "$(free -g | grep -Eo "[0-9]+" | head -n1)" -ge 15 ] || MINIMAL=1

    LK_SUDO=1

    FILE="/etc/sysctl.d/90-sysrq.conf"
    [ -e "$FILE" ] || {
        cat <<EOF | sudo tee "$FILE" >/dev/null
# Enable Alt+SysRq shortcuts (e.g. for REISUB)
# See https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html
kernel.sysrq = 1
EOF
        sudo sysctl --system
    }

    # TODO: add the following above the relevant pam_nologin.so lines in /etc/pam.d/system-login:
    #
    # auth [success=1 default=ignore] pam_succeed_if.so quiet user ingroup wheel
    # account [success=1 default=ignore] pam_succeed_if.so quiet user ingroup wheel
    lk_apply_setting "/etc/ssh/sshd_config" "PasswordAuthentication" "no" " " "#" " "
    lk_apply_setting "/etc/ssh/sshd_config" "AcceptEnv" "LANG LC_*" " " "#" " "
    lk_systemctl_enable sshd

    lk_systemctl_enable atd

    lk_systemctl_enable cronie

    lk_systemctl_enable ntpd

    lk_systemctl_enable org.cups.cupsd

    if ! lk_is_virtual; then
        [ ! -f "/etc/bluetooth/main.conf" ] || {
            lk_apply_setting "/etc/bluetooth/main.conf" "AutoEnable" "true" "=" "#" &&
                lk_systemctl_enable bluetooth || exit
        }

        lk_apply_setting "/etc/conf.d/libvirt-guests" "URIS" \
            '"default$(for i in /run/user/*/libvirt/libvirt-sock; do [ ! -e "$i" ] || printf " qemu:///session?socket=%s" "$i"; done)"' "=" "#"
        lk_apply_setting "/etc/conf.d/libvirt-guests" "ON_BOOT" "ignore" "=" "#"
        lk_apply_setting "/etc/conf.d/libvirt-guests" "ON_SHUTDOWN" "shutdown" "=" "#"
        lk_apply_setting "/etc/conf.d/libvirt-guests" "SHUTDOWN_TIMEOUT" "300" "=" "#"
        sudo usermod --append --groups libvirt,kvm "$USER"
        [ -e "/etc/qemu/bridge.conf" ] || {
            sudo install -d -m 00755 "/etc/qemu" &&
                echo "allow all" |
                sudo tee "/etc/qemu/bridge.conf" >/dev/null || exit
        }
        lk_is_true "$MINIMAL" || lk_systemctl_enable libvirtd libvirt-guests

        sudo usermod --append --groups docker "$USER"
        lk_is_true "$MINIMAL" || lk_systemctl_enable docker
    fi

    sudo test -d "/var/lib/mysql/mysql" ||
        sudo mariadb-install-db --user="mysql" --basedir="/usr" --datadir="/var/lib/mysql"
    lk_is_true "$MINIMAL" || lk_systemctl_enable mysqld

    PHP_INI_FILE=/etc/php/php.ini
    for PHP_EXT in bcmath curl exif gd gettext iconv imap intl mysqli pdo_sqlite soap sqlite3 xmlrpc zip; do
        lk_enable_php_entry "extension=$PHP_EXT"
    done
    lk_enable_php_entry "zend_extension=opcache"
    sudo install -d -m 00700 -o "http" -g "http" "/var/cache/php/opcache"
    lk_apply_php_setting "max_execution_time" "0"
    lk_apply_php_setting "memory_limit" "128M"
    lk_apply_php_setting "error_reporting" "E_ALL"
    lk_apply_php_setting "display_errors" "On"
    lk_apply_php_setting "display_startup_errors" "On"
    lk_apply_php_setting "log_errors" "Off"
    lk_apply_php_setting "opcache.enable" "Off"
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
        install -d -m 00777 "$HOME/.tmp/cachegrind"
        install -d -m 00777 "$HOME/.tmp/trace"
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
        lk_apply_php_setting "xdebug.collect_vars" "On"
        lk_apply_php_setting "xdebug.trace_output_dir" "$HOME/.tmp/trace"
        lk_apply_php_setting "xdebug.trace_output_name" "trace.%H.%R.%u"
    }
    [ ! -f "/etc/php/php-fpm.d/www.conf" ] ||
        {
            sudo install -d -m 00775 -o "root" -g "http" "/var/log/httpd"
            PHP_INI_FILE="/etc/php/php-fpm.d/www.conf"
            lk_apply_php_setting "pm" "static"
            lk_apply_php_setting "pm.max_children" "4"
            lk_apply_php_setting "pm.max_requests" "0"
            lk_apply_php_setting "request_terminate_timeout" "0"
            lk_apply_php_setting "pm.status_path" "/php-fpm-status"
            lk_apply_php_setting "ping.path" "/php-fpm-ping"
            lk_apply_php_setting "access.log" '/var/log/httpd/php-fpm-$pool.access.log'
            lk_apply_php_setting "access.format" '"%{REMOTE_ADDR}e - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"'
            lk_apply_php_setting "catch_workers_output" "yes"
            lk_apply_php_setting "php_admin_value[memory_limit]" "128M"
            lk_apply_php_setting "php_admin_value[error_log]" '/var/log/httpd/php-fpm-$pool.error.log'
            lk_apply_php_setting "php_admin_flag[log_errors]" "On"
            lk_apply_php_setting "php_flag[display_errors]" "Off"
            lk_apply_php_setting "php_flag[display_startup_errors]" "Off"
        }
    lk_is_true "$MINIMAL" || lk_systemctl_enable php-fpm

    HTTPD_CONF_FILE="/etc/httpd/conf/httpd.conf"
    sudo install -d -m 00755 -o "$USER" -g "$(id -gn)" "/srv/http"
    mkdir -p "/srv/http/localhost/html" "/srv/http/127.0.0.1"
    [ -e "/srv/http/127.0.0.1/html" ] ||
        ln -sfT "../localhost/html" "/srv/http/127.0.0.1/html"
    lk_safe_symlink "$LK_BASE/etc/httpd/dev-defaults.conf" "/etc/httpd/conf/extra/httpd-dev-defaults.conf"
    lk_enable_httpd_entry "Include conf/extra/httpd-dev-defaults.conf"
    lk_enable_httpd_entry "LoadModule alias_module modules/mod_alias.so"
    lk_enable_httpd_entry "LoadModule dir_module modules/mod_dir.so"
    lk_enable_httpd_entry "LoadModule headers_module modules/mod_headers.so"
    lk_enable_httpd_entry "LoadModule info_module modules/mod_info.so"
    lk_enable_httpd_entry "LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so"
    lk_enable_httpd_entry "LoadModule proxy_module modules/mod_proxy.so"
    lk_enable_httpd_entry "LoadModule rewrite_module modules/mod_rewrite.so"
    lk_enable_httpd_entry "LoadModule status_module modules/mod_status.so"
    lk_enable_httpd_entry "LoadModule vhost_alias_module modules/mod_vhost_alias.so"
    sudo usermod --append --groups "http" "$USER"
    sudo usermod --append --groups "$(id -gn)" "http"
    lk_is_true "$MINIMAL" || lk_systemctl_enable httpd

    unset LK_SUDO

    exit
}

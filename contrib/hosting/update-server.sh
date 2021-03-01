#!/bin/bash

# shellcheck disable=SC1091,SC2015,SC2029,SC2034

include='' . lk-bash-load.sh || exit

lk_log_output

{
    function update-server() {

        function update-wp() {
            local CRONTAB DISABLE_WP_CRON
            cd "$1" &&
                . /opt/lk-platform/lib/bash/rc.sh || return
            lk_console_item "Checking WordPress at" "$1"
            if CRONTAB=$(crontab -l 2>/dev/null | grep -F "$1/wp-cron.php") &&
                DISABLE_WP_CRON=$(lk_wp \
                    config get DISABLE_WP_CRON --type=constant) &&
                lk_is_true DISABLE_WP_CRON; then
                lk_console_detail \
                    "WP-Cron appears to be configured correctly"
                lk_console_detail \
                    "crontab command:" $'\n'"$CRONTAB"
            else
                lk_console_detail "WP-Cron does not appear in crontab"
                lk_wp_enable_system_cron
            fi
        }

        local OWNER

        cd /opt/lk-platform 2>/dev/null ||
            cd /opt/*-platform ||
            return

        chown -c :adm . &&
            chmod -c 02775 . ||
            return

        { git remote set-url origin "https://github.com/lkrms/lk-platform.git" ||
            git remote add origin "https://github.com/lkrms/lk-platform.git"; } &&
            git fetch origin &&
            git checkout "$1" &&
            git branch --set-upstream-to "origin/$1" &&
            git merge ||
            return

        ./bin/lk-platform-configure.sh "${@:2}" --set LK_PLATFORM_BRANCH="$1" &&
            . /opt/lk-platform/lib/bash/rc.sh &&
            lk_include hosting &&
            lk_hosting_configure_backup

        shopt -s nullglob
        for WP in /srv/www/{*,*/*}/public_html/wp-config.php; do
            WP=${WP%/wp-config.php}
            OWNER=$(lk_file_owner "$WP") || return
            sudo -Hu "$OWNER" \
                bash -c "$(declare -f update-wp); update-wp \"\$@\"" bash "$WP"
        done

    }

    ARGS=()
    while [ "${1:-}" = --set ]; do
        ARGS+=("${@:1:2}")
        shift 2
    done

    FAILED=()
    i=0
    while [ $# -gt 0 ]; do

        ! ((i++)) || lk_console_blank
        lk_console_item "Updating" "$1"

        ssh "$1" "sudo -H bash -c$(printf ' %q' \
            "$(declare -f update-server); update-server \"\$@\"" \
            bash \
            "${UPDATE_SERVER_BRANCH:-master}" \
            ${ARGS[@]+"${ARGS[@]}"})" || {
            FAILED+=("$1")
            lk_console_error "Update failed (exit status $?):" "$1"
            [ $# -gt 1 ] && lk_confirm "Continue?" Y || break
        }

        shift

    done

    lk_console_blank

    if [ ${#FAILED[@]} -gt 0 ]; then
        lk_console_error "${#FAILED[@]} of $i $(lk_maybe_plural \
            "$i" server servers) failed to update:" $'\n'"$(lk_echo_array FAILED)"
    else
        lk_console_success \
            "$i $(lk_maybe_plural "$i" server servers) updated successfully"
    fi

    exit
}

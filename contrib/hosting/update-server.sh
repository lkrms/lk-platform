#!/bin/bash

. lk-bash-load.sh || exit

lk_log_start

{
    function keep-alive() {
        local OUT_FILE
        # To make the running script resistant to broken connections (SIGHUP),
        # Ctrl+C (SIGINT) and kill signals (SIGTERM):
        # 0. Invoke Bash with SIGHUP, SIGINT and SIGTERM already ignored
        #    (otherwise child processes will be able to receive them)
        # 1. Copy stdout and stderr to FD 6 and FD 7
        # 2. Redirect stdout and stderr to OUT_FILE
        # 3. Redirect stdin from /dev/null
        # 4. Run `tail -f OUT_FILE` in the background to display the script's
        #    output on FD 6 without tying it to a possibly fragile TTY
        OUT_FILE=$(mktemp -- \
            ~/update-server.sh-keep-alive.nohup.out.XXXXXXXXXX) &&
            echo "Redirecting output to $OUT_FILE" >&2 &&
            exec 6>&1 7>&2 8>"$OUT_FILE" &&
            exec >&8 2>&1 </dev/null || return
        (trap - SIGHUP SIGINT SIGTERM &&
            exec tail -fn+1 "$OUT_FILE") >&6 2>&7 &
        trap "kill $!" EXIT
    }

    # update-server BRANCH [--set SETTING]...
    function update-server() {
        function update-wp() {
            local CRONTAB DISABLE_WP_CRON
            cd "$1" &&
                . /opt/lk-platform/lib/bash/rc.sh || return
            lk_console_item "Checking WordPress at" "$1"
            if CRONTAB=$(crontab -l 2>/dev/null | grep -F "$(printf \
                'wp --path=%q cron event run --due-now' "$1")" |
                grep -F _LK_LOG_FILE) &&
                DISABLE_WP_CRON=$(lk_wp \
                    config get DISABLE_WP_CRON --type=constant) &&
                lk_is_true DISABLE_WP_CRON; then
                lk_console_detail \
                    "WP-Cron appears to be configured correctly"
                lk_console_detail \
                    "crontab command:" $'\n'"$CRONTAB"
            else
                lk_console_detail "WP-Cron: valid job not found in crontab"
                lk_wp_enable_system_cron
            fi
        }

        set -uo pipefail

        local INSTALL KEYS_FILE NO_CERTBOT WP OWNER STATUS=0

        cd /opt/lk-platform 2>/dev/null ||
            cd /opt/*-platform ||
            return

        chown -c :adm . &&
            chmod -c 02775 . ||
            return

        (IFS= && umask 002 &&
            # Remove every remote that isn't origin
            { git remote | grep -Fxv origin | tr '\n' '\0' |
                xargs -0 -n1 -r git remote remove ||
                [ "${PIPESTATUS[*]}" = 0100 ]; } &&
            # Add origin or update its URL
            if git remote | grep -Fx origin >/dev/null; then
                git config remote.origin.url | grep -Fx "$2" >/dev/null ||
                    git remote set-url origin "$2"
            else
                git remote add origin "$2"
            fi &&
            # Retrieve latest commits from origin
            git fetch --prune origin &&
            # Stash local changes
            { git stash --include-untracked ||
                { git config user.name "$USER" &&
                    git config user.email "$USER@$(hostname -f)" &&
                    git stash --include-untracked; }; } &&
            if git rev-parse --verify --abbrev-ref HEAD |
                grep -Fx "$1" >/dev/null; then
                # If the branch is already checked out, merge upstream changes
                git merge --ff-only "origin/$1" ||
                    git reset --hard "origin/$1"
            elif git for-each-ref --format="%(refname:short)" refs/heads |
                grep -Fx "$1" >/dev/null; then
                # If the branch exists but isn't checked out, merge upstream
                # changes, then switch
                { git merge-base --is-ancestor "$1" "origin/$1" &&
                    git fetch . "origin/$1:$1" ||
                    git branch -f "$1" "origin/$1"; } &&
                    git checkout "$1"
            else
                # Otherwise, create a new branch from origin/<branch>
                git checkout -b "$1" --track "origin/$1"
            fi &&
            # Set remote-tracking branch to origin/<branch> if needed
            { git rev-parse --verify --abbrev-ref "@{upstream}" 2>/dev/null |
                grep -Fx "origin/$1" >/dev/null ||
                git branch --set-upstream-to "origin/$1"; }) || return

        . ./lib/bash/rc.sh || return

        # Install icdiff if it's not already installed
        INSTALL=$(lk_dpkg_not_installed_list icdiff) || return
        [ -z "$INSTALL" ] ||
            lk_apt_install $INSTALL || return

        shopt -s nullglob

        [ -z "${3:+1}" ] ||
            ! KEYS_FILE=$(lk_first_existing \
                /etc/skel.*/.ssh/{authorized_keys_*,authorized_keys}) ||
            lk_file_replace -m "$KEYS_FILE" "$3" || return

        ./bin/lk-provision-hosting.sh \
            "${@:4}" --set LK_PLATFORM_BRANCH="$1" || return

        lk_console_message "Checking TLS certificates"
        local IFS=$'\n'
        NO_CERTBOT=($(comm -13 \
            <(lk_certbot_list_certificates 2>/dev/null |
                awk -F$'\t' -v "now=$(lk_date "%Y-%m-%d %H:%M:%S%z")" \
                    '$3 > now {print $2}' | sort -u) \
            <(lk_hosting_site_list -e |
                awk -F$'\t' '$11 == "N" {print $10}' | sort -u))) || return
        IFS=,
        [ -z "${NO_CERTBOT+1}" ] ||
            for DOMAINS in "${NO_CERTBOT[@]}"; do
                lk_console_detail \
                    "Requesting TLS certificate:" "${DOMAINS//,/ }"
                lk_certbot_install $DOMAINS ||
                    lk_console_error -r \
                        "TLS certificate not obtained" || STATUS=$?
            done
        unset IFS

        for WP in /srv/www/{*,*/*}/public_html/wp-config.php; do
            WP=${WP%/wp-config.php}
            OWNER=$(stat -c '%U' "$WP") &&
                runuser -u "$OWNER" -- bash -c "$(
                    declare -f update-wp
                    printf '%q %q\n' update-wp "$WP"
                )" || STATUS=$?
        done

        return "$STATUS"
    }

    function do-update-server() {
        local STATUS=0
        keep-alive || return
        update-server "$@" || STATUS=$?
        echo "update-server exit status: $STATUS" >&2
        return "$STATUS"
    }

    ARGS=()
    while [[ ${1-} =~ ^(-[saru]|--(set|add|remove|unset))$ ]]; do
        SHIFT=2
        [[ ${2-} == *=* ]] || [[ $1 =~ ^--?u ]] ||
            ((SHIFT++))
        ARGS+=("${@:1:SHIFT}")
        shift "$SHIFT"
    done

    COMMAND=(sudo -HE bash -c "$(lk_quote_args "$(
        declare -f keep-alive update-server do-update-server
        lk_quote_args trap "" SIGHUP SIGINT SIGTERM
        lk_quote_args set -m
        lk_quote_args do-update-server \
            "${UPDATE_SERVER_BRANCH:-master}" \
            "${UPDATE_SERVER_REPO:-https://github.com/lkrms/lk-platform.git}" \
            "${UPDATE_SERVER_HOSTING_KEYS-}" \
            ${ARGS[@]+"${ARGS[@]}"}
    ) & wait \$! 2>/dev/null")")

    FAILED=()
    i=0
    while [ $# -gt 0 ]; do

        ! ((i++)) || lk_console_blank
        lk_console_item "Updating" "$1"

        trap "" SIGHUP SIGINT SIGTERM

        ssh -o ControlPath=none -t "$1" LK_VERBOSE=${LK_VERBOSE-1} "${COMMAND[@]}" || {
            lk_console_error "Update failed (exit status $?):" "$1"
            FAILED+=("$1")
        }

        trap - SIGHUP SIGINT SIGTERM
        [ $# -gt 1 ] && lk_confirm "Continue?" Y || break

        shift

    done

    trap - SIGHUP SIGINT SIGTERM

    lk_console_blank

    if [ ${#FAILED[@]} -gt 0 ]; then
        lk_console_error "${#FAILED[@]} of $i $(lk_plural \
            "$i" server servers) failed to update:" \
            $'\n'"$(lk_echo_array FAILED)"
        lk_die ""
    else
        lk_console_success \
            "$i $(lk_plural "$i" server servers) updated successfully"
    fi

    exit
}

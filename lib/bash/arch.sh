#!/bin/bash
# shellcheck disable=SC2206

# [PACMAN_CONF=conf_file] lk_pacman_add_repo repo...
#   Add REPO to CONF_FILE (/etc/pacman.conf by default) unless already present.
#   REPO format: "repo|server|[key_url]|[key_id]|[siglevel]"
function lk_pacman_add_repo() {
    local PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}" IFS='|' \
        i r REPO SERVER KEY_URL KEY_ID SIG_LEVEL KEY_FILE
    [ -f "$PACMAN_CONF" ] || lk_warn "file not found: $PACMAN_CONF" || return
    for i in "$@"; do
        r=($i)
        REPO="${r[0]}"
        ! grep -Fxq "[$REPO]" "$PACMAN_CONF" || continue
        SERVER="${r[1]}"
        KEY_URL="${r[2]:-}"
        KEY_ID="${r[3]:-}"
        SIG_LEVEL="${r[4]:-}"
        if [ -n "$KEY_URL" ]; then
            lk_elevate ${CHROOT_COMMAND[@]+"${CHROOT_COMMAND[@]}"} \
                bash -c "\
KEY_FILE=\"\$(mktemp)\" &&
    curl --output \"\$KEY_FILE\" \"$(lk_esc "$KEY_URL")\" &&
    pacman-key --add \"\$KEY_FILE\"" || return
        elif [ -n "$KEY_ID" ]; then
            lk_elevate ${CHROOT_COMMAND[@]+"${CHROOT_COMMAND[@]}"} \
                pacman-key --recv-keys "$KEY_ID" || return
        fi
        [ -z "$KEY_ID" ] ||
            lk_elevate ${CHROOT_COMMAND[@]+"${CHROOT_COMMAND[@]}"} \
                pacman-key --lsign-key "$KEY_ID" || return
        lk_keep_original "$PACMAN_CONF"
        cat <<EOF | lk_elevate tee -a "$PACMAN_CONF" >/dev/null

[$REPO]${SIG_LEVEL:+
SigLevel = $SIG_LEVEL}
Server = $SERVER
EOF
    done
}

#!/bin/bash

# shellcheck disable=SC2015

# lk_openconnect USER HOST [ROUTE...]
function lk_openconnect() {
    local VPN_USER=$1 VPN_HOST=$2 VPN_PASSWD COMMAND LOG_FILE
    shift 2 || return
    ! pgrep -x openconnect >/dev/null ||
        lk_warn "openconnect is already running" ||
        return
    VPN_PASSWD=$(lk_secret \
        "$VPN_USER@$VPN_HOST" \
        "openconnect password for $VPN_USER@$VPN_HOST" \
        openconnect) &&
        [ -n "$VPN_PASSWD" ] ||
        lk_warn "password required" ||
        return
    COMMAND=(
        openconnect
        --background
        --script "vpn-slice --verbose --dump ${*:---route-internal}"
        --verbose
        --dump-http-traffic
        --passwd-on-stdin
        --protocol "${LK_OPENCONNECT_PROTOCOL:-gp}"
        --user "$VPN_USER"
        "$VPN_HOST"
    )
    LOG_FILE=$(LK_LOG_BASENAME=openconnect lk_log_create_file) || return
    echo "$VPN_PASSWD" | lk_elevate "${COMMAND[@]}" >>"$LOG_FILE" 2>&1
}

function lk_mediainfo_check() {
    local FILE VALUE COUNT \
        LK_MEDIAINFO_LABEL=${LK_MEDIAINFO_LABEL:-} \
        LK_MEDIAINFO_NO_VALUE=${LK_MEDIAINFO_NO_VALUE-<no content type>}
    LK_MEDIAINFO_FILES=()
    LK_MEDIAINFO_VALUES=()
    LK_MEDIAINFO_EMPTY_FILES=()
    while IFS= read -rd $'\0' FILE; do
        ((++COUNT))
        VALUE=$(mediainfo \
            --Output="${LK_MEDIAINFO_FORMAT:-General;%ContentType%}" \
            "$FILE") || return
        LK_MEDIAINFO_FILES+=("$FILE")
        LK_MEDIAINFO_VALUES+=("$VALUE")
        if [ -n "${VALUE// /}" ]; then
            lk_is_script_running && ! lk_verbose ||
                lk_console_log "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$VALUE"
        else
            LK_MEDIAINFO_EMPTY_FILES+=("$FILE")
            lk_is_script_running && ! lk_verbose ||
                lk_console_warning "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$LK_MEDIAINFO_NO_VALUE"
        fi
    done < <(
        [ $# -gt 0 ] &&
            printf '%s\0' "$@" ||
            find -L . -type f ! -name '.*' -print0
    )
    lk_is_script_running && ! lk_verbose 2 || {
        lk_console_message \
            "$COUNT $(lk_maybe_plural "$COUNT" file files) checked"
        lk_console_detail \
            "File names and mediainfo output saved at same indices in arrays:" \
            $'LK_MEDIAINFO_FILES\nLK_MEDIAINFO_VALUES'
        lk_console_detail \
            "Names of files where mediainfo output was empty saved in array:" \
            $'\nLK_MEDIAINFO_EMPTY_FILES'
    }
}

function lk_readynas_poweroff() {
    local NAS_HOSTNAME=$1 NAS_USER=$2 PASSWORD URL
    PASSWORD="${3-$(lk_secret "$NAS_USER@$NAS_HOSTNAME" \
        "Password for $NAS_USER@$NAS_HOSTNAME" lk_readynas)}" ||
        lk_warn "unable to retrieve password for $NAS_USER@$NAS_HOSTNAME" ||
        return
    URL="https://$NAS_HOSTNAME/get_handler?$(lk_implode_args "&" \
        "PAGE=System" "OUTER_TAB=tab_shutdown" "INNER_TAB=NONE" \
        "shutdown_option1=1" "command=poweroff" "OPERATION=set")"
    lk_curl_config \
        --user="$NAS_USER:$PASSWORD" \
        --insecure |
        curl --config - "$URL"
}

function lk_nextcloud_get_excluded() {
    (
        shopt -s nullglob || exit
        FILES=(
            ~/.config/*/sync-exclude.lst
            ~/Library/Preferences/*/sync-exclude.lst
        )
        [ ${#FILES[@]} -gt 0 ] ||
            lk_warn "file not found: sync-exclude.lst" || exit
        EXCLUDE_FILE=${FILES[0]}
        # - Ignore blank lines and comments
        # - Remove fleeting metadata prefixes ("]") and unescape leading hashes
        lk_mapfile EXCLUDE <(sed -Ee '/^([[:blank:]]*$|#)/d' \
            -e 's/^(\]|\\(#))/\2/' "$EXCLUDE_FILE")
        EXCLUDE+=(
            "._sync_*.db*"
            ".sync_*.db*"
            ".csync_journal.db*"
            ".owncloudsync.log*"
            "*_conflict-*"
        )
        FIND=(-path ./Desktop.ini)
        for p in "${EXCLUDE[@]}"; do
            if [[ $p =~ /$ ]]; then
                FIND+=(-o \( -type d -name "${p%/}" \))
            else
                FIND+=(-o -name "$p")
            fi
        done
        FIND=(find . \( "${FIND[@]}" \) -print0)
        lk_mapfile -z FILES <("${FIND[@]}" | sort -zu)
        EXCLUDE_FILE=${EXCLUDE_FILE//~/"~"}
        [ ${#FILES[@]} -eq 0 ] &&
            lk_console_message "No files excluded by $EXCLUDE_FILE" ||
            lk_echo_array FILES |
            lk_console_list "Excluded by $EXCLUDE_FILE:" file files
    )
}

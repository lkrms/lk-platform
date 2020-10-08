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
            lk_is_source_file_running && ! lk_verbose ||
                lk_console_log "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$VALUE"
        else
            LK_MEDIAINFO_EMPTY_FILES+=("$FILE")
            lk_is_source_file_running && ! lk_verbose ||
                lk_console_warning "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$LK_MEDIAINFO_NO_VALUE"
        fi
    done < <(
        [ $# -gt 0 ] &&
            printf '%s\0' "$@" ||
            find -L . -type f ! -name '.*' -print0
    )
    lk_is_source_file_running && ! lk_verbose 2 || {
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

function lk_nextcloud_get_excluded() {
    (
        shopt -s globstar nullglob || exit
        LIST=(
            ~/.config/**/sync-exclude.lst
            ~/Library/Preferences/**/sync-exclude.lst
        )
        [ "${#LIST[@]}" -eq 1 ] ||
            lk_warn "exactly one sync-exclude.lst required (${#LIST[@]} found)" ||
            return
        FILE="${LIST[0]}"
        eval "LIST=($(sed -Ee '/^([[:blank:]]*$|#)/d' -e 's/^[]\]//' -e 's/[[:blank:]]/\\&/g' -e 's/^/**\//' "$FILE"))"
        lk_console_item "${#LIST[@]} $(lk_maybe_plural "${#LIST[@]}" file files) excluded by $FILE:"
        lk_echo_array LIST
    )
}

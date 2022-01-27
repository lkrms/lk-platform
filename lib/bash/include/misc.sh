#!/bin/bash

lk_require secret

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
    LOG_FILE=$(_LK_LOG_BASENAME=openconnect lk_log_create_file) || return
    echo "$VPN_PASSWD" | lk_elevate "${COMMAND[@]}" >>"$LOG_FILE" 2>&1
}

function lk_mediainfo_check() {
    local FILE VALUE COUNT \
        LK_MEDIAINFO_LABEL=${LK_MEDIAINFO_LABEL-} \
        LK_MEDIAINFO_NO_VALUE=${LK_MEDIAINFO_NO_VALUE-<no content type>}
    LK_MEDIAINFO_FILES=()
    LK_MEDIAINFO_VALUES=()
    LK_MEDIAINFO_EMPTY_FILES=()
    while IFS= read -rd '' FILE; do
        ((++COUNT))
        VALUE=$(mediainfo \
            --Output="${LK_MEDIAINFO_FORMAT:-General;%ContentType%}" \
            "$FILE") || return
        LK_MEDIAINFO_FILES+=("$FILE")
        LK_MEDIAINFO_VALUES+=("$VALUE")
        if [ -n "${VALUE// /}" ]; then
            lk_script_running && ! lk_verbose ||
                lk_tty_log "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$VALUE"
        else
            LK_MEDIAINFO_EMPTY_FILES+=("$FILE")
            lk_script_running && ! lk_verbose ||
                lk_tty_warning "${FILE#./}:" \
                    "$LK_MEDIAINFO_LABEL$LK_MEDIAINFO_NO_VALUE"
        fi
    done < <(
        [ $# -gt 0 ] &&
            printf '%s\0' "$@" ||
            find -L . -type f ! -name '.*' -print0
    )
    lk_script_running && ! lk_verbose 2 || {
        lk_tty_print \
            "$COUNT $(lk_plural "$COUNT" file files) checked"
        lk_tty_detail \
            "File names and mediainfo output saved at same indices in arrays:" \
            $'LK_MEDIAINFO_FILES\nLK_MEDIAINFO_VALUES'
        lk_tty_detail \
            "Names of files where mediainfo output was empty saved in array:" \
            $'\nLK_MEDIAINFO_EMPTY_FILES'
    }
}

function lk_vscode_state_get_db() {
    local DB=/User/globalStorage/state.vscdb PATHS
    PATHS=(~/{.config,"Library/Application Support"}/{VSCodium,Code})
    PATHS=("${PATHS[@]/%/$DB}")
    lk_first_existing "${PATHS[@]}"
}

function lk_vscode_state_get_item() {
    local KEY DB
    [ $# -ge 1 ] || lk_warn "no key" || return
    KEY=${1//"'"/"''"}
    DB=$(lk_vscode_state_get_db) &&
        sqlite3 -line "$DB" \
            "select value from ItemTable where key='$KEY'" |
        awk -F"$S*=$S*" '$1=="value"{print$2}'
}

function lk_vscode_state_set_item() {
    local KEY VALUE DB
    [ $# -ge 2 ] || lk_warn "invalid arguments" || return
    KEY=${1//"'"/"''"}
    VALUE=${2//"'"/"''"}
    DB=$(lk_vscode_state_get_db) &&
        sqlite3 "$DB" \
            "replace into ItemTable (key, value) values ('$KEY', '$VALUE')"
}

function lk_vscode_extension_disable() {
    local KEY=extensionsIdentifiers/disabled JSON DISABLED
    [ -n "${1-}" ] || lk_warn "no extension" || return
    JSON=$(lk_vscode_state_get_item "$KEY") &&
        JSON=${JSON:-"[]"} &&
        DISABLED=$(jq --arg id "$1" \
            '[.[]|select(.id==$id)]|length' <<<"$JSON") ||
        return
    [ "$DISABLED" -gt 0 ] || {
        lk_tty_detail "Disabling VS Code extension:" "$1"
        JSON=$(jq -c --arg id "$1" '.+[{"id":$id}]' <<<"$JSON") &&
            lk_vscode_state_set_item "$KEY" "$JSON"
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
        [ ${#FILES[@]} -eq 0 ] &&
            lk_tty_print \
                "No files excluded by $(lk_tty_path "$EXCLUDE_FILE")" ||
            lk_tty_list FILES \
                "Excluded by $(lk_tty_path "$EXCLUDE_FILE"):" file files
    )
}

# lk_squid_get_directive_order [CONF [ORIG_CONF]]
#
# Print the names of all unique Squid directives in CONF in the same order as
# their respective "TAG:" lines in ORIG_CONF.
function lk_squid_get_directive_order() {
    local CONF=${1:-/etc/squid/squid.conf} \
        ORIG_CONF=${2:-/etc/squid/squid.conf.documented}
    sed -En "s/^#  TAG: ($NS+).*/\1/p" "$ORIG_CONF" |
        grep -Fxf <(awk '$0 !~ "^(#|'"$S"'*$)" {print $1}' "$CONF" | sort -u)
}

lk_provide misc

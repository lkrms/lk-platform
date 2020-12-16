#!/bin/bash
# shellcheck disable=SC2207

function lk_macos_version() {
    local VERSION
    VERSION=$(sw_vers -productVersion) || return
    [[ ! $VERSION =~ ^([0-9]+\.[0-9]+)(\.[0-9]+)?$ ]] ||
        VERSION=${BASH_REMATCH[1]}
    echo "$VERSION"
}

function lk_macos_version_name() {
    local VERSION
    VERSION=${1:-$(lk_macos_version)} || return
    case "$VERSION" in
    10.15)
        echo "catalina"
        ;;
    10.14)
        echo "mojave"
        ;;
    10.13)
        echo "high_sierra"
        ;;
    10.12)
        echo "sierra"
        ;;
    10.11)
        echo "el_capitan"
        ;;
    10.10)
        echo "yosemite"
        ;;
    *)
        lk_warn "unknown macOS version: $VERSION"
        return 1
        ;;
    esac
}

function lk_macos_set_hostname() {
    sudo scutil --set ComputerName "$1" &&
        sudo scutil --set HostName "$1" &&
        sudo scutil --set LocalHostName "$1" &&
        sudo defaults write \
            /Library/Preferences/SystemConfiguration/com.apple.smb.server \
            NetBIOSName "$1"
}

function lk_macos_command_line_tools_path() {
    xcode-select --print-path 2>/dev/null
}

function lk_macos_command_line_tools_installed() {
    lk_macos_command_line_tools_path >/dev/null
}

function lk_macos_install_command_line_tools() {
    local ITEM_NAME \
        TRIGGER=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    ! lk_macos_command_line_tools_installed || return 0
    lk_console_message "Installing command line tools"
    lk_console_detail "Searching for the latest Command Line Tools for Xcode"
    touch "$TRIGGER" &&
        ITEM_NAME=$(lk_keep_trying caffeinate -i softwareupdate --list |
            grep -E "^$S*\*.*Command Line Tools" |
            grep -Eiv "\W(beta|seed)\W" |
            sed -E "s/^$S*\*$S*(Label:$S*)?//" |
            sort --version-sort |
            tail -n1) ||
        lk_warn "unable to determine item name for Command Line Tools" ||
        return
    lk_console_detail "Installing Command Line Tools with:" \
        "softwareupdate --install \"$ITEM_NAME\""
    lk_keep_trying lk_elevate caffeinate -i \
        softwareupdate --install "$ITEM_NAME" >/dev/null || return
    lk_macos_command_line_tools_installed || return
    rm -f "$TRIGGER" || true
}

function lk_macos_xcode_maybe_accept_license() {
    if [ -e /Applications/Xcode.app ] &&
        ! xcodebuild -license check >/dev/null 2>&1; then
        lk_console_message "Accepting Xcode license"
        lk_console_detail "Running:" "xcodebuild -license accept"
        sudo xcodebuild -license accept
    fi
}

# lk_macos_kb_add_shortcut DOMAIN MENU_TITLE SHORTCUT
#
# Add a keyboard shortcut to the NSUserKeyEquivalents dictionary for DOMAIN.
#
# Modifier keys:
# - ^ = Ctrl
# - ~ = Alt
# - $ = Shift
# - @ = Command
function lk_macos_kb_add_shortcut() {
    local PLIST=${1:-}
    [ $# -eq 3 ] || return
    [ "$1" != NSGlobalDomain ] || PLIST=.GlobalPreferences
    defaults write "$1" \
        NSUserKeyEquivalents -dict-add "$2" "$3" &&
        defaults write ~/"Library/Preferences/$PLIST.plist" \
            NSUserKeyEquivalents -dict-add "$2" "$3"
}

# lk_macos_kb_reset_shortcuts DOMAIN
function lk_macos_kb_reset_shortcuts() {
    local PLIST=${1:-}
    [ $# -eq 1 ] || return
    [ "$1" != NSGlobalDomain ] || PLIST=.GlobalPreferences
    defaults delete "$1" \
        NSUserKeyEquivalents >/dev/null 2>&1 || true
    [ ! -e ~/"Library/Preferences/$PLIST.plist" ] ||
        defaults delete ~/"Library/Preferences/$PLIST.plist" \
            NSUserKeyEquivalents >/dev/null 2>&1 || true
}

function lk_macos_unmount() {
    local EXIT_STATUS=0 MOUNT_POINT
    for MOUNT_POINT in "$@"; do
        hdiutil unmount "$MOUNT_POINT" || EXIT_STATUS=$?
    done
    return "$EXIT_STATUS"
}

function lk_macos_install_pkg() {
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_detail "Installing:" "${1##*/}"
    lk_elevate installer -allowUntrusted -pkg "$1" -target / || return
}

function lk_macos_install_dmg() {
    local IFS MOUNT_ROOT MOUNT_POINTS EXIT_STATUS=0
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_console_detail "Attaching:" "${1##*/}"
    MOUNT_ROOT=$(lk_mktemp_dir) &&
        IFS=$'\n' &&
        MOUNT_POINTS=($(hdiutil attach -mountroot "$MOUNT_ROOT" "$1" |
            cut -sf3 | sed '/^[[:blank:]]*$/d')) &&
        [ ${#MOUNT_POINTS[@]} -gt 0 ] || return
    INSTALL=($(
        unset IFS
        find "${MOUNT_POINTS[@]}" -iname "*.pkg"
    )) || EXIT_STATUS=$?
    unset IFS
    [ "$EXIT_STATUS" -ne 0 ] ||
        [ ${#INSTALL[@]} -eq 1 ] ||
        lk_warn "nothing to install" || EXIT_STATUS=$?
    [ "$EXIT_STATUS" -ne 0 ] ||
        lk_macos_install_pkg "${INSTALL[0]}" || EXIT_STATUS=$?
    lk_macos_unmount "${MOUNT_POINTS[@]}" >/dev/null || EXIT_STATUS=$?
    return "$EXIT_STATUS"
}

function lk_macos_install() {
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    case "$1" in
    *.pkg)
        lk_macos_install_pkg "$1"
        ;;
    *.dmg)
        lk_macos_install_dmg "$1"
        ;;
    *)
        lk_warn "unknown file type: $1"
        false
        ;;
    esac
}

# lk_macos_maybe_install_pkg_url PKGID PKG_URL [PKG_NAME]
#
# Install PKGID from PKG_URL unless it's already installed.
function lk_macos_maybe_install_pkg_url() {
    local PKGID=$1 PKG_URL=$2 PKG_NAME=${3:-$1}
    pkgutil --pkgs | grep -Fx "$PKGID" >/dev/null || (
        lk_console_item "Installing package:" "$PKG_NAME"
        lk_console_detail "Downloading:" "$PKG_URL"
        DIR=$(lk_mktemp_dir) &&
            cd "$DIR" &&
            FILE=$(lk_download "$PKG_URL") &&
            lk_macos_install "$FILE" &&
            lk_console_message "Package installed successfully" || exit
    )
}

# lk_macos_sshd_set_port SERVICE_NAME
function lk_macos_sshd_set_port() {
    local PORT FILE=/System/Library/LaunchDaemons/ssh.plist
    [ -n "${1:-}" ] || lk_usage "Usage: $(lk_myself -f) SERVICE_NAME" || return
    [ -f "$FILE" ] || lk_warn "file not found: $FILE" || return
    lk_plist_set_file "$FILE"
    PORT=$(lk_plist_get ":Sockets:Listeners:SockServiceName" 2>/dev/null) &&
        [ "$PORT" = "$1" ] || {
        LK_SUDO=1 lk_file_keep_original "$FILE" &&
            lk_elevate launchctl unload "$FILE" &&
            LK_SUDO=1 lk_plist_replace \
                ":Sockets:Listeners:SockServiceName" string "$1" &&
            { LK_SUDO=1 lk_plist_replace \
                ":Sockets:Listeners:Bonjour:0" string "$1" 2>/dev/null ||
                true; } &&
            lk_elevate launchctl load -w "$FILE"
    }
}

# lk_macos_defaults_maybe_write EXPECTED DOMAIN KEY [TYPE] VALUE
#
# Run `defaults write DOMAIN KEY VALUE` if `defaults read DOMAIN KEY` doesn't
# output EXPECTED.
function lk_macos_defaults_maybe_write() {
    local EXPECTED=$1 CURRENT
    shift
    if ! CURRENT=$(defaults read "$1" "$2" 2>/dev/null) ||
        [ "$CURRENT" != "$EXPECTED" ]; then
        lk_console_detail "Configuring '$2' in" "$1"
        defaults write "$@"
    fi
}

# lk_macos_defaults_dump
function lk_macos_defaults_dump() {
    local IFS=', ' DIR HOST DOMAINS DOMAIN FILE
    if [ -n "${LK_DEFAULTS_DIR:-}" ]; then
        DIR=${LK_DEFAULTS_DIR%/}
    else
        DIR=~/.${LK_PATH_PREFIX:-lk-}defaults/$(lk_date_ymdhms)
    fi
    for HOST in "" currentHost; do
        mkdir -p "$DIR${HOST:+/$HOST}" || return
        DOMAINS=(
            NSGlobalDomain
            $(${_LK_MACOS_DEFAULTS_DUMP_SUDO:+sudo} \
                defaults ${HOST:+"-$HOST"} domains)
        ) || return
        for DOMAIN in "${DOMAINS[@]}"; do
            FILE=$DIR${HOST:+/$HOST}/$DOMAIN
            ${_LK_MACOS_DEFAULTS_DUMP_SUDO:+sudo} \
                defaults ${HOST:+"-$HOST"} read "$DOMAIN" >"$FILE" ||
                rm -f "$FILE"
        done
    done
    [ -z "${_LK_MACOS_DEFAULTS_DUMP_SUDO:-}" ] ||
        return 0
    lk_is_root || ! lk_can_sudo defaults || {
        local _LK_MACOS_DEFAULTS_DUMP_SUDO=1
        LK_DEFAULTS_DIR=$DIR-system \
            lk_macos_defaults_dump || return
    }
    DIR=$(lk_pretty_path "$DIR")
    lk_console_log \
        "Output of \"defaults [-currentHost] read \$DOMAIN\" dumped to:" \
        "$(for d in "$DIR" ${_LK_MACOS_DEFAULTS_DUMP_SUDO:+"$DIR-system"}; do
            lk_echo_args \
                "$d" "$d/currentHost"
        done)"
}

function PlistBuddy() {
    lk_maybe_sudo /usr/libexec/PlistBuddy "$@"
}

function _lk_plist_buddy() {
    [ -n "${_LK_PLIST:-}" ] ||
        lk_warn "lk_plist_set_file must be called before $(lk_myself -f 1)" ||
        return
    PlistBuddy -c "$1" "$_LK_PLIST" || return
}

function _lk_plist_quote() {
    echo "\"${1//\"/\\\"}\""
}

# lk_plist_set_file PLIST_FILE
#
# Run subsequent lk_plist_* commands on PLIST_FILE.
function lk_plist_set_file() {
    _LK_PLIST=$1
}

# lk_plist_delete ENTRY
function lk_plist_delete() {
    _lk_plist_buddy "Delete $(_lk_plist_quote "$1")"
}

# lk_plist_add ENTRY TYPE [VALUE]
#
# TYPE must be one of:
# - string
# - array
# - dict
# - bool
# - real
# - integer
# - date
# - data
function lk_plist_add() {
    _lk_plist_buddy \
        "Add $(_lk_plist_quote "$1") $2${3+ $(_lk_plist_quote "$3")}"
}

# lk_plist_replace ENTRY TYPE [VALUE]
function lk_plist_replace() {
    lk_plist_delete "$1" 2>/dev/null || true
    lk_plist_add "$@"
}

# lk_plist_replace_from_file ENTRY TYPE PLIST_FILE
#
# TYPE must match the top-level element of PLIST_FILE.
function lk_plist_replace_from_file() {
    lk_plist_replace "${@:1:2}"
    _lk_plist_buddy "Merge $(_lk_plist_quote "$3") $(_lk_plist_quote "$1")"
}

# lk_plist_get ENTRY
function lk_plist_get() {
    _lk_plist_buddy "Print $(_lk_plist_quote "$1")"
}

# lk_plist_exists ENTRY
function lk_plist_exists() {
    lk_plist_get "$1" >/dev/null 2>&1
}

# lk_plist_maybe_add ENTRY TYPE [VALUE]
function lk_plist_maybe_add() {
    lk_plist_exists "$1" ||
        lk_plist_add "$@"
}

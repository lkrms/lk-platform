#!/usr/bin/env bash

function _lk_macos_env() { true; }
function lk_x86() { "$@"; }
function lk_x86_only() { "$@"; }
function ibrew() { brew "$@"; }
function ibash() { bash "$@"; }

if lk_system_is_apple_silicon; then
    function _lk_macos_env() {
        local _LK_VAR _LK_VARS=(PATH MANPATH INFOPATH) _LK_VAL
        for _LK_VAR in "${_LK_VARS[@]}"; do
            [ -n "${!_LK_VAR:+1}" ] || continue
            _LK_VAL=$(lk_path_edit "$1" "${2-}" "${!_LK_VAR}") || return
            printf 'declare %s=%q\n' "$_LK_VAR" "$_LK_VAL"
            printf 'export %s\n' "$_LK_VAR"
        done
    }
    function lk_x86() {
        local SH
        SH=$(_lk_macos_env "" '^/opt/homebrew(/|$)') && eval "$SH" &&
            arch -x86_64 "$@"
    }
    function lk_x86_only() {
        local SH
        SH=$(_lk_macos_env '^/opt/homebrew(/|$)') && eval "$SH" &&
            arch -x86_64 "$@"
    }
    [[ ! -x /opt/homebrew/bin/brew ]] ||
        function brew() {
            local SH
            SH=$(_lk_macos_env '^/usr/local(/|$)') && eval "$SH" &&
                /opt/homebrew/bin/brew "$@"
        }
    [[ ! -x /usr/local/bin/brew ]] ||
        function ibrew() {
            local SH
            SH=$(_lk_macos_env '^/opt/homebrew(/|$)') && eval "$SH" &&
                arch -x86_64 /usr/local/bin/brew "$@"
        }
    function ibash() { lk_x86 bash "$@"; }
fi

# lk_macos_version
function lk_macos_version() {
    local version
    version=$(sw_vers -productVersion |
        sed -En 's/^([0-9]+\.[0-9]+).*/\1/p' | grep .) || return
    printf '%s\n' "$version"
}

# lk_macos_version_name [<version>]
function lk_macos_version_name() {
    local version name
    version=${1-$(lk_macos_version)} || return
    case "$version" in
    26.*) name=tahoe ;;
    15.*) name=sequoia ;;
    14.*) name=sonoma ;;
    13.*) name=ventura ;;
    12.*) name=monterey ;;
    11.*) name=big_sur ;;
    10.15) name=catalina ;;
    10.14) name=mojave ;;
    10.13) name=high_sierra ;;
    10.12) name=sierra ;;
    10.11) name=el_capitan ;;
    10.10) name=yosemite ;;
    *) lk_err "unknown macOS version: $version" || return ;;
    esac
    printf '%s\n' "$name"
}

# lk_macos_setenv VARIABLE VALUE
function lk_macos_setenv() {
    lk_is_identifier "${1-}" ||
        lk_warn "not a valid identifier: ${1-}" || return
    local LK_SUDO=1 _LABEL=setenv.$1 _FILE _TEMP
    _FILE=/Library/LaunchAgents/$_LABEL.plist
    _TEMP=$(lk_mktemp -d)/$_LABEL.plist &&
        lk_delete_on_exit "${_TEMP%/*}" || return
    defaults write "$_TEMP" Label -string "$_LABEL" &&
        defaults write "$_TEMP" ProgramArguments -array \
            /bin/launchctl setenv "$1" "${2-}" &&
        defaults write "$_TEMP" RunAtLoad -bool true || return
    if ! diff \
        <(plutil -convert xml1 -o - "$_FILE" 2>/dev/null) \
        <(plutil -convert xml1 -o - "$_TEMP") >/dev/null; then
        lk_user_is_root || launchctl unload "$_FILE" &>/dev/null || true
        lk_elevate install -m 00644 "$_TEMP" "$_FILE" || return
        lk_user_is_root || launchctl load -w "$_FILE" || return
    fi
    grep -Eq "\<$1\>" /etc/profile &>/dev/null || {
        lk_file_keep_original /etc/profile && lk_elevate tee -a \
            /etc/profile <<<"export $1=$(lk_double_quote "${2-}")" >/dev/null
    } || return
    export "$1=${2-}"
}

function lk_macos_set_hostname() {
    lk_elevate scutil --set ComputerName "$1" &&
        lk_elevate scutil --set HostName "$1" &&
        lk_elevate scutil --set LocalHostName "$1" &&
        lk_elevate defaults write \
            /Library/Preferences/SystemConfiguration/com.apple.smb.server \
            NetBIOSName "$1"
}

function lk_macos_command_line_tools_path() {
    xcode-select --print-path
}

function lk_macos_command_line_tools_installed() {
    lk_macos_command_line_tools_path &>/dev/null
}

function lk_macos_bundle_is_installed() {
    mdfind -onlyin / "kMDItemCFBundleIdentifier == '$1'" | grep . >/dev/null
}

function lk_macos_bundle_list() {
    mdfind -0 -onlyin / 'kMDItemContentType == "com.apple.application-bundle" && kMDItemCFBundleIdentifier == "*"' |
        xargs -0 mdls -r -name kMDItemCFBundleIdentifier -name kMDItemPath |
        tr '\0' '\n' |
        awk '{ b = $0; if (getline > 0) { print b, $0 } else { exit 1 } }'
}

# lk_macos_update_list_available
#
# Output tab-separated fields LABEL, TITLE, VERSION, SIZE, RECOMMENDED, and
# ACTION for each available update reported by `softwareupdate --list`.
function lk_macos_update_list_available() {
    softwareupdate --list | awk -v "S=$LK_h" -v OFS=$'\t' '
$1 ~ /^[*-]$/ {
  recommended = ($1 == "*" ? "Y" : "N")
  if (sub("^" S "*[*-]" S "+Label:" S "+", "")) {
    label = $0
  } else {
    label = ""
  }
  next
}
label {
  for (i in u) {
    delete u[i]
  }
  sub("^" S "+", "")
  split($0, a, "," S "+")
  for (i in a) {
    if (match(a[i], ":" S "+")) {
      f = substr(a[i], 1, RSTART - 1)
      v = substr(a[i], RSTART + RLENGTH)
      u[f] = v
    }
  }
  if (u["Title"] && u["Size"]) {
    print label, u["Title"], u["Version"], u["Size"], recommended, u["Action"]
  }
  label = ""
}'
}

function lk_macos_install_command_line_tools() {
    local FILE LABEL
    ! lk_macos_command_line_tools_installed || return 0
    lk_tty_print "Installing command line tools"
    lk_tty_detail "Searching for the latest Command Line Tools for Xcode"
    FILE=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    touch "$FILE" && LABEL=$(lk_macos_update_list_available |
        awk -F$'\t' -v 'W=([^[:alnum:]_]|^|$)' '
$5 == "Y" && $1 ~ "^Command Line Tools"W && $1 !~ W"(beta|seed)"W {print $1}' |
        sort --version-sort | tail -n1) &&
        [ -n "${LABEL:+1}" ] ||
        lk_warn "unable to determine item name for Command Line Tools" ||
        return
    lk_tty_run_detail lk_elevate caffeinate -d \
        softwareupdate --install "$LABEL" >/dev/null || return
    lk_macos_command_line_tools_installed || return
    rm -f "$FILE" || true
}

function lk_macos_install_rosetta2() {
    ! pkgutil --pkgs='com\.apple\.pkg\.RosettaUpdateAuto' &>/dev/null ||
        return 0
    lk_tty_print "Installing Rosetta 2"
    lk_tty_run_detail lk_elevate caffeinate -d \
        softwareupdate --install-rosetta --agree-to-license
}

function lk_macos_xcode_maybe_accept_license() {
    if [ -e /Applications/Xcode.app ] &&
        ! xcodebuild -license check &>/dev/null; then
        lk_tty_print "Accepting Xcode license"
        lk_tty_run_detail lk_elevate xcodebuild -license accept
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
    [ $# -eq 3 ] || return
    defaults write "$1" NSUserKeyEquivalents -dict-add "$2" "$3" || return
    [ "$1" = NSGlobalDomain ] ||
        defaults read com.apple.universalaccess \
            com.apple.custommenu.apps 2>/dev/null |
        grep -F "\"$1\"" >/dev/null ||
        defaults write com.apple.universalaccess \
            com.apple.custommenu.apps -array-add "$1"
}

# lk_macos_kb_reset_shortcuts DOMAIN
function lk_macos_kb_reset_shortcuts() {
    [ $# -eq 1 ] || return
    defaults delete "$1" NSUserKeyEquivalents &>/dev/null || true
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
    lk_tty_detail "Installing:" "${1##*/}"
    lk_elevate installer -allowUntrusted -pkg "$1" -target / || return
}

function lk_macos_install_dmg() {
    local IFS MOUNT_ROOT MOUNT_POINTS EXIT_STATUS=0
    [ -f "$1" ] || lk_warn "file not found: $1" || return
    lk_tty_detail "Attaching:" "${1##*/}"
    MOUNT_ROOT=$(lk_mktemp -d) &&
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
    lk_macos_unmount "${MOUNT_POINTS[@]}" >/dev/null || return
    rm -Rf "$MOUNT_ROOT" || true
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
        lk_tty_print "Installing package:" "$PKG_NAME"
        lk_tty_detail "Downloading:" "$PKG_URL"
        DIR=$(lk_mktemp -d) &&
            cd "$DIR" &&
            FILE=$(lk_download "$PKG_URL") &&
            lk_macos_install "$FILE" &&
            lk_tty_print "Package installed successfully" || exit
    )
}

# lk_macos_sshd_set_port SERVICE_NAME
function lk_macos_sshd_set_port() {
    local PORT FILE=/System/Library/LaunchDaemons/ssh.plist
    [ -n "${1-}" ] || lk_usage "Usage: $FUNCNAME SERVICE_NAME" || return
    [ -f "$FILE" ] || lk_warn "file not found: $FILE" || return
    lk_plist_set_file "$FILE"
    PORT=$(lk_plist_get ":Sockets:Listeners:SockServiceName" 2>/dev/null) &&
        [ "$PORT" = "$1" ] || {
        local LK_SUDO=1
        lk_file_keep_original "$FILE" &&
            lk_elevate launchctl unload "$FILE" &&
            lk_plist_replace \
                ":Sockets:Listeners:SockServiceName" string "$1" &&
            { lk_plist_replace \
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
        lk_tty_detail "Configuring '$2' in" "$1"
        defaults write "$@"
    fi
}

# lk_macos_defaults_dump [TAG]
function lk_macos_defaults_dump() {
    local IFS=', ' DIR HOST DOMAINS DOMAIN FILE
    if [ -n "${_LK_DEFAULTS_DIR-}" ]; then
        DIR=${_LK_DEFAULTS_DIR%/}
    else
        DIR=~/.${LK_PATH_PREFIX:-lk-}defaults/$(lk_date_ymdhms)${1+-$1}
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
                defaults ${HOST:+"-$HOST"} export "$DOMAIN" - >"$FILE" ||
                rm -f "$FILE"
        done
    done
    [ -z "${_LK_MACOS_DEFAULTS_DUMP_SUDO-}" ] ||
        return 0
    lk_user_is_root || ! lk_can_sudo defaults || {
        local _LK_MACOS_DEFAULTS_DUMP_SUDO=1
        _LK_DEFAULTS_DIR=$DIR/system \
            lk_macos_defaults_dump || return
    }
    DIR=$(lk_tty_path "$DIR")
    lk_tty_log \
        'Output of "defaults [-currentHost] export $DOMAIN" dumped to:' \
        "$(for d in "$DIR" ${_LK_MACOS_DEFAULTS_DUMP_SUDO:+"$DIR/system"}; do
            lk_args \
                "$d" "$d/currentHost"
        done)"
}

function PlistBuddy() {
    lk_sudo /usr/libexec/PlistBuddy "$@"
}

function _lk_plist_buddy() {
    [[ -n ${_LK_PLIST:+1} ]] ||
        _LK_STACK_DEPTH=1 lk_warn "call lk_plist_set_file first" || return
    # Create the plist file without "File Doesn't Exist, Will Create"
    [[ -e $_LK_PLIST ]] ||
        PlistBuddy -c "Save" "$_LK_PLIST" >/dev/null || return
    local COMMAND=$1
    shift
    PlistBuddy "$@" -c "$COMMAND" "$_LK_PLIST" || return
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

# lk_plist_maybe_delete ENTRY
function lk_plist_maybe_delete() {
    lk_plist_delete "$1" 2>/dev/null || true
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
#
# See lk_plist_add for valid types.
function lk_plist_replace() {
    lk_plist_delete "$1" 2>/dev/null || true
    lk_plist_add "$@"
}

# lk_plist_merge_from_file ENTRY PLIST_FILE [PLIST_FILE_ENTRY]
function lk_plist_merge_from_file() {
    (($# < 3)) || {
        [[ -e $2 ]] || lk_warn "file not found: $2" || return
        local TEMP
        lk_mktemp_with TEMP \
            PlistBuddy -x -c "Print $(_lk_plist_quote "$3")" "$2" || return
        set -- "$1" "$TEMP"
    }
    _lk_plist_buddy "Merge $(_lk_plist_quote "$2") $(_lk_plist_quote "$1")"
}

# lk_plist_replace_from_file ENTRY TYPE PLIST_FILE [PLIST_FILE_ENTRY]
#
# Use TYPE to specify the data type of the PLIST_FILE entry being applied.
#
# See lk_plist_add for valid types.
function lk_plist_replace_from_file() {
    lk_plist_replace "$1" "$2" &&
        lk_plist_merge_from_file "$1" "$3" ${4+"$4"}
}

# lk_plist_get ENTRY
function lk_plist_get() {
    _lk_plist_buddy "Print $(_lk_plist_quote "$1")"
}

# lk_plist_get_xml ENTRY
function lk_plist_get_xml() {
    _lk_plist_buddy "Print $(_lk_plist_quote "$1")" -x
}

# lk_plist_exists ENTRY
function lk_plist_exists() {
    lk_plist_get "$1" &>/dev/null
}

# lk_plist_maybe_add ENTRY TYPE [VALUE]
#
# See lk_plist_add for valid types.
function lk_plist_maybe_add() {
    lk_plist_exists "$1" ||
        lk_plist_add "$@"
}

# lk_macos_launch_agent_install [-p PROCESS_TYPE] LABEL COMMAND [ARG...]
#
# Create and load a launchd user agent that runs COMMAND when the user logs in.
# If PROCESS_TYPE is set to the empty string, the launchd default ('Standard')
# will be used, otherwise 'Interactive' will be used.
function lk_macos_launch_agent_install() {
    local PROCESS_TYPE=Interactive
    [ "${1-}" != -p ] || { PROCESS_TYPE=$2 && shift 2; }
    (($# > 1)) && [[ $1 != */* ]] || lk_usage "\
Usage: $FUNCNAME [-p PROCESS_TYPE] LABEL COMMAND [ARG...]" || return
    local LABEL=$1 FILE=~/Library/LaunchAgents/$1.plist _DIR _FILE ARG _PATH
    shift
    lk_mktemp_dir_with _DIR || return
    _FILE=$_DIR/$LABEL.plist
    lk_plist_set_file "$_FILE" &&
        lk_plist_add ":Disabled" bool false &&
        lk_plist_add ":Label" string "$LABEL" &&
        lk_plist_add ":ProcessType" string "${PROCESS_TYPE:-Standard}" &&
        lk_plist_add ":RunAtLoad" bool true &&
        lk_plist_add ":ProgramArguments" array || return
    for ARG in "$@"; do
        lk_plist_add ":ProgramArguments:" string "$ARG" || return
    done
    if _PATH=$(defaults read /var/db/com.apple.xpc.launchd/config/user.plist \
        PathEnvironmentVariable 2>/dev/null | grep .); then
        lk_plist_add ":EnvironmentVariables" dict &&
            lk_plist_add ":EnvironmentVariables:PATH" string "$_PATH" || return
    fi
    lk_install -d -m 00755 "${FILE%/*}" &&
        lk_install -m 00644 "$FILE" &&
        cp "$_FILE" "$FILE" || return
    launchctl unload "$FILE" &>/dev/null || true
    launchctl load -w "$FILE"
}

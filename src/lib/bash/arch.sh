#!/bin/bash

lk_require linux provision

function lk_arch_chroot() {
    [ "${1-}" != -u ] || {
        [ $# -ge 3 ] || lk_warn "invalid arguments" || return
        set -- runuser "${@:1:2}" -- "${@:3}"
    }
    if [ -n "${_LK_ARCH_ROOT-}" ]; then
        lk_elevate arch-chroot "$_LK_ARCH_ROOT" "$@"
    else
        lk_elevate "$@"
    fi
}

function lk_arch_path() {
    [[ ${1-} == /* ]] || lk_warn "path not absolute: ${1-}" || return
    echo "${_LK_ARCH_ROOT:+${_LK_ARCH_ROOT%/}}$1"
}

function lk_arch_reset_pacman_keyring() { (
    shopt -s dotglob
    lk_elevate gpgconf --homedir /etc/pacman.d/gnupg --kill gpg-agent &&
        lk_elevate rm -Rf /etc/pacman.d/gnupg/* &&
        lk_elevate pacman-key --init &&
        lk_elevate pacman-key --populate archlinux
); }

function lk_arch_configure_pacman() {
    local LK_CONF_OPTION_FILE _LK_CONF_DELIM=" = " LK_SUDO=1
    LK_CONF_OPTION_FILE=$(lk_arch_path /etc/pacman.conf)
    lk_tty_print "Checking pacman options in" "$LK_CONF_OPTION_FILE"
    lk_conf_enable_row -s options Color
    lk_conf_remove_row -s options TotalDownload
    lk_conf_set_option -s options ParallelDownloads 5
}

# lk_arch_add_repo REPO...
#
# Add each REPO to /etc/pacman.conf unless it has already been added. REPO is a
# pipe-separated list of values in this order (trailing pipes are optional):
# - REPO
# - SERVER
# - KEY_URL (optional)
# - KEY_ID (optional)
# - SIG_LEVEL (optional)
#
# Examples (line breaks added for legibility):
# - lk_arch_add_repo "aur|file:///srv/repo/aur|||Optional TrustAll"
# - lk_arch_add_repo "sublime-text|
#   https://download.sublimetext.com/arch/stable/\$arch|
#   https://download.sublimetext.com/sublimehq-pub.gpg|
#   8A8F901A"
function lk_arch_add_repo() {
    local IFS='|' FILE SH i r REPO SERVER KEY_URL KEY_ID SIG_LEVEL _FILE \
        LK_SUDO=1
    [ $# -gt 0 ] || lk_warn "no repo" || return
    FILE=$(lk_arch_path /etc/pacman.conf)
    [ -f "$FILE" ] ||
        lk_warn "$FILE: file not found" || return
    SH=$(
        function add_key() { KEY_FILE=$(mktemp) && {
            STATUS=0
            curl -fsSL --output "$KEY_FILE" "$1" &&
                pacman-key --add "$KEY_FILE" || STATUS=$?
            rm -f "$KEY_FILE" || true
            return "$STATUS"
        }; }
        declare -f add_key
        echo 'add_key "$1"'
    )
    lk_tty_print "Checking repositories in" "$FILE"
    for i in "$@"; do
        r=($i)
        REPO=${r[0]}
        ! pacman-conf --config "$FILE" --repo-list |
            grep -Fx "$REPO" >/dev/null || continue
        SERVER=${r[1]}
        KEY_URL=${r[2]-}
        KEY_ID=${r[3]-}
        SIG_LEVEL=${r[4]-}
        lk_tty_detail "Adding '$REPO':" "$SERVER"
        if [ -n "$KEY_URL" ]; then
            lk_arch_chroot bash -c "$SH" bash "$KEY_URL"
        elif [ -n "$KEY_ID" ]; then
            lk_arch_chroot pacman-key --recv-keys "$KEY_ID"
        fi || return
        [ -z "$KEY_ID" ] ||
            lk_arch_chroot pacman-key --lsign-key "$KEY_ID" || return
        lk_file_keep_original "$FILE" &&
            lk_file_get_text "$FILE" _FILE &&
            lk_file_replace "$FILE" "$_FILE
[$REPO]${SIG_LEVEL:+
SigLevel = $SIG_LEVEL}
Server = $SERVER"
        unset _LK_PACMAN_SYNC
    done
}

function lk_arch_configure_grub() {
    local CMDLINE FILE _FILE LK_SUDO=1
    CMDLINE=${LK_GRUB_CMDLINE+"$(lk_escape_ere_replace \
        "$(lk_double_quote -f "$LK_GRUB_CMDLINE")")"}
    CMDLINE=${CMDLINE:-\\1}
    FILE=$(lk_arch_path /etc/default/grub)
    _FILE=$(sed -E \
        -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
        -e 's/^#?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
        -e "s/^GRUB_CMDLINE_LINUX_DEFAULT=(.*)/GRUB_CMDLINE_LINUX_DEFAULT=$CMDLINE/" \
        "$FILE") &&
        lk_file_keep_original "$FILE" &&
        lk_file_replace "$FILE" "$_FILE" || lk_warn "unable to update $FILE" || return
    FILE=$(lk_arch_path /usr/local/bin/update-grub)
    _FILE=$(
        cat <<"EOF"
#!/bin/bash

set -euo pipefail
lk_die() { s=$? && echo "$0: ${1-error $s}" >&2 && (exit $s) && false || exit; }

[ "$EUID" -eq 0 ] || lk_die "not running as root"

if [[ ${1-} =~ ^(-i|--install)$ ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    # On some systems, GRUB must be installed at the default/fallpack boot path
    install -d /boot/EFI/BOOT
    cp -afv /boot/EFI/{GRUB/grubx64.efi,BOOT/BOOTX64.EFI} >&2
else
    echo "${0##*/}: skipping grub-install (--install not set)" >&2
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF
    )
    lk_install -d -m 00755 "${FILE%/*}" &&
        lk_install -m 00755 "$FILE" &&
        lk_file_replace "$FILE" "$_FILE" || lk_warn "unable to update $FILE" || return
}

function lk_pac_official_repo_list() {
    pacman-conf --repo-list |
        grep -E '^(core|extra|community|multilib)$'
}

# lk_pac_installed PACKAGE...
#
# Return true if each PACKAGE is installed.
function lk_pac_installed() {
    local E='' D=''
    [ "${1-}" != -e ] || E=-e
    [ "${1-}" != -d ] || D=-d
    [ -z "$E$D" ] || shift
    [ $# -gt 0 ] || lk_warn "no package" || return
    pacman -Qq $E $D "$@" &>/dev/null
}

# lk_pac_installed_list [PACKAGE...]
#
# Output each currently installed PACKAGE, or list all installed packages.
function lk_pac_installed_list() {
    local E='' D=''
    [ "${1-}" != -e ] || E=-e
    [ "${1-}" != -d ] || D=-d
    [ -z "$E$D" ] || shift
    [ $# -eq 0 ] || {
        comm -12 \
            <(lk_pac_installed_list $E $D | sort -u) \
            <(lk_echo_args "$@" | sort -u)
        return
    }
    pacman -Qq $E $D
}

# lk_pac_not_installed_list PACKAGE...
#
# Output each PACKAGE that isn't currently installed.
function lk_pac_not_installed_list() {
    local E='' D=''
    [ "${1-}" != -e ] || E=-e
    [ "${1-}" != -d ] || D=-d
    [ -z "$E$D" ] || shift
    [ $# -gt 0 ] || lk_warn "no package" || return
    comm -13 \
        <(lk_pac_installed_list $E $D "$@" | sort -u) \
        <(lk_echo_args "$@" | sort -u)
}

function lk_pac_sync() {
    ! lk_root && ! lk_can_sudo pacman ||
        { lk_is_false _LK_PACMAN_SYNC && [ "${1-}" != -f ]; } ||
        { lk_tty_print "Refreshing package databases" &&
            lk_elevate pacman -Sy >/dev/null &&
            _LK_PACMAN_SYNC=0; }
}

function lk_pac_groups() {
    lk_pac_sync &&
        pacman -Sgq "$@"
}

# lk_pac_repo_available_list [REPO...]
function lk_pac_repo_available_list() {
    lk_pac_sync &&
        pacman -Slq "$@"
}

# lk_pac_available_list [-o] [PACKAGE...]
#
# Output the names of all packages available for installation. If -o is set,
# only output packages from official repositories.
function lk_pac_available_list() {
    local OFFICIAL=
    [ "${1-}" != -o ] || { OFFICIAL=1 && shift; }
    lk_pac_sync || return
    if [ $# -gt 0 ]; then
        comm -12 \
            <(lk_echo_args "$@" | sort -u) \
            <(lk_pac_available_list ${OFFICIAL:+-o} | sort -u)
    else
        local IFS=$'\n' REPOS
        REPOS=${OFFICIAL:+$(lk_pac_official_repo_list)} &&
            lk_pac_repo_available_list $REPOS
    fi
}

# lk_pac_unavailable_list [-o] PACKAGE...
function lk_pac_unavailable_list() {
    local OFFICIAL=
    [ "${1-}" != -o ] || { OFFICIAL=1 && shift; }
    [ $# -gt 0 ] || lk_warn "no package" || return
    lk_pac_sync || return
    comm -23 \
        <(lk_echo_args "$@" | sort -u) \
        <(lk_pac_available_list ${OFFICIAL:+-o} | sort -u)
}

# lk_pac_installed_explicit [PACKAGE...]
#
# Output each PACKAGE currently marked as "explicitly installed", or list all
# explicitly installed packages.
function lk_pac_installed_explicit() {
    lk_pac_installed_list -e "$@"
}

# lk_pac_installed_not_explicit [PACKAGE...]
#
# Output each installed PACKAGE that isn't currently marked as "explicitly
# installed", or list all packages installed as dependencies.
function lk_pac_installed_not_explicit() {
    lk_pac_installed_list -d "$@"
}

# lk_pac_list_changed_files [DIR...]
function lk_pac_list_changed_files() {
    [ $# -gt 0 ] || set -- /etc
    local REGEX
    REGEX=$(lk_regex_implode "$@")
    {
        comm -13 \
            <(pacman -Ql |
                awk "\$2 ~ \"^$REGEX/.*[^/]\$\" {print \$2}" | sort -u) \
            <(sudo find "$@" ! \( \( \
                -path /etc/ca-certificates -o \
                -path /etc/ssl/certs \
                \) -prune \) ! -type d | sort -u) |
            tr '\n' '\0' |
            sudo xargs -0 ls -ld --time-style=long-iso |
            sed -E 's/^/NEW /' || return
        { sudo paccheck --md5sum --sha256sum --file-properties \
            --backup --noextract --noupgrade --quiet || true; } |
            awk -F"'" "\$2 ~ \"^$REGEX/.*[^/]\$\" {print \$2}" |
            sort -u |
            tr '\n' '\0' |
            sudo xargs -0 ls -ld --time-style=long-iso |
            sed -E 's/^/CHANGED /'
    } | sort -k9 | awk '
{ for (i = 1; i <= 8; i++) { printf "%s%s", $i, (i == 7 ? " " : "\t"); $i = "" }
  sub("^[[:blank:]]+", "")
  print }'
}

function lk_makepkg_setup() {
    local NAME EMAIL
    printenv PACKAGER &>/dev/null || (
        unset PACKAGER
        { [ ! -f /etc/makepkg.conf ] || . /etc/makepkg.conf; } &&
            [ -n "${PACKAGER-}" ]
    ) || {
        NAME=$(lk_full_name) && [ -n "$NAME" ] || NAME=$USER
        EMAIL=$USER@$(lk_fqdn) || EMAIL=$USER@localhost
        export PACKAGER="$NAME <${EMAIL%.localdomain}>"
    }
}

# lk_makepkg [-a AUR_PACKAGE] [MAKEPKG_ARG...]
function lk_makepkg() {
    local LK_SUDO= AUR_PACKAGE AUR_URL BUILD_DIR SH LIST
    [ "${1-}" != -a ] || { AUR_PACKAGE=$2 && shift 2; }
    lk_makepkg_setup
    LK_MAKEPKG_LIST=()
    if [ -n "${AUR_PACKAGE-}" ]; then
        AUR_URL=https://aur.archlinux.org/$AUR_PACKAGE.git
        BUILD_DIR=$(lk_mktemp_dir) &&
            lk_delete_on_exit "$BUILD_DIR" &&
            git clone "$AUR_URL" "$BUILD_DIR" &&
            SH=$({ cd "$BUILD_DIR" && lk_makepkg "$@"; } >&2 &&
                echo "LK_MAKEPKG_LIST=($(lk_quote_arr LK_MAKEPKG_LIST))") &&
            eval "$SH"
    else
        lk_pac_sync &&
            lk_faketty makepkg --syncdeps --rmdeps --clean --noconfirm "$@" &&
            LIST=$(lk_require_output makepkg --packagelist) &&
            lk_mapfile LK_MAKEPKG_LIST <<<"$LIST"
    fi
}

function lk_aur_can_chroot() {
    [[ -f /etc/aurutils/pacman-${LK_ARCH_AUR_REPO_NAME:-aur}.conf ]] &&
        lk_pac_installed devtools &&
        ! lk_in_chroot
}

function lk_aur_outdated() {
    aur repo --database "${LK_ARCH_AUR_REPO_NAME:-aur}" --list |
        aur vercmp -q
}

function lk_aur_sync() {
    local OUTDATED CHROOT PKG
    [ "${1-}" != -g ] && { local SYNCED FAILED; } || shift
    SYNCED=()
    FAILED=()
    [ $# -gt 0 ] || {
        lk_tty_print "Checking for updates to AUR packages"
        OUTDATED=($(lk_aur_outdated)) || return
        set -- ${OUTDATED[@]+"${OUTDATED[@]}"}
    }
    [ $# -gt 0 ] || return 0
    unset CHROOT
    ! lk_aur_can_chroot || CHROOT=
    lk_echo_args "$@" |
        lk_tty_list - "Syncing from AUR:" package packages
    lk_makepkg_setup
    for PKG in "$@"; do
        lk_tty_run_detail aur sync \
            --database "${LK_ARCH_AUR_REPO_NAME:-aur}" \
            --no-view \
            --noconfirm \
            ${CHROOT+--chroot} \
            ${CHROOT+--makepkg-conf=/etc/makepkg.conf} \
            ${CHROOT+${LK_ARCH_AUR_CHROOT_DIR:+--directory="$LK_ARCH_AUR_CHROOT_DIR"}} \
            ${GPGKEY+--sign} \
            ${CCACHE_DIR+--bind-rw="$CCACHE_DIR:/build/.ccache"} \
            "$PKG" &&
            SYNCED+=("$PKG") ||
            FAILED+=("$PKG")
    done
    [ ${#SYNCED[@]} -eq 0 ] ||
        lk_tty_list SYNCED "Synced from AUR:" package{,s} "$_LK_SUCCESS_COLOUR"
    [ ${#FAILED[@]} -eq 0 ] ||
        lk_tty_list FAILED "Failed to sync:" package{,s} "$_LK_ERROR_COLOUR"
    [ ${#FAILED[@]} -eq 0 ]
}

function lk_aur_rebuild() {
    (($#)) || lk_warn "invalid arguments" || return
    local SYNC_DIR=${XDG_CACHE_HOME:-~/.cache}/aurutils/sync \
        PKG PKGS=() ARG_FILE CHROOT
    while (($#)); do
        PKG=${1%PKGBUILD}
        PKG=${PKG%/}
        PKG=$(lk_first_file "$PWD/$PKG/PKGBUILD" "$SYNC_DIR/$PKG/PKGBUILD") ||
            lk_warn "PKGBUILD not found: $1" || return
        PKGS[${#PKGS[@]}]=$PKG
        shift
    done
    lk_mktemp_with ARG_FILE &&
        lk_realpath "${PKGS[@]}" | sed -En 's/\/PKGBUILD$//p' >"$ARG_FILE" ||
        return
    [ -s "$ARG_FILE" ] || lk_warn "no PKGBUILD files found" || return
    unset CHROOT
    ! lk_aur_can_chroot || CHROOT=
    lk_tty_list - "Rebuilding:" package packages <"$ARG_FILE"
    lk_makepkg_setup
    lk_tty_run_detail aur build \
        --database "${LK_ARCH_AUR_REPO_NAME:-aur}" \
        --force \
        --noconfirm \
        ${CHROOT+--chroot} \
        ${CHROOT+--makepkg-conf=/etc/makepkg.conf} \
        ${CHROOT+${LK_ARCH_AUR_CHROOT_DIR:+--directory="$LK_ARCH_AUR_CHROOT_DIR"}} \
        ${GPGKEY+--sign} \
        ${CCACHE_DIR+--bind-rw="$CCACHE_DIR:/build/.ccache"} \
        --arg-file "$ARG_FILE"
}

function lk_arch_reboot_required() {
    local RELEASE PACKAGE PACKAGE_VER
    RELEASE=$(uname -r) || return
    [ ! -d "/usr/lib/modules/$RELEASE" ] || {
        PACKAGE=$(awk -F= -v RS='[[:blank:]]+' '
/^BOOT_IMAGE=/ { if (sub(/^\/vmlinuz-/, "", $2)) p = $2 }
END { if (p) print p }' /proc/cmdline) && [ -n "$PACKAGE" ] || return
        PACKAGE_VER=$(pacman -Q "$PACKAGE" | awk '{print $2}') || return
        [[ ${RELEASE//./-} != ${PACKAGE_VER//./-}* ]]
    }
}

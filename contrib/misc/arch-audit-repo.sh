#!/bin/bash

# arch-audit-repo.sh REPO PACKAGE...
#
# Checks pacman repository REPO for each PACKAGE and its AUR dependencies.

. lk-bash-load.sh || exit

lk_require arch

# Default to AUR packages provisioned by lk-platform
[ $# -gt 1 ] || {
    PACKAGES=(
        aha
        apachedirectorystudio
        aurutils
        aurutils-git
        autorandr-git
        azure-cli
        azure-functions-core-tools-bin
        babel-preset-env
        bluez-git
        brother-hl5450dn
        brother-hll3230cdw
        csvkit
        demjson
        devilspie2
        elementary-xfce-icons
        emote
        espanso
        geekbench
        git-cola
        google-chrome
        hfsprogs
        httptoolkit
        icdiff
        linode-cli
        lua-posix
        makemkv
        masterpdfeditor-free
        memtest86-efi
        mongodb-bin
        mongodb-tools-bin
        mugshot
        networkmanager-dispatcher-ntpd
        nodejs-less
        numix-gtk-theme-git
        nvm
        pacman-cleanup-hook
        pencil
        php-sqlsrv
        phpdoc-phar
        powercap
        powerpanel
        powershell-bin
        quicktile-git
        r8152-dkms
        raidar
        rasdaemon
        rdfind
        robo3t-bin
        ryzenadj-git
        skypeforlinux-stable-bin
        sound-theme-smooth
        spotify
        standard
        storageexplorer
        stretchly-bin
        stretchly-git
        stripe-cli
        teams
        teamviewer
        terser
        timer-for-harvest
        todoist-appimage
        trickle
        trickle-git
        trimage
        ttf-apple-emoji
        ttf-ms-win10
        ttf-twemoji
        typora
        video-trimmer
        vpn-slice
        vscodium-bin
        wp-cli
        xfce-theme-greybird
        xfce4-panel-profiles
        xiccd
        xrandr-invert-colors
        zoom
        zuki-themes
    )
    set -- aur "${PACKAGES[@]}"
}

REPO=$1
shift

function download_sources() {
    printf '%s\n' "$@" |
        lk_tty_list - "Downloading from AUR:" package packages
    local pkg
    for pkg in "$@"; do
        (file=$pkg.tar.gz &&
            url=https://aur.archlinux.org/cgit/aur.git/snapshot/$file &&
            lk_cache curl -fsL "$url" >"$file" &&
            tar -zxf "$file" &&
            rm -f "$file" ||
            lk_pass rm -Rf "$file" "$pkg" ||
            echo "$pkg" >>"$ERRORS") &
    done
    wait
}

function parse_SRCINFO() {
    awk -f /dev/stdin "$PKGBUILDS"/*/.SRCINFO <<<"$AWK" |
        jq -r "$1" |
        grep -Eo "($S|^)[[:alnum:]+@_][[:alnum:]+.@_-]*" |
        tr -d '[:blank:]' |
        sort -u
}

lk_assign AWK <<"EOF"
function quote(str) {
  gsub("\"", "\\\"", str)
  return "\"" str "\""
}

function _print() {
  if (_name) {
    printf "%s:{\"pkgname\":[", (_count > 1 ? "," : "") quote(name[1])
    for (i = 1; i < _name; i++) {
      printf "%s", (i > 1 ? "," : "") quote(name[i])
      delete name[i]
    }
    printf "],\"depends\":["
    for (i = 1; i < _depends; i++) {
      printf "%s", (i > 1 ? "," : "") quote(depends[i])
      delete depends[i]
    }
    printf "]}"
  }
  _name = 1
  _depends = 1
  _count++
}

BEGIN {
  printf "{"
}
$1 == "pkgbase" {
  _print()
  name[_name++] = $3
  next
}
$1 == "pkgname" && $3 != name[1] {
  name[_name++] = $3
}
$1 == "depends" {
  depends[_depends++] = $3
}
END {
  _print()
  print "}"
}
EOF

lk_mktemp_with ERRORS
lk_mktemp_with OFFICIAL lk_pac_repo_available_list $(lk_pac_official_repo_list)
lk_mktemp_dir_with PKGBUILDS download_sources "$@"

cd "$PKGBUILDS"
while PKG=($(parse_SRCINFO '.[].pkgname | @tsv')) &&
    DEPS=($(parse_SRCINFO '.[].depends | @tsv' |
        grep -Fxvf "$OFFICIAL" \
            -f <(printf '%s\n' "$@" ${PKG+"${PKG[@]}"} | sort -u))); do
    download_sources "${DEPS[@]}"
    set -- $(lk_arr PKG DEPS | sort -u)
done

lk_console_success "Download complete"
lk_tty_print

printf '%s\n' "$@" | sort -u |
    lk_tty_list - "Expected from AUR in repo '$REPO':" package packages

! lk_mktemp_with ERRORS \
    grep -Fxvf "$OFFICIAL" -f <(printf '%s\n' "$@") "$ERRORS" ||
    lk_tty_list_detail - \
        "Unable to download from AUR:" package packages <"$ERRORS"

if lk_mktemp_with MISSING grep -Fxv \
    -f <(lk_pac_repo_available_list "$REPO") < <(printf '%s\n' "$@"); then
    lk_tty_list_detail - \
        "Missing (provided by others?):" package packages <"$MISSING"
else
    lk_tty_detail "No missing packages found"
fi

if lk_mktemp_with ORPHANS grep -Fxv \
    -f <(printf '%s\n' "$@") < <(lk_pac_repo_available_list "$REPO"); then
    lk_tty_list_detail - "Orphaned:" package packages <"$ORPHANS"
else
    lk_tty_detail "No orphans found"
fi

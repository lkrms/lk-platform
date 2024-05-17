#!/bin/bash

# arch-audit-repo.sh REPO PACKAGE...
#
# Checks pacman repository REPO for each PACKAGE and its AUR dependencies.

lk_bin_depth=2 . lk-bash-load.sh || exit
lk_require arch

# Default to AUR packages provisioned by lk-platform and/or maintained by lkrms
[ $# -gt 1 ] || {
    lk_require bash
    lk_pac_sync
    set -- "${1:-${LK_ARCH_AUR_REPO_NAME:-aur}}" $(comm -23 \
        <({ cat \
            "$LK_BASE/share/packages/arch"/* \
            "$LK_BASE/lib/arch/packages.sh" |
            lk_bash_array_literals |
            sed -E '/^[-a-zA-Z0-9+.:@_]+$/!d; s/:.*//; s/-$//' &&
            curl -fsSL 'https://aur.archlinux.org/rpc/?v=5&type=search&by=maintainer&arg=lkrms' |
            jq -r '.results[].Name'; } | sort -u) \
        <(expac -S '%r %n %G' |
            awk -v repo="${1:-${LK_ARCH_AUR_REPO_NAME:-aur}}" \
                '$1 != repo { gsub(/(^[^ ]+[[:blank:]]+|[[:blank:]]+$)/, ""); print }' |
            tr -s ' ' '\n' | sort -u))
}

REPO=$1
shift

function download_sources() {
    lk_mktemp_with -r PKGS
    curl -fsSL "https://aur.archlinux.org/rpc/?v=5&type=info$(
        printf '&arg[]=%s' "$@"
    )" | jq -r '.results[]|[.Name,.PackageBase]|@tsv' >"$PKGS" || return
    printf '%s\n' "$@" |
        lk_tty_list - "Downloading from AUR:" package packages
    local _pkg pkg
    for _pkg in "$@"; do
        pkg=$(awk -v pkg="$_pkg" '$1==pkg{print $2}' "$PKGS" | grep .) ||
            pkg=$_pkg
        [[ ! -f .$pkg ]] || continue
        touch ".$pkg" || return
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
    for (j = i = 1 + pkgbase_is_not_pkgname; i < _name; i++) {
      printf "%s", (i > j ? "," : "") quote(name[i])
      delete name[i]
    }
    printf "],\"depends\":["
    for (i = 1; i < _depends; i++) {
      printf "%s", (i > 1 ? "," : "") quote(depends[i])
      delete depends[i]
    }
    printf "],\"provides\":["
    for (i = 1; i < _provides; i++) {
      printf "%s", (i > 1 ? "," : "") quote(provides[i])
      delete provides[i]
    }
    printf "]}"
  }
  _name = 1
  _depends = 1
  _provides = 1
  _count++
}

BEGIN {
  printf "{"
}
$1 == "pkgbase" {
  _print()
  name[_name++] = $3
  pkgbase_is_not_pkgname = 1
  next
}
$1 == "pkgname" && $3 == name[1] {
  pkgbase_is_not_pkgname = 0
}
$1 == "pkgname" && $3 != name[1] {
  name[_name++] = $3
}
$1 == "depends" {
  depends[_depends++] = $3
}
$1 == "provides" {
  provides[_provides++] = $3
}
END {
  _print()
  print "}"
}
EOF

lk_mktemp_with ERRORS
lk_mktemp_with OTHER
# For each package in another repo, print 'name' and 'provides'
expac -S '%r %n %S' |
    awk -v repo="$REPO" '$1 != repo { gsub(/(^[^ ]+[[:blank:]]+|[[:blank:]]+$)/, ""); print }' |
    tr -s ' ' '\n' | sort -u >"$OTHER"
lk_mktemp_dir_with PKGBUILDS download_sources "$@"

cd "$PKGBUILDS"
while PKG=($(parse_SRCINFO '.[].pkgname | @tsv')) &&
    PROVIDES=($(parse_SRCINFO '.[].provides | @tsv')) &&
    DEPS=($(parse_SRCINFO '.[].depends | @tsv' |
        grep -Fxvf "$OTHER" -f <(printf '%s\n' \
            "$@" ${PKG+"${PKG[@]}"} ${PROVIDES+"${PROVIDES[@]}"} |
            sort -u))); do
    download_sources "${DEPS[@]}"
    set -- $(lk_arr PKG DEPS | sort -u)
done

lk_tty_success "Download complete"
lk_tty_print

printf '%s\n' "$@" | sort -u |
    lk_tty_list - "Expected from AUR in repo '$REPO':" package packages

! lk_mktemp_with ERRORS \
    grep -Fxvf "$OTHER" -f <(printf '%s\n' "$@") "$ERRORS" ||
    lk_tty_list_detail - \
        "Unable to download from AUR:" package packages <"$ERRORS"

lk_mktemp_with AVAILABLE lk_pac_repo_available_list "$REPO"
lk_mktemp_with PROVIDED
pacman -Sp --print-format "%n %P" $(
    awk -v repo="$REPO" '{ print repo "/" $0 }' "$AVAILABLE"
) | tr -s ' ' '\n' | sed -E 's/=.*//' | sort -u >"$PROVIDED"

if lk_mktemp_with MISSING grep -Fxv \
    -f "$PROVIDED" < <(printf '%s\n' "$@"); then
    lk_tty_list_detail - \
        "Missing (provided by others?):" package packages <"$MISSING"
else
    lk_tty_detail "No missing packages found"
fi

if lk_mktemp_with ORPHANS grep -Fxv -f <(
    pacman -Sp --print-format "%n" $(
        grep -Fx -f "$PROVIDED" < <(printf '%s\n' "$@") |
            awk -v repo="$REPO" '{ print repo "/" $0 }'
    )
) <"$AVAILABLE"; then
    lk_tty_list_detail - "Orphaned:" package packages <"$ORPHANS"
else
    lk_tty_detail "No orphans found"
fi

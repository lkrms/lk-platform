#!/usr/bin/env bash

function lk_brew_flush_cache() {
    lk_cache_flush
} #### Reviewed: 2023-03-14

function lk_brew_info() {
    lk_cache -t 3600 brew info "$@"
} #### Reviewed: 2023-03-14

# lk_brew_install_homebrew [TARGET_DIR]
function lk_brew_install_homebrew() {
    local TARGET_DIR=${1-} \
        URL=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
        COMMAND=(caffeinate -d) REFRESH_ENV=1 NAME BREW
    LK_BREW_NEW_INSTALL=0
    if lk_is_system_apple_silicon; then
        TARGET_DIR=${TARGET_DIR:-/opt/homebrew}
        COMMAND=(caffeinate -d arch -arm64)
        NAME=native
        [[ $TARGET_DIR != /usr/local ]] || {
            COMMAND=(caffeinate -d arch -x86_64)
            REFRESH_ENV=0
            NAME=Intel
        }
    elif lk_is_macos; then
        TARGET_DIR=${TARGET_DIR:-/usr/local}
    else
        TARGET_DIR=${TARGET_DIR:-/home/linuxbrew/.linuxbrew}
        COMMAND=()
    fi
    NAME=Homebrew${NAME:+" ($NAME)"}
    BREW=$TARGET_DIR/bin/brew
    [[ ! -x $BREW ]] || return 0
    lk_tty_print "Installing $NAME"
    [[ -s ${_LK_BREW_INSTALL-} ]] ||
        lk_mktemp_with _LK_BREW_INSTALL lk_curl "$URL" ||
        lk_pass rm -f "${_LK_BREW_INSTALL-}" || return
    CI=1 lk_faketty ${COMMAND+"${COMMAND[@]}"} \
        "$BASH" "$_LK_BREW_INSTALL" || return
    [[ -x $BREW ]] ||
        lk_warn "$BREW: command not found" || return
    LK_BREW_NEW_INSTALL=1
    ((!REFRESH_ENV)) ||
        [[ ! -f $LK_BASE/lib/bash/env.sh ]] ||
        { SH=$(. "$LK_BASE/lib/bash/env.sh") && eval "$SH"; }
} #### Reviewed: 2023-03-14

# lk_brew_tap [TAP...]
function lk_brew_tap() {
    local TAP
    while IFS= read -r TAP; do
        lk_tty_detail "Tapping" "$TAP"
        brew tap --quiet "$TAP" &&
            lk_brew_flush_cache || return
    done < <(comm -13 \
        <(brew tap | sort -u) \
        <(printf '%s\n' "$@" | sort -u))
} #### Reviewed: 2023-03-14

function lk_brew_list_formulae() {
    lk_cache -t 3600 brew list --formula --full-name
} #### Reviewed: 2023-03-14

function lk_brew_list_casks() {
    lk_cache -t 3600 brew list --cask --full-name
} #### Reviewed: 2023-03-14

# lk_brew_formulae_list_native [-n] [FORMULA...]
function lk_brew_formulae_list_native() {
    local NATIVE=true
    [[ ${1-} != -n ]] || { NATIVE=false && shift; }
    if ! lk_is_system_apple_silicon; then
        [[ $NATIVE == false ]] ||
            lk_brew_info --json=v2 --formula "${@---eval-all}" |
            jq -r '.formulae[].full_name'
    else
        lk_brew_info --json=v2 --formula "${@---eval-all}" |
            jq -r --argjson native "$NATIVE" '
def is_native:
    (.versions.bottle | not) or
        ([.bottle[].files | keys[] |
            select(match("^(all$|arm64_)"))] | length > 0);
.formulae[] | select(is_native == $native).full_name'
    fi
} #### Reviewed: 2023-03-14

# lk_brew_formulae_list_not_native [FORMULA...]
function lk_brew_formulae_list_not_native() {
    lk_brew_formulae_list_native -n "$@"
} #### Reviewed: 2023-03-14

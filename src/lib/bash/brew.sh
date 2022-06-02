#!/bin/bash

function lk_brew_flush_cache() {
    lk_cache_mark_dirty
}

function lk_brew_info() {
    lk_cache brew info "$@"
}

# lk_brew_install_homebrew [TARGET_DIR]
function lk_brew_install_homebrew() {
    local TARGET_DIR=${1-} COMMAND=(caffeinate -d) REFRESH_ENV NAME BREW \
    URL=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
    LK_BREW_NEW_INSTALL=0
    if lk_is_system_apple_silicon; then
        TARGET_DIR=${TARGET_DIR:-/opt/homebrew}
        COMMAND=(caffeinate -d arch -arm64)
        NAME=native
        [ "$TARGET_DIR" != /usr/local ] || {
            COMMAND=(caffeinate -d arch -x86_64)
            # Reuse local downloads to save time and bandwidth
            [ ! -d /opt/homebrew ] || COMMAND=(env
                HOMEBREW_BREW_GIT_REMOTE=/opt/homebrew
                HOMEBREW_CORE_GIT_REMOTE=/opt/homebrew/Library/Taps/homebrew/homebrew-core
                "${COMMAND[@]}")
            REFRESH_ENV=0
            NAME=Intel
        }
    elif lk_is_macos; then
        TARGET_DIR=${TARGET_DIR:-/usr/local}
    else
        TARGET_DIR=${TARGET_DIR:-/home/linuxbrew/.linuxbrew}
        COMMAND=()
    fi
    NAME="Homebrew${NAME:+ ($NAME)}"
    BREW=$TARGET_DIR/bin/brew
    [ -x "$BREW" ] || {
        lk_tty_print "Installing $NAME"
        [ -s "${_LK_BREW_INSTALL-}" ] ||
            lk_mktemp_with _LK_BREW_INSTALL lk_curl "$URL" ||
            lk_pass rm -f "${_LK_BREW_INSTALL-}" || return
        CI=1 lk_faketty ${COMMAND+"${COMMAND[@]}"} \
            /bin/bash "$_LK_BREW_INSTALL" || return
        [ -x "$BREW" ] ||
            lk_warn "$BREW: command not found" || return
        LK_BREW_NEW_INSTALL=1
        [ "${REFRESH_ENV:-1}" -eq 0 ] ||
            [ ! -f "$LK_BASE/lib/bash/env.sh" ] ||
            { SH=$(. "$LK_BASE/lib/bash/env.sh") && eval "$SH"; } || return
    }
}

# lk_brew_tap [TAP...]
function lk_brew_tap() {
    local TAP DIR URL
    while IFS= read -r TAP; do
        lk_tty_detail "Tapping" "$TAP"
        unset URL
        if lk_is_system_apple_silicon &&
            [ "$(brew --prefix 2>/dev/null)" != /opt/homebrew ] &&
            [[ $TAP =~ ^[^/]+/[^/]+$ ]] &&
            DIR=/opt/homebrew/Library/Taps/${TAP%/*}/homebrew-${TAP#*/} &&
            [ -d "$DIR" ]; then
            URL=$DIR
        fi
        brew tap --quiet "$TAP" ${URL+"$URL"} &&
            lk_brew_flush_cache || return
    done < <(comm -13 \
        <(brew tap | sort -u) \
        <(printf '%s\n' "$@" | sort -u))
}

function lk_brew_list_formulae() {
    lk_cache brew list --formula --full-name
}

function lk_brew_list_casks() {
    lk_cache brew list --cask --full-name
}

# lk_brew_enable_autoupdate [ARCH]
function lk_brew_enable_autoupdate() {
    lk_is_macos || lk_warn "not supported on this platform" || return
    local LABEL
    ! brew tap | grep -Fx homebrew/autoupdate >/dev/null ||
        { brew autoupdate delete &&
            brew untap homebrew/autoupdate || return; }
    LABEL=com.github.domt4.homebrew-autoupdate.${1-$(uname -m)}
    brew tap lkrms/autoupdate
    launchctl list "$LABEL" &>/dev/null || {
        lk_tty_print 'Enabling daily `brew update`'
        install -d -m 00755 ~/Library/LaunchAgents &&
            brew autoupdate start --cleanup
    }
}

# lk_brew_formulae_list_native [-n] [FORMULA...]
function lk_brew_formulae_list_native() {
    local NATIVE=true
    [ "${1-}" != -n ] || { NATIVE=false && shift; }
    if ! lk_is_system_apple_silicon; then
        [ "$NATIVE" = false ] ||
            lk_brew_info --json=v2 --formula "${@---all}" |
            jq -r '.formulae[].full_name'
    else
        lk_brew_info --json=v2 --formula "${@---all}" |
            jq -r --argjson native "$NATIVE" '
def is_native:
    (.versions.bottle | not) or
        ([.bottle[].files | keys[] |
            select(match("^(all$|arm64_)"))] | length > 0);
.formulae[] | select(is_native == $native).full_name'
    fi
}

# lk_brew_formulae_list_not_native [FORMULA...]
function lk_brew_formulae_list_not_native() {
    lk_brew_formulae_list_native -n "$@"
}

#### Reviewed: 2021-12-03

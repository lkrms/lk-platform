#!/bin/sh

quote() {
    echo "'$(echo "$1" | sed -E "s/'/'\\\\''/g")'"
}

in_path() {
    case ":$2:" in
    *:"$1":*)
        return
        ;;
    *)
        return 1
        ;;
    esac
}

_path_join() {
    _path=
    while [ $# -gt 0 ]; do
        [ ! -d "$1" ] ||
            _path=${_path:+$_path:}$1
        shift
    done
}

_path_check() {
    echo "$1" | awk -v RS=: '
function add_dir(d) { a[i++] = d; b[d] = 1 }
{ gsub(/(^[[:space:]]+|[[:space:]]+$)/, "") }
$0 && !b[$0] { add_dir($0) }
END { for (i = 0; i < length(a); i++) { s = (i ? s RS : "") a[i] } print s }' \
        2>/dev/null || echo "$1"
}

path_add() {
    _path_join "$@"
    _path_check "$PATH:$_path"
}

path_add_to_front() {
    _path_join "$@"
    _path_check "$_path:$PATH"
}

IFS=:
PATH=${PATH-}
OLD_PATH=$PATH
PATH=$(path_add \
    /usr/bin /bin /usr/sbin /sbin \
    $LK_BASE/bin \
    ${LK_ADD_TO_PATH-})
PATH=$(path_add_to_front \
    /usr/local/bin /usr/local/sbin \
    /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin)
[ ! -d /opt/homebrew/bin ] ||
    [ /opt/homebrew/bin -ef /usr/local/bin ] ||
    [ "$(uname -m 2>/dev/null)" = x86_64 ] || {
    PATH=$(path_add_to_front /opt/homebrew/bin /opt/homebrew/sbin)
    # DYLD_FALLBACK_LIBRARY_PATH defaults to "$HOME/lib:/usr/local/lib:/usr/lib"
    # (see `man dlopen`)
    [ ! -d /opt/homebrew/lib ] ||
        echo 'export DYLD_FALLBACK_LIBRARY_PATH=${DYLD_FALLBACK_LIBRARY_PATH-${HOME:+$HOME/lib:}/opt/homebrew/lib:/usr/local/lib:/usr/lib}'
}

unset -f brew

! BREW=$(command -v brew) ||
    ! BREW_SH=$(PATH=/usr/bin:/bin:/usr/sbin:/sbin "$BREW" shellenv 2>/dev/null |
        grep -E '\<HOMEBREW_(PREFIX|CELLAR|REPOSITORY|SHELLENV_PREFIX)=') || {
    eval "$BREW_SH"
    cat <<EOF
$BREW_SH
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_CASK_OPTS=--no-quarantine
EOF
    in_path "$HOMEBREW_PREFIX/share/man" "${MANPATH-}" ||
        echo 'export MANPATH="$HOMEBREW_PREFIX/share/man${MANPATH+:$MANPATH}:"'
    in_path "$HOMEBREW_PREFIX/share/info" "${INFOPATH-}" ||
        echo 'export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH-}"'
}

PATH=$(path_add_to_front \
    ${LK_ADD_TO_PATH_FIRST-} \
    ${HOME:+$HOME/.local/bin} \
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin})
[ "$PATH" = "$OLD_PATH" ] ||
    echo "export PATH=$(quote "$PATH")"
UNSET="${LK_ADD_TO_PATH+ LK_ADD_TO_PATH}\
${LK_ADD_TO_PATH_FIRST+ LK_ADD_TO_PATH_FIRST}"
cat <<EOF
${UNSET:+unset$UNSET
}export SUDO_PROMPT="[sudo] password for %p: "
EOF

[ -n "${LANG-}" ] ||
    { [ "$(uname -s)" != Darwin ] ||
        ! LANG=$(defaults read -g AppleLocale | grep .).UTF-8 ||
        echo "export LANG=$(quote "$LANG")"; } 2>/dev/null

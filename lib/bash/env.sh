#!/bin/sh

# quote <value>
quote() {
    printf '%s\n' "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

# implode_dirs [<dir>...]
implode_dirs() {
    p=
    for d in "$@"; do
        [ ! -d "$d" ] || p=${p:+$p:}$d
    done
    printf '%s\n' "$p"
}

# normalise_path <path>
normalise_path() {
    printf '%s' "$1" | awk -v RS=: '
$0 != "" && ! s[$0]++ {
  d[i++] = $0
}

END {
  p = ""
  for (j = 0; j < i; j++) {
    p = (j ? p RS : "") d[j]
  }
  print p
}'
}

# add_after_path [<dir>...]
add_after_path() {
    normalise_path "$PATH:$(implode_dirs "$@")"
}

# add_before_path [<dir>...]
add_before_path() {
    normalise_path "$(implode_dirs "$@"):$PATH"
}

IFS=:
PATH=${PATH-}
_path=$PATH
# shellcheck disable=SC2086
PATH=$(add_after_path /usr/bin /bin /usr/sbin /sbin ${LK_BASE+"$LK_BASE/bin"} ${LK_ADD_TO_PATH-})
PATH=$(add_before_path /usr/local/bin /usr/local/sbin /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/sbin)
# Don't add Homebrew for arm64 to PATH if running as a translated binary
[ ! -d /opt/homebrew/bin ] ||
    [ /opt/homebrew/bin -ef /usr/local/bin ] ||
    [ "$(uname -m)" != arm64 ] ||
    PATH=$(add_before_path /opt/homebrew/bin /opt/homebrew/sbin)

if _brew=$(
    unset -f brew
    command -v brew
    # `brew shellenv` output is empty if Homebrew directories are first in PATH
) && _sh=$(PATH=$_path "$_brew" shellenv); then
    eval "$_sh"
    printf '%s\n' "$_sh"
    printf 'export %s=%s\n' \
        HOMEBREW_NO_ANALYTICS 1 \
        HOMEBREW_NO_ENV_HINTS 1
fi

# shellcheck disable=SC2086
PATH=$(add_before_path ${LK_ADD_TO_PATH_FIRST-} ${HOME:+"$HOME/.local/bin"})
[ "$PATH" = "$_path" ] ||
    printf 'export %s=%s\n' \
        PATH "$(quote "$PATH")"
printf 'export %s=%s\n' \
    SUDO_PROMPT "$(quote "[sudo] password for %p: ")"

[ "${LANG-}" ] ||
    [ "$(uname -s)" != Darwin ] ||
    ! _locale=$(defaults read -g AppleLocale) 2>/dev/null ||
    [ -z "$_locale" ] ||
    printf 'export %s=%s\n' \
        LANG "$(quote "$_locale.UTF-8")"

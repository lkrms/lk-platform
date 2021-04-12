#!/bin/sh

double_quote() {
    echo "$1" | sed -Ee 's/[$`\"]/\\&/g' -e 's/^.*$/"&"/'
}

escape_ere() {
    echo "$1" | sed -E 's/[]$()*+./?[\^{|}]/\\&/g'
}

in_path() {
    case ":$PATH:" in
    *:$1:*)
        return
        ;;
    *)
        return 1
        ;;
    esac
}

path_add() {
    if ! in_path "$1" && [ -d "$1" ]; then
        echo "$PATH:$1" | sed -Ee 's/:+/:/g' -e 's/(^:|:$)//g'
    else
        echo "$PATH"
    fi
}

path_add_to_front() {
    if [ -d "$1" ]; then
        echo "$1:$(echo "$PATH" |
            sed -Ee "s/(:|^)$(escape_ere "$1")(:|$)/\\1\\2/g" \
                -e 's/:+/:/g' -e 's/(^:|:$)//g')"
    else
        echo "$PATH"
    fi
}

OLD_PATH=$PATH
PATH=$(path_add_to_front /usr/local/bin)
# shellcheck disable=SC2039
[ /opt/homebrew/bin -ef /usr/local/bin ] ||
    PATH=$(path_add_to_front /opt/homebrew/bin)

! type brew >/dev/null 2>&1 ||
    ! BREW_SH=$(brew shellenv 2>/dev/null |
        grep -E '^HOMEBREW_(PREFIX|CELLAR|REPOSITORY)=') || {
    eval "$BREW_SH"
    cat <<EOF
$BREW_SH
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_CASK_OPTS=--no-quarantine
EOF
    PATH=${MANPATH:-} in_path "$HOMEBREW_PREFIX/share/man" ||
        echo 'export MANPATH="$HOMEBREW_PREFIX/share/man${MANPATH+:$MANPATH}:"'
    PATH=${INFOPATH:-} in_path "$HOMEBREW_PREFIX/share/info" ||
        echo 'export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"'
}

IFS=':'
for DIR in ${LK_ADD_TO_PATH:+$LK_ADD_TO_PATH} ${LK_INST:-$LK_BASE}/bin; do
    PATH=$(path_add "$DIR")
done
for DIR in ${HOME:+$HOME/.local/bin} \
    ${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin} \
    ${LK_ADD_TO_PATH_FIRST:+$LK_ADD_TO_PATH_FIRST}; do
    PATH=$(path_add_to_front "$DIR")
done
[ "$PATH" = "$OLD_PATH" ] || {
    echo "export PATH=$(double_quote "$PATH")"
}
UNSET="${LK_ADD_TO_PATH+ LK_ADD_TO_PATH}\
${LK_ADD_TO_PATH_FIRST+ LK_ADD_TO_PATH_FIRST}"
cat <<EOF
${UNSET:+unset$UNSET
}export SUDO_PROMPT="[sudo] password for %p: "
export WP_CLI_CONFIG_PATH=\${LK_INST:-\$LK_BASE}/share/wp-cli/config.yml
EOF

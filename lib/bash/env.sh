#!/bin/sh

# shellcheck disable=SC2016

lk_double_quote() {
    set -- "$(echo "$1." | sed -Ee 's/\\/\\\\/g' -e 's/[$`"]/\\&/g')"
    echo "\"${1%.}\""
}

lk_esc_ere() {
    set -- "$(echo "$1," | sed -Ee 's/\\/\\\\/g' -e 's/[]$()*+./?[^{|}]/\\&/g')"
    printf '%s' "${1%,}"
}

lk_in_path() {
    case ":$PATH:" in
    *:$1:*)
        return
        ;;
    *)
        return 1
        ;;
    esac
}

lk_path_add() {
    if ! lk_in_path "$1" && [ -d "$1" ]; then
        echo "$PATH:$1" | sed -Ee 's/:+/:/g' -e 's/(^:|:$)//g'
    else
        echo "$PATH"
    fi
}

lk_path_add_to_front() {
    if [ -d "$1" ]; then
        echo "$1:$(echo "$PATH" |
            sed -Ee "s/(:|^)$(lk_esc_ere "$1")(:|$)/\\1\\2/g" \
                -e 's/:+/:/g' -e 's/(^:|:$)//g')"
    else
        echo "$PATH"
    fi
}

OLD_PATH=$PATH
PATH=$(lk_path_add_to_front /usr/local/bin)

! type brew >/dev/null 2>&1 ||
    ! BREW_SH=$(brew shellenv 2>/dev/null |
        grep -E 'HOMEBREW_(PREFIX|CELLAR|REPOSITORY)=') || {
    eval "$BREW_SH"
    cat <<EOF
$BREW_SH
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_CASK_OPTS=--no-quarantine
EOF
    PATH=${MANPATH:-} lk_in_path "$HOMEBREW_PREFIX/share/man" ||
        echo 'export MANPATH="$HOMEBREW_PREFIX/share/man${MANPATH+:$MANPATH}:"'
    PATH=${INFOPATH:-} lk_in_path "$HOMEBREW_PREFIX/share/info" ||
        echo 'export INFOPATH="$HOMEBREW_PREFIX/share/info:${INFOPATH:-}"'
}

ADD_TO_PATH=${LK_ADD_TO_PATH:+$LK_ADD_TO_PATH:}${LK_INST:-$LK_BASE}/bin
ADD_TO_PATH_FIRST="\
${HOME:+$HOME/.local/bin:}\
${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:}\
${LK_ADD_TO_PATH_FIRST:+$LK_ADD_TO_PATH_FIRST:}"
IFS=':'
for DIR in $ADD_TO_PATH; do
    PATH=$(lk_path_add "$DIR")
done
for DIR in $ADD_TO_PATH_FIRST; do
    PATH=$(lk_path_add_to_front "$DIR")
done
unset IFS
[ "$PATH" = "$OLD_PATH" ] || {
    echo "export PATH=$(lk_double_quote "$PATH")"
}
UNSET="\
${LK_ADD_TO_PATH+ LK_ADD_TO_PATH}\
${LK_ADD_TO_PATH_FIRST+ LK_ADD_TO_PATH_FIRST}"
cat <<EOF
${UNSET:+unset$UNSET
}export SUDO_PROMPT="[sudo] password for %p: "
export WP_CLI_CONFIG_PATH=\${LK_INST:-\$LK_BASE}/share/wp-cli/config.yml
EOF

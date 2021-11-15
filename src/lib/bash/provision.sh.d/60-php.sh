#!/bin/bash

# lk_composer_install [INSTALL_PATH]
function lk_composer_install() {
    local DEST=${1-} URL SHA FILE BASE_URL=https://getcomposer.org
    [ -n "$DEST" ] ||
        { lk_sudo test -w /usr/local/bin &&
            DEST=/usr/local/bin/composer || DEST=.; }
    [ ! -d "$DEST" ] || DEST=${DEST%/}/composer.phar
    lk_tty_print "Installing composer"
    URL=$BASE_URL$(lk_curl "$BASE_URL/versions" | jq -r '.stable[0].path') &&
        SHA=$(lk_curl "$URL.sha256sum" | awk '{print $1}') || return
    lk_tty_detail "Downloading" "$URL"
    lk_mktemp_with FILE lk_curl "$URL" || return
    lk_tty_detail "Verifying download"
    sha256sum "$FILE" | awk '{print $1}' | grep -Fxq "$SHA" ||
        lk_warn "invalid sha256sum: $FILE" || return
    lk_tty_detail "Installing to" "$DEST"
    lk_sudo install -m 00755 "$FILE" "$DEST"
}

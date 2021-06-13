#!/bin/bash

# lk_brew_formulae_list_native [FORMULA...]
function lk_brew_formulae_list_native() {
    local NATIVE=${_LK_BREW_NATIVE:-true}
    if ! lk_is_system_apple_silicon; then
        [ "$NATIVE" = false ] ||
            brew info --json=v2 --formula "${@---all}" |
            jq -r '.formulae[].full_name'
    else
        brew info --json=v2 --formula "${@---all}" |
            jq -r --argjson native "$NATIVE" "\
def is_native:
    (.versions.bottle | not) or
        ([.bottle[].files | keys[] |
            select(match(\"^(all\$|arm64_)\"))] | length > 0);
.formulae[] | select(is_native == \$native).full_name"
    fi
}

# lk_brew_formulae_list_not_native [FORMULA...]
function lk_brew_formulae_list_not_native() {
    local _LK_BREW_NATIVE=false
    lk_brew_formulae_list_native "$@"
}

lk_provide brew

#!/bin/bash

# lk_user_config_set VAR DIR FILE
#
# Assign the path of a user-specific config file to VAR in the caller's scope.
# DIR may be the empty string.
function lk_user_config_set() {
    (($# == 3)) && unset -v "$1" || lk_bad_args || return
    eval "$1=\${XDG_CONFIG_HOME:-~/.config}/lk-platform/${2:+\$2/}\$3"
}

# lk_user_config_find ARRAY DIR PATTERN
#
# Assign the paths of any user-specific config files matching PATTERN to ARRAY
# in the caller's scope. DIR may be the empty string.
function lk_user_config_find() {
    (($# == 3)) && unset -v "$1" || lk_bad_args || return
    lk_mapfile "$1" < <(lk_expand_path \
        "${XDG_CONFIG_HOME:-~/.config}/lk-platform/${2:+$2/}$3" |
        lk_filter "test -e")
}

# lk_user_config_install VAR DIR FILE [FILE_MODE [DIR_MODE]]
#
# Create or update permissions on a user-specific config file and assign its
# path to VAR in the caller's scope. DIR may be the empty string.
function lk_user_config_install() {
    (($# > 2)) || lk_bad_args || return
    local IFS=$' \t\n'
    lk_user_config_set "${@:1:3}" || return
    { [[ -z ${4:+1}${5:+1} ]] && [[ -r ${!1} ]]; } ||
        { lk_install -d ${5:+-m "$5"} "${!1%/*}" &&
            lk_install ${4:+-m "$4"} "${!1}"; }
}

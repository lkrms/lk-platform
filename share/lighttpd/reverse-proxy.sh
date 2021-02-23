#!/bin/bash

set -euo pipefail
shopt -s nullglob

HOST_NAME_REGEX="[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)*"

[ $# -ge 2 ] &&
    [[ $1 =~ ^$HOST_NAME_REGEX$ ]] &&
    [[ $2 =~ ^$HOST_NAME_REGEX$ ]] &&
    [[ ${3:-} =~ ^(|/([^/]+/)*)$ ]] || {
    echo "Usage: ${0##*/} HOST TARGET_HOST [/TARGET_PATH/]" >&2
    exit 1
}

printf 'server.modules += ("mod_proxy")
$HTTP["host"] == "%s" {
    proxy.server = ( "" => ( "%s" => ( "host" => "%s", "port" => 80 ) ) )
    proxy.replace-http-host = 1
    proxy.header = ( "map-urlpath" => ( "/" => "%s" ) )
}' "$1" "$2" "$2" "${3:-/}"

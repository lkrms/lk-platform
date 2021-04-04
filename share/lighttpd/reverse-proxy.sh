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

STREAM_RESPONSE=2
if [[ $2 =~ ^(127\.0\.0\.1|localhost)$ ]]; then
    STREAM_RESPONSE=0
fi

printf 'server.modules += ("%s")\n' mod_proxy mod_accesslog
printf '$HTTP["host"] == "%s" {
    proxy.server = ( "" => ( "%s" => ( "host" => "%s", "port" => 80 ) ) )
    proxy.replace-http-host = 1
    proxy.header = ( "map-urlpath" => ( "/" => "%s" ) )
    server.stream-response-body = %d
    accesslog.format = "%s"
}\n' "$1" "$2" "$2" "${3:-/}" "$STREAM_RESPONSE" \
    '%h %V %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"'" $2:80"

#!/bin/bash

set -euo pipefail
shopt -s nullglob

HOST_NAME_REGEX="[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?)*"

[ $# -ge 2 ] &&
    [[ $1 =~ ^$HOST_NAME_REGEX$ ]] &&
    [[ $2 =~ ^$HOST_NAME_REGEX$ ]] &&
    [[ ${3-} =~ ^(/([^/]+/)*)?$ ]] || {
    echo "Usage: ${0##*/} HOST TARGET_HOST [/TARGET_PATH/ [/IGNORE_PATH...]]" >&2
    exit 1
}

STREAM_RESPONSE=2
if [[ $2 =~ ^(127\.0\.0\.1|localhost)$ ]]; then
    STREAM_RESPONSE=0
fi

REWRITE=$(
    for IGNORE_PATH in "${@:4}"; do
        if [[ $IGNORE_PATH == */ ]]; then
            printf '"^/(%s.*)" => "/$1", ' "${IGNORE_PATH#/}"
        else
            printf '"^/(%s)$" => "/$1", ' "${IGNORE_PATH#/}"
        fi
    done
    set -- "${@:1:2}" "${3:-/}"
    printf '"^(/(.*))?$" => "/%s$2"' "${3#/}"
)

printf '$HTTP["host"] == "%s" {
    proxy.server = ( "" => ( "%s" => ( "host" => "%s", "port" => 80 ) ) )
    proxy.header = ( "https-remap" => "enable" )
    url.rewrite-once = ( %s )
    setenv.set-request-header = reverse_proxy_header_policy
    server.stream-response-body = %d
    accesslog.format = "%s"
}\n' "$1" "$2" "$2" "$REWRITE" "$STREAM_RESPONSE" \
    '%h %V %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"'" $2:80 %U"

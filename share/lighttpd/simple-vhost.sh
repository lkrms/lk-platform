#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

[ $# -ge 2 ] &&
    [ -d "$1" ] &&
    [[ $2 =~ ^[^/[:blank:]]+$ ]] || {
    echo "Usage: ${0##*/} SERVER_ROOT DOCUMENT_ROOT [HOST_EXCLUDE_PATTERN]" >&2
    exit 1
}

SERVER_ROOT=$(realpath "$1")
DEFAULT_PATTERN='\.mirror$'
set -- "$SERVER_ROOT" "$2" "${3:-$DEFAULT_PATTERN}"

HOST_FQDN=$(hostname -f)
DEFAULT_HOST=$HOST_FQDN
for HOST in "$HOST_FQDN" localhost 127.0.0.1 "$1"/*; do
    HOST=${HOST##*/}
    [ -d "$1/$HOST/$2" ] || continue
    DEFAULT_HOST=$HOST
    printf 'server.document-root := "%s"\n' "$1/$HOST/$2"
    break
done

printf 'server.modules += ("mod_simple_vhost")
$HTTP["host"] !~ "%s" {
    simple-vhost.server-root = "%s"
    simple-vhost.document-root = "%s"
    simple-vhost.default-host = "%s"
}' "$3" "$1" "$2" "$DEFAULT_HOST"

#!/bin/bash

# Generated by ({:printf '%s at %s' "$0" "$(lk_date_log)":})

function lk_log() {
    perl -pe '$| = 1;
BEGIN {
    use POSIX qw{strftime};
    use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );' >>/var/log/{{LK_PATH_PREFIX}}policy-rc.log
}

LK_BOLD=$'\E[1m'
LK_RESET=$'\E[m\017'

lk_log <<<"====> $LK_BOLD${0##*/}$LK_RESET invoked$(
    [ $# -eq 0 ] || {
        printf ' with %s %s:' \
            $# "$([ $# -eq 1 ] && echo argument || echo arguments)"
        i=0
        for ARG in "$@"; do
            ((++i))
            printf '\n%s%3d%s %q' "$LK_BOLD" "$i" "$LK_RESET" "$ARG"
        done
    }
)"

PROVISIONING=N
UPGRADING=N
EXIT_STATUS=104
LOCK_FILE=/tmp/{{LK_PATH_PREFIX}}install.lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    PROVISIONING=Y
    if [ -z "${_LK_APT_UPGRADE-}" ]; then
        [ "${DPKG_MAINTSCRIPT_NAME-}" != postinst ] ||
            EXIT_STATUS=101
    else
        UPGRADING=Y
    fi
else
    exec 9>&- &&
        rm -f -- "$LOCK_FILE" || true
fi
lk_log <<<"Provisioning: $PROVISIONING"
lk_log <<<"Upgrading: $UPGRADING"
lk_log <<<"Exit status: $EXIT_STATUS"
exit "$EXIT_STATUS"

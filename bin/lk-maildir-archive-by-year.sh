#!/usr/bin/env bash

lk_bin_depth=1 . lk-bash-load.sh || exit

function __usage() {
    cat <<EOF
Move email in one or more Maildirs from 'Archive' to 'Archive.YEAR'.

Usage:
  ${0##*/} [options] [MAILDIR...]

Options:
  --dry-run   Perform a trial run without moving email (this is the default).
  --run       Actually move email.

Default MAILDIR: $MAILDIR
EOF
}

MAILDIR=~/Maildir
COURIER_PREFIX=INBOX

LK_DRY_RUN=Y

lk_getopt
eval "set -- $LK_GETOPT"

[ $# -gt 0 ] || set -- "$MAILDIR"
lk_test_all_d "$@" || lk_usage -e "invalid Maildir"

lk_log_start

for MAILDIR in "$@"; do
    MAILDIR=$(lk_realpath "$MAILDIR")
    lk_tty_print "Processing" "$MAILDIR"

    ARCHIVE=$MAILDIR/.Archive/cur
    [ -d "$ARCHIVE" ] || continue

    OWNER=$(lk_file_owner "$MAILDIR")
    SUBSCRIBED=$MAILDIR/courierimapsubscribed
    PREFIX=${COURIER_PREFIX}.
    [ -f "$SUBSCRIBED" ] || {
        SUBSCRIBED=$MAILDIR/subscriptions
        PREFIX=
    }
    YEAR=$(date '+%Y')

    # Continue until there is no email from YEAR or earlier
    while find "$ARCHIVE" \
        -type f \
        -not -newermt "$((YEAR + 1))0101" \
        -print \
        -quit | grep . >/dev/null; do

        ((NEXT_YEAR = YEAR + 1))
        FOLDER=Archive.${YEAR}
        DIR=$MAILDIR/.$FOLDER/cur

        if [ ! -d "$DIR" ]; then
            lk_maybe -p lk_run_as "$OWNER" \
                install -d -m 00700 "$MAILDIR/.$FOLDER"/{,cur,new,tmp} &&
                { lk_is_dryrun || [ -d "$DIR" ]; } ||
                lk_die "unable to create $FOLDER in $MAILDIR"

            if [ -f "$SUBSCRIBED" ] &&
                ! grep -Fxq "$PREFIX$FOLDER" "$SUBSCRIBED"; then
                lk_maybe -p eval "$(printf \
                    'echo %q >>%q\n' "$PREFIX$FOLDER" "$SUBSCRIBED")" ||
                    lk_die "unable to subscribe $OWNER to $FOLDER in $MAILDIR"
            fi
        fi

        lk_maybe -p find "$ARCHIVE" \
            -type f \
            -newermt "${YEAR}0101" \
            -not -newermt "${NEXT_YEAR}0101" \
            -exec mv -v '{}' "$DIR" \;

        ((--YEAR))
    done
done

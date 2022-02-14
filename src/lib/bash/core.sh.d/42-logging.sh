#!/bin/bash

# _lk_log_install_file FILE
#
# If the parent directory of FILE doesn't exist, use root privileges to create
# it with file mode 01777. Then, if FILE doesn't exist or isn't writable, create
# it or change its permissions and ownership as needed.
function _lk_log_install_file() {
    if [[ ! -f $1 ]] || [[ ! -w $1 ]]; then
        if [[ ! -e $1 ]]; then
            local DIR=${1%"${1##*/}"} GID
            [[ -d ${DIR:=$PWD} ]] ||
                lk_elevate install -d -m 01777 "$DIR" || return
            GID=$(id -g) &&
                lk_elevate -f \
                    install -m 00600 -o "$UID" -g "$GID" /dev/null "$1"
        else
            lk_elevate -f chmod 00600 "$1" || return
            [ -w "$1" ] ||
                lk_elevate chown "$UID" "$1"
        fi
    fi
}

# lk_log
#
# For each line of input, add a microsecond-resolution timestamp and remove
# characters before any carriage returns that aren't part of the line ending.
function lk_log() {
    local PL=${LK_BASE:+$LK_BASE/lib/perl/log.pl}
    trap "" SIGINT
    if [[ -x $PL ]]; then
        exec "$PL"
    else
        # Don't use exec because without Bash, $PL won't be deleted on exit
        lk_mktemp_with PL cat <<"EOF" && chmod u+x "$PL" && "$PL"
#!/usr/bin/perl -p
BEGIN {
  $| = 1;
  use POSIX qw{strftime};
  use Time::HiRes qw{gettimeofday};
}
( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );
s/.*\r(.)/\1/;
EOF
    fi
}

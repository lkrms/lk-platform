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


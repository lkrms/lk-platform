#!/usr/bin/perl -p

# Add a timestamp with microseconds to each line of input.

BEGIN {
  # Ignore Ctrl+C
  $SIG{INT} = "IGNORE";

  # Disable output buffering
  $| = 1;
  use POSIX       qw{strftime};
  use Time::HiRes qw{gettimeofday};
}

( $s, $ms ) = Time::HiRes::gettimeofday();
$ms = sprintf( "%06i", $ms );
print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );

# Remove text before the last CR on each line (i.e. transient progress output)
s/.*\r(.)/\1/;


#!/usr/bin/perl

# Add a timestamp with microseconds to each line of input.
#
# Usage:
#   log.pl [--self-delete]

BEGIN {
  # Disable output buffering
  $| = 1;
  use POSIX       qw{strftime};
  use Time::HiRes qw{gettimeofday};
}

while (<STDIN>) {
  ( $s, $ms ) = Time::HiRes::gettimeofday();
  $ms = sprintf( "%06i", $ms );
  print strftime( "%Y-%m-%d %H:%M:%S.$ms %z ", localtime($s) );

  # Remove text before the last CR on each line (e.g. progress bars)
  s/.*\r(.)/\1/;

  # Remove escape sequences and non-printing characters
  #
  # - Bash/readline non-printing sequences
  # - ANSI-compliant escape sequences
  #   - CSI (including SGR)
  #   - OSC (terminated by BEL or ST)
  #   - Other ST-terminated control sequences
  #   - Other escape sequences
  s/(?:
    \x{1} .*? \x{2} |
    \e \[ [\x{30}-\x{3f}]* [\x{20}-\x{2f}]* [\x{40}-\x{7e}] |
    \e \] .*? (?: \a | \e \\ ) |
    \e [PX^_] .*? \e \\ |
    \e [\x{20}-\x{2f}]* [\x{30}-\x{7e}]
  )//xg;
}
continue {
  print;
}

END {
  if ( $ARGV[0] eq "--self-delete" ) {
    unlink $0;
  }
}


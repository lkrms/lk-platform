#!/bin/awk -f

BEGIN {
  if (!section) {
    section = ARGV[1]
    ARGV[1] = ""
    if (!section) {
      printf("Usage: %s ([-v] section=<SECTION>|<SECTION>) ...\n",
        ARGV[0]) > "/dev/stderr"
      exit 1
    }
  }
  S = "[[:blank:]]"
  prefix = "^" S "*\\[" S "*"
  suffix = S "*\\]" S "*$"
  name   = "[-[:alnum:]./_]+"
  re     = prefix name suffix
  skip = 1
}

!skip && $0 ~ re {
  exit
}

$0 ~ re {
  sub(prefix, "")
  sub(suffix, "")
  if ($0 ~ name && $0 == section) {
    skip = 0
    next
  }
}

!skip {
  print
}

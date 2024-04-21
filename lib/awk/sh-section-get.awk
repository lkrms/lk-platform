BEGIN {
  if (! section) {
    section = ARGV[1]
    ARGV[1] = ""
    if (! section) {
      print("section required") > "/dev/stderr"
      exit 1
    }
  }
  S = "[[:blank:]]"
  FS = "(" S "*\\[|\\]" S "*)"
  blank = "^" S "*$"
  comment = "^" S "*" (comment ? comment : "[#;]")
  section_start = "^" S "*\\[[^][]+\\]" S "*$"
  disabled_section_start = comment S "*\\[[^][]+\\]" S "*$"
  skip = 1
}

$0 ~ section_start && $2 == section {
  skip = 0
  next
}

! skip && $0 ~ section_start {
  exit
}

{
  if (skip_disabled && ! is_blank() && ! is_comment()) {
    printf "%s", disabled
    disabled = ""
    skip_disabled = 0
  } else if (! skip && ! skip_disabled && $0 ~ disabled_section_start) {
    skip_disabled = 1
  }
}

skip_disabled {
  disabled = disabled $0 "\n"
  next
}

! skip {
  print
}


function is_blank()
{
  return ($0 ~ blank)
}

function is_comment()
{
  return ($0 ~ comment)
}

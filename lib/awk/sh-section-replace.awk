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
  entries = right(entries, 1) == "\n" ? entries : entries "\n"
}

$0 ~ section_start && $2 == section {
  skip = 1
  next
}

skip && $0 ~ section_start {
  print_section()
}

{
  if (keep_disabled && ! is_blank() && ! is_comment()) {
    disabled = ""
    keep_disabled = 0
  } else if (skip && ! keep_disabled && $0 ~ disabled_section_start) {
    keep_disabled = 1
  }
}

keep_disabled {
  disabled = disabled $0 "\n"
  next
}

skip {
  next
}

! printed && (is_blank() || is_comment()) {
  last_blank = NR
}

{
  maybe_print_blank(1)
  print
  last_printed = NR
}

END {
  entries = entries "\n"
  print_section()
}


function is_blank()
{
  return ($0 ~ blank)
}

function is_comment()
{
  return ($0 ~ comment)
}

function maybe_print_blank(check_current)
{
  if (pending_blank && (! check_current || ! is_blank())) {
    print ""
  }
  pending_blank = 0
}

function print_section()
{
  if (! printed) {
    if (last_blank < last_printed) {
      print ""
    }
    print "[" section "]"
    printf "%s", entries
    printed = 1
    if (right(entries, 2) != "\n\n") {
      pending_blank = 1
    }
  }
  if (keep_disabled) {
    maybe_print_blank()
    printf "%s", disabled
    disabled = ""
    keep_disabled = 0
  }
  skip = 0
}

function right(s, l)
{
  substr(s, length(s) - l + 1)
}

/^[ \t]*$/ {
  if (last_blank) {
    next
  }
  last_blank = 1
  print ""
  next
}

{
  last_blank = 0
  print
}


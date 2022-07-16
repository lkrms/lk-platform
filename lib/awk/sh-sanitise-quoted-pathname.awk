# Remove any enclosing single or double quotation marks from untrusted
# pathnames, then quote everything except tilde-prefixes and wildcard patterns
# for safe expansion in shell scripts via `eval` or similar.
#
# - Enclosing quotes must be backslash-escaped if they appear within pathnames
# - Set awk variables `no_unquote_single` and/or `no_unquote_double` to suppress
#   removal of enclosing quotes
#
# Example input:
#
#     "\"This is quoted,\" he said. \"That's what she said,\" came the reply."
#     'This isn\'t quoted with double quotes, but with single quotes.'
#     ~/$this/has a tilde-prefix/and/`unsavoury characters`
#     ~/Code/*/l[ka]*
#
# Output:
#
#     '"This is quoted," he said. "That'\''s what she said," came the reply.'
#     'This isn'\''t quoted with double quotes, but with single quotes.'
#     ~/'$this/has a tilde-prefix/and/`unsavoury characters`'
#     ~/'Code/'*'/l'[ka]*
#
BEGIN {
  unquote_single = no_unquote_single ? 0 : 1
  unquote_double = no_unquote_double ? 0 : 1
  unquote = unquote_single || unquote_double
  ORS = RS
}

# Remove enclosing quotes and unescape
unquote && (/^'([^']+|\\')*'$/ || /^"([^"]+|\\")*"$/) {
  if (unquote_single && (gsub(/^'|'$/, "", $0))) {
    gsub(/\\'/, "'", $0)
  } else if (unquote_double && (gsub(/^"|"$/, "", $0))) {
    gsub(/\\"/, "\"", $0)
  }
}

# Print tilde-prefixes unquoted
/^(~[-a-z0-9\$_]*)(\/.*)?$/ {
  home = $0
  sub(/\/.*/, "/", home)
  printf "%s", home
  sub(/^[^\/]+\/?/, "", $0)
}

{
  # Print wildcards (as defined by glob(7)) unquoted
  while (pos = match($0, /\*+|\?+|\[(][^]]*|[^]]+)]/)) {
    if (pos > 1) {
      printf "%s", quote(substr($0, 1, pos - 1))
    }
    printf "%s", substr($0, pos, RLENGTH)
    $0 = substr($0, pos + RLENGTH)
  }
  if ($0) {
    printf "%s", quote($0)
  }
  print ""
}


function quote(str)
{
  gsub(/'/, "'\\''", str)
  return ("'" str "'")
}

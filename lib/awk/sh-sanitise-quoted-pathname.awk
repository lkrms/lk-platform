# Remove enclosing single and double quotes from pathnames, then quote them for
# safe tilde and wildcard expansion in shell scripts.
#
# Assign a value to one or more of the following variables to modify the
# script's behaviour:
#
# - `unquote_single`: remove enclosing single quotes (') (default: 1).
# - `unquote_double`: remove enclosing double quotes (") (default: 1).
# - `quote_tilde`: prevent tilde expansion (default: 0).
# - `quote_glob`: prevent glob expansion (default: 0).
#
# In pathnames with enclosing quotes that are being removed, quotes of the same
# type must be backslash-escaped, e.g. `'I\'m quoted'`.
#

BEGIN {
  unquote_single = get_value(unquote_single, 1)
  unquote_double = get_value(unquote_double, 1)
  quote_tilde = get_value(quote_tilde, 0)
  quote_glob = get_value(quote_glob, 0)
  ORS = RS
}


# Remove enclosing quotes and unescape
(unquote_single && /^'([^'\\]+|\\.)*'$/) || (unquote_double && /^"([^"\\]+|\\.)*"$/) {
  enclosing = substr($0, 1, 1)
  $0 = substr($0, 2, length($0) - 2)
  if (enclosing == "'") {
    gsub(/\\'/, "'", $0)
  } else {
    gsub(/\\"/, "\"", $0)
  }
}


# Print tilde prefixes unquoted
! quote_tilde && /^~/ {
  printf "%s", "~"
  $0 = substr($0, 2)
  # Match Bash-compatible quoting
  if (match($0, /^([^'"\/]+|'[^']*'|"([^"\\$`]+|\\.)*"|\\.)*\/?/)) {
    printf "%s", substr($0, 1, RLENGTH)
    $0 = substr($0, RLENGTH + 1)
  }
}


# Print unescaped wildcards (as defined by glob(7)) unquoted
! quote_glob {
  q = ""
  while (pos = match($0, /\*+|\?+|\[(][^]]*|[^]]+)]/)) {
    len = RLENGTH
    if (pos > 1) {
      _q = substr($0, 1, pos - 1)
      # Check if this is an escaped wildcard
      if (match(_q, /^([^\\]|\\.)*\\$/)) {
        q = q _q substr($0, pos, 1)
        $0 = substr($0, pos + 1)
        continue
      } else {
        printf "%s", quote(q _q)
        q = ""
      }
    } else if (q) {
      printf "%s", quote(q)
      q = ""
    }
    printf "%s", substr($0, pos, len)
    $0 = substr($0, pos + len)
  }
  if (q) {
    printf "%s", quote(q)
  }
}

$0 {
  printf "%s", quote($0)
}

{
  print ""
}

function get_value(val, default)
{
  return (val == 0 && val == "" ? default : val)
}

function quote(str)
{
  gsub(/'/, "'\\''", str)
  return ("'" str "'")
}

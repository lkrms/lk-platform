# Follow CNAME records in output from `dig` and print the entries they resolve
# to with their original names and TTLs.
#
BEGIN {
  s = "[ \\t]"
  ns = "[^ \\t]"
  name_ttl_regex = "^" s "*" ns "+" s "+" ns "+"
}

/^(;|[ \t]*$)/ {
  next
}

{
  line = $0
  ttl = $2
  # Normalise before de-duplicating
  $2 = "-"
  if (seen[$0]++) {
    next
  }
  print line
}

# If this entry matches a CNAME we've already seen, save it for later
$4 != "CNAME" && cname_count[$1] {
  canonical[canonical_count++] = line
}

$4 == "CNAME" {
  i = cname_count[$5]++
  cname_alias[$5, i] = $1
  match(line, name_ttl_regex)
  cname_record[$5, i] = substr(line, RSTART, RLENGTH)
}

END {
  # Print entries that match CNAMEs we're tracking with the names and TTLs of
  # their respective CNAME records
  for (i = 0; i < canonical_count; i++) {
    $0 = canonical[i]
    follow_cname($1)
  }
}


function follow_cname(cname, _i, _alias)
{
  for (_i = 0; _i < cname_count[cname]; _i++) {
    _alias = cname_alias[cname, _i]
    if (cname_count[_alias]) {
      follow_cname(_alias)
      continue
    }
    # Use sub() to preserve `dig`'s original delimiters
    sub(name_ttl_regex, cname_record[cname, _i], $0)
    print
  }
}

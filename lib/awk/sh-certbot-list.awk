# Parse `certbot certificates` output to tab-separated fields:
# 1. Certificate name
# 2. Domains (format: <name>[,www.<name>][,<other_domain>...])
# 3. Expiry date (format: %Y-%m-%d %H:%M:%S%z)
# 4. Certificate path
# 5. Private key path
BEGIN {
  OFS = "\t"
}

tolower($0) ~ /\<certificate name:/ {
  maybe_print()
  name = val()
  domains = expiry = cert = key = "-"
}

tolower($0) ~ /\<domains:/ {
  split(val(), a, "[[:blank:]]+")
  domains = ""
  # Add certificate name without "www."
  no_www = tolower(name)
  sub(/^www\./, "", no_www)
  add_domain(no_www)
  # Add certificate name with "www."
  add_domain("www." no_www)
  # Add remaining domains
  add_domain()
}

tolower($0) ~ /\<expiry date:/ {
  expiry = val()
  gsub("[[:blank:]]+\\(.*", "", expiry)
}

/\/fullchain\.pem$/ {
  cert = val()
}

/\/privkey\.pem$/ {
  key = val()
}

END {
  maybe_print()
}


function add_domain(d)
{
  for (i in a) {
    if (! d || tolower(a[i]) == tolower(d)) {
      domains = domains (domains ? "," : "") a[i]
      delete a[i]
    }
  }
}

function maybe_print()
{
  if (name) {
    print name, domains, expiry, cert, key
  }
}

function val(_)
{
  _ = $0
  gsub("(^[^:]+:[[:blank:]]+|[[:blank:]]+$)", "", _)
  return (_ ? _ : "-")
}

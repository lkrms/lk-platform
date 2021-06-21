# Parse output from `certbot certificates` and output the following
# tab-separated fields:
# 1. Certificate name
# 2. Domains (sorted, comma-separated)
# 3. Expiry date (format: %Y-%m-%d %H:%M:%S%z)
# 4. Certificate path
# 5. Private key path

BEGIN {
    OFS = "\t"
    "mktemp" | getline temp
    close("mktemp")
    sort = "tr ',' '\\n' | sort -u | tr '\\n' ',' >" temp
}

function val(_) {
    _ = $0
    sub("^[^:]+:[[:blank:]]+", "", _)
    return _
}

function maybe_print() {
    if (name) {
        print name, domains, expiry, cert, key
    }
}

tolower($0) ~ /\<certificate name:/ {
    maybe_print()
    name = val()
    domains = expiry = cert = key = ""
}

tolower($0) ~ /\<domains:/ {
    domains = val()
    gsub("[[:blank:]]+", ",", domains)
    print domains | sort
    close(sort)
    getline domains < temp
    close(temp)
    sub(",$", "", domains)
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

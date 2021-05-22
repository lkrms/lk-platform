# For each record in the package index (e.g. /var/lib/apt/lists/*_Packages):
# - rename `Depends` to `Original_Depends`
# - rename `Recommends` to `Original_Recommends`
# - combine the original values of `Depends` and `Recommends`
# - set `Depends` to the new value
#
# See:
# - https://wiki.debian.org/DebianRepository/Format#A.22Packages.22_Indices
# - https://www.debian.org/doc/debian-policy/ch-controlfields.html

function collect(line) {
    # "Horizontal whitespace (spaces and tabs) may occur immediately before or
    # after the value and is ignored there"
    gsub(/(^[ \t]+|[ \t]+$)/, "", line)
    if (line) {
        depends = (depends ? depends ", " : "") line
    }
}

collecting && /^[ \t]/ { collect($0) }

collecting && /^[^ \t]/ { collecting = 0 }

/^(Depends|Recommends):/ {
    collecting = 1
    line = $0
    sub(/^(Depends|Recommends):/, "", line)
    collect(line)
    $0 = "Original_" $0
}

# "Parsers may accept lines consisting solely of spaces and tabs as paragraph
# separators"
/^[ \t]*$/ {
    if (depends) {
        printf "Depends: %s\n", depends
    }
    collecting = 0
    depends = ""
}

{
    print
}

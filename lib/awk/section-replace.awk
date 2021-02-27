BEGIN {
    S = "[[:blank:]]"
    FS = "(" S "*\\[|\\]" S "*)"
    blank = "^" S "*$"
    section_start = "^" S "*\\[[^][]+\\]" S "*$"
    COMMENT = COMMENT ? COMMENT : "^" S "*#"
    ENTRIES = right(ENTRIES, 1) == "\n" ? ENTRIES : ENTRIES "\n"
}

function right(s, l) {
    substr(s, length(s) - l + 1)
}

function is_blank() {
    return $0 ~ blank
}

function is_comment() {
    return $0 ~ COMMENT
}

function print_section() {
    if (!printed) {
        if (last_blank < last_printed)
            print ""
        print "[" SECTION "]"
        printf "%s", ENTRIES
        printed = 1
        just_printed = 1
    }
    skip = 0
}

$0 ~ section_start && $2 == SECTION {
    skip = 1
    next
}

skip && $0 ~ section_start {
    print_section()
}

skip {
    next
}

is_blank() || is_comment() {
    last_blank = NR
}

{
    if (just_printed && !is_blank() && right(ENTRIES, 2) != "\n\n")
        print ""
    print
    just_printed = 0
    last_printed = NR
}

END {
    ENTRIES = ENTRIES "\n"
    print_section()
}

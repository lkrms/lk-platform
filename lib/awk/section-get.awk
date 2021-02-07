BEGIN {
    S = "[[:blank:]]"
    FS = "(" S "*\\[|\\]" S "*)"
    section_start = "^" S "*\\[[^][]+\\]" S "*$"
    skip = 1
}

$0 ~ section_start && $2 == SECTION {
    skip = 0
    next
}

$0 ~ section_start {
    skip = 1
}

!skip {
    print
}

BEGIN {
    S = "[[:blank:]]"
    section_prefix_re = section_prefix_re ? section_prefix_re : "^" S "*\\[" S "*"
    section_suffix_re = section_suffix_re ? section_suffix_re : S "*\\]" S "*$"
    section_name_re = section_name_re ? section_name_re : "[-[:alnum:]./_]+"
    section_re = section_prefix_re section_name_re section_suffix_re
    skip = 1
}

function maybe_print(str) {
    if (str) {
        printf "%s", str
    }
}

!skip && $0 ~ section_re {
    skip = 1
}

$0 ~ section_re {
    sub(section_prefix_re, "")
    sub(section_suffix_re, "")
    if ($0 ~ section_name_re && $0 == section) {
        skip = 0
        next
    }
}

!skip && $0 ~ "^" S "*$" {
    pending_empty = pending_empty $0 "\n"
    next
}

!skip {
    maybe_print(pending_empty)
    pending_empty = ""
    print
}

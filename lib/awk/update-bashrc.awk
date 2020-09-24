function print_previous() {
    if (previous) {
        print previous
        previous = ""
    }
}

function print_RC_SH(add_newline) {
    if (RC_SH) {
        print (add_newline ? "\n" : "") RC_SH
        RC_SH = ""
    }
}

$0 ~ RC_PATTERN {
    remove = 1
    previous = ""
    next
}

remove {
    remove = 0
    print_RC_SH()
    next
}

/^# Added by / {
    print_previous()
    previous = $0
    next
}

{
    print_previous()
    print
}

END {
    print_previous()
    print_RC_SH(1)
}

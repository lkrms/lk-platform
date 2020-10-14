function print_line(line) {
    if (print_out)
        print line ? line : $0
    else
        lines[++line_count] = line ? line : $0
}

function print_previous() {
    if (previous) {
        print_line(previous)
        previous = ""
    }
}

function print_SSH_CONFIG(add_newline) {
    if (SSH_CONFIG) {
        print_line(SSH_CONFIG (add_newline ? "\n" : ""))
        SSH_CONFIG = ""
    }
}

$0 ~ SSH_PATTERN {
    remove = 1
    previous = ""
    next
}

remove {
    remove = 0
    print_SSH_CONFIG()
}

/^# Added by / {
    print_previous()
    previous = $0
    next
}

{
    print_previous()
    print_line()
}

END {
    print_out = 1
    print_SSH_CONFIG(1)
    for (i = 1; i <= line_count; i++)
        print lines[i]
}

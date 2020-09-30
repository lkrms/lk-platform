BEGIN {
    u[1] = "K"
    u[2] = "M"
    u[3] = "G"
    u[4] = "T"
    u[5] = "P"
    u[6] = "E"
    u[7] = "Z"
    u[8] = "Y"
}

function quote(str, q, q_count, arr, i, outstr) {
    # \47 = single quote
    q = "\47"
    q_count = split(str, arr, q)
    for (i in arr) {
        outstr = outstr q arr[i] q (i < q_count ? "\\" q : "")
    }
    return outstr
}

function human_readable(kb, width, i) {
    i = 1
    while (kb > 1024 && u[i]) {
        kb /= 1024
        i++
    }
    return sprintf("%" width ".1f%s", kb, u[i])
}

/^PRM[[:blank:]]/ {
    program = substr($8, 2, length($8) - 2)
    pss[program] += $24
    count[program] += 1
}
/^SEP([[:blank:]]|$)/ {
    total = 0
    for (program in pss) {
        if (pss[program]) {
            total += pss[program]
            print human_readable(pss[program], 10),
                program,
                (count[program] > 1 ?
                    "(" count[program] " @ " \
                        human_readable(pss[program] / count[program]) \
                    ")" :
                    "") > TEMP
        }
        delete pss[program]
        delete count[program]
    }
    close(TEMP)
    system("sort -h " quote(TEMP))
    print "-----------"
    print human_readable(total, 10)
    print "==========="
}

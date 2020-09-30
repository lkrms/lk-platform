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
    if (match($0, /\(.*\)/)) {
        program = substr($0, RSTART + 1, RLENGTH - 2)
        $0 = substr($0, 1, RSTART) substr($0, RSTART + RLENGTH - 1)
        pss[program] += $24
        count[program] += 1
        if (max[program] < $24) {
            max[program] = $24
        }
    }
}

/^SEP([[:blank:]]|$)/ {
    total = 0
    for (program in pss) {
        if (pss[program]) {
            total += pss[program]
            print human_readable(pss[program], 10),
                program,
                (count[program] > 1 ?
                    "(" count[program] \
                        ", average: " \
                        human_readable(pss[program] / count[program]) \
                        ", max (overall): " \
                        human_readable(max[program]) \
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

function sh(op, arr, _i, _j) {
    printf(prefix "%s=(", op)
    for (_i in arr) {
        printf((_j++ ? " %s" : "%s"), arr[_i])
    }
    printf(")\n")
}

$1 == "Inst" {
    inst[++i] = $2
}

$1 == "Conf" {
    conf[++c] = $2
}

$1 == "Remv" {
    remv[++r] = $2
}

END {
    sh("INST", inst)
    sh("CONF", conf)
    sh("REMV", remv)
    printf(prefix "CHANGES=%s", i + c + r)
}

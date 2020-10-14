# Necessary because ifconfig output on macOS looks like:
# - inet 10.10.10.4 netmask 0xffff0000 broadcast 10.10.255.255
# - inet6 fe80::1c43:b79d:5dfe:c0a4%en0 prefixlen 64 secured scopeid 0x8

BEGIN {
    b["f"] = 4
    b["e"] = 3
    b["c"] = 2
    b["8"] = 1
    b["0"] = 0
}

$1 == ADDRESS_FAMILY && $2 ~ /\/[0-9]+$/ {
    print $2
}

$1 == ADDRESS_FAMILY && $2 ~ /\/0x[0-9a-f]{8}$/ {
    split($2, a, "/0x")
    p=0
    for (i = 1; i <= length(a[2]); i++)
        p += b[substr(a[2], i, 1)]
    printf "%s/%s\n", a[1], p
}

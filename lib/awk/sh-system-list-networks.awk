# Parse output from `ip addr` or `ifconfig` and print IPv4 and IPv6 networks in
# CIDR format.
#
# `ip addr` sample (Ubuntu 18.04):
#
#     2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
#         link/ether 92:66:29:6e:05:91 brd ff:ff:ff:ff:ff:ff
#         inet 192.168.1.180/24 brd 192.168.1.255 scope global eth0
#            valid_lft forever preferred_lft forever
#         inet6 2001:db8::9066:29ff:fe6e:591/64 scope global dynamic mngtmpaddr noprefixroute
#            valid_lft 60sec preferred_lft 20sec
#         inet6 fe80::9066:29ff:fe6e:0591/64 scope link
#            valid_lft forever preferred_lft forever
#
# `ifconfig` sample (macOS Monterey):
#
#     en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
#             options=6463<RXCSUM,TXCSUM,TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
#             ether 92:66:29:6e:05:91 
#             inet6 fe80::9066:29ff:fe6e:0591%en0 prefixlen 64 secured scopeid 0xb 
#             inet6 2001:db8::8d2:d39d:f6cd:a313 prefixlen 64 autoconf secured 
#             inet6 2001:db8::39ef:ab4d:d5cf:c98e prefixlen 64 autoconf temporary 
#             inet 192.168.1.180 netmask 0xffffff00 broadcast 192.168.1.255
#             nd6 options=201<PERFORMNUD,DAD>
#             media: autoselect
#             status: active
#
BEGIN {
  # f = 1111
  mask_bits["f"] = 4
  # e = 1110
  mask_bits["e"] = 3
  # c = 1100
  mask_bits["c"] = 2
  # 8 = 1000
  mask_bits["8"] = 1
  # 0 = 0000
  mask_bits["0"] = 0
}

$1 ~ /^inet6?$/ && $2 !~ /^169\.254\./ {
  if ($2 ~ /\/[0-9]+$/) {
    print $2
  } else if ($3 == "netmask" && $4 ~ /^0x[0-9a-f]{8}$/) {
    # Convert hexadecimal mask (e.g. 0xfffff800) to prefix length
    prefix_bits = 0
    for (i = 3; i <= length($4); i++) {
      prefix_bits += mask_bits[substr($4, i, 1)]
    }
    printf "%s/%s\n", $2, prefix_bits
  } else if ($3 == "prefixlen") {
    # Remove device suffix
    sub(/%.*/, "", $2)
    printf "%s/%s\n", $2, $4
  }
}


include "core";

def to_part:
  sub("^(?<part>\(regex.domainPart)).*"; "\(.part)");

def to_spf($ip):
  "v=spf1 ip4:\($ip.ip4) ip6:\($ip.ip6) include:amazonses.com -all";

.[] | {
  "ip4": [ .ipv4[] | select(test(regex.ipv4PrivateFilter) | not) ] | first,
  "ip4_private": [ .ipv4[] | select(test(regex.ipv4PrivateFilter)) ] | first,
  "ip6": .ipv6 | split("/")[0]
} as $ip | [(
  .label,
  (.tags[] | select(test(regex.domainPart) and
    (to_part as $t | $tags | index($t) != null)))
) | to_part ] |
  if $reverse then
    first | (
      [ $ip.ip4, . + "." + $domain ],
      [ $ip.ip6, . + "." + $domain ]
    )
  else
    (.[] | (
      [ .             , "A", $ip.ip4        , 0 ],
      [ .          , "AAAA", $ip.ip6        , 0 ],
      [ . + ".private", "A", $ip.ip4_private, 0 ]
    )),
    (first |
      [ .           , "TXT", to_spf($ip)    , 0 ])
  end | @tsv

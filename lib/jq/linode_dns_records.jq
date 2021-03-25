def to_part:
  sub($domainPart; "\(.part)");

.[] | {
  "ipv4Public": [ .ipv4[] | select(test($ipv4Private) | not) ] | first,
  "ipv4Private": [ .ipv4[] | select(test($ipv4Private)) ] | first,
  "ipv6": .ipv6 | split("/")[0]
} as $ip | [(
  .label,
  (.tags[] | select(test($domainPart) and
    (to_part as $t | $tags | index($t) != null)))
) | to_part ] |
  if $reverse then
    first | (
      [ $ip.ipv4Public, . + "." + $domain],
      [ $ip.ipv6,       . + "." + $domain]
    )
  else
    .[] | (
      [ .             , "A", $ip.ipv4Public  ],
      [ .          , "AAAA", $ip.ipv6        ],
      [ . + ".private", "A", $ip.ipv4Private ]
    )
  end | @tsv

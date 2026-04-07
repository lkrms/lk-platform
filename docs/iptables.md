# iptables

## DDoS protection

According to [this article][anti-DDoS], dropping invalid packets in the `mangle`
table is essential to mitigating DDoS attacks at line rate:

```bash
iptables -t mangle -A PREROUTING -m conntrack --ctstate INVALID -m comment --comment "block invalid" -j DROP
iptables -t mangle -A PREROUTING -p tcp -m tcp ! --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -m comment --comment "block new without SYN" -j DROP
iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -m comment --comment "block new with small MSS" -j DROP
```

## TCP flags

Of the 6 TCP flags surfaced by `iptables`, [`netfilter` code][netfilter] in
recent Linux kernels ignores `PSH` and considers the other 5 `INVALID` in any
combination other than:

| `SYN` | `ACK` | `FIN` | `RST` | `URG` | `PSH` |
| ----- | ----- | ----- | ----- | ----- | ----- |
| ✗     |       |       |       |       | -     |
| ✗     |       |       |       | ✗     | -     |
| ✗     | ✗     |       |       |       | -     |
|       |       |       | ✗     |       | -     |
|       | ✗     |       | ✗     |       | -     |
|       | ✗     | ✗     |       |       | -     |
|       | ✗     | ✗     |       | ✗     | -     |
|       | ✗     |       |       | ✗     | -     |
|       | ✗     |       |       |       | -     |

So, as long as `INVALID` packets are dropped, the "block packets with bogus TCP
flags" rules one might find in `iptables` tutorials are no longer necessary.

> [!TIP]
>
> Rules like this:
>
> ```bash
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags ALL ALL -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags ALL NONE -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags ALL FIN,PSH,URG -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags ALL FIN,SYN,RST,ACK,URG -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags FIN,ACK FIN -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags FIN,RST FIN,RST -j DROP
> iptables -t mangle -A PREROUTING -p tcp -m tcp --tcp-flags ALL FIN,SYN,PSH,URG -j DROP
> ```
>
> can be replaced with one rule like this:
>
> ```bash
> iptables -t filter -m conntrack --ctstate INVALID -j DROP
> ```

[anti-DDoS]: https://itgala.xyz/iptables-antiddos-protection/
[netfilter]:
  https://github.com/torvalds/linux/blob/4b97bac0756a81cda5afd45417a99b5bccdcff67/net/netfilter/nf_conntrack_proto_tcp.c#L709

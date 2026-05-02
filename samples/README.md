# Sample runs

Real `dns-bench.ps1` outputs from various configurations. Useful for:

- Seeing what the script produces before you run it
- Comparing your numbers against a known baseline
- Spotting regressions if the script's output format ever changes

## [windows11-cloudflare-doh.log](windows11-cloudflare-doh.log)

**Configuration:** Windows 11, system DNS configured for Cloudflare with DoH enabled (1.1.1.1 / 1.0.0.1 IPv4 + 2606:4700:4700::1111 / ::1001 IPv6, all four templates auto-upgrading to `https://cloudflare-dns.com/dns-query`).

**Default 5 passes, 12 domains, 7 resolvers, run from a freshly-extracted GitHub zip.**

Final ranking:

```
Resolver          ColdMs WarmMs OverallMs
--------          ------ ------ ---------
Router              15.5    2.9       5.4   <- warm = LAN cache, ignore
Cloudflare-v6         16   15.7      15.7
Current (DoH)       17.9   15.9      16.3
Cloudflare-direct   19.5   19.2      19.2
Quad9               20.5     20      20.1
Google              27.5   22.8      23.7
OpenDNS             49.9   44.1      45.2

Current (DoH) is 2.9 ms faster than Cloudflare-direct (likely connection reuse)
```

### Three things this run demonstrates

1. **DoH beats plain UDP to the same provider.** `Current (DoH)` (16.3) vs `Cloudflare-direct` (19.2) is a ~3ms win for DoH, attributed to HTTP/2 session reuse against an already-warm `cloudflare-dns.com` connection.
2. **IPv6 Cloudflare is ~3.5ms ahead of IPv4 Cloudflare** at this location (15.7 vs 19.2 OverallMs). Anycast routing lands on a closer PoP via the v6 path on this network.
3. **OpenDNS is a regional outlier** (~25ms slower than everyone else). The closest OpenDNS anycast PoP isn't in this user's region; in other geographies it competes well. This is exactly the kind of finding the benchmark is meant to surface — public resolver "best" rankings are network-dependent.

### Things to ignore in the ranking

- The Router's WarmMs (2.9). After Pass 1, every test domain is already cached on the router, so passes 2-5 measure LAN cache hits, not real DNS. Pass 1's 15.5ms is the only honest router number.
- OpenDNS's variance (stdev 4.6-12.7ms) and its extreme outlier max values. The path is unstable as well as slow at this location.

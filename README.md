# dns-bench-windows

A PowerShell script that benchmarks DNS resolvers from a Windows machine — including DoH (DNS-over-HTTPS) — and tells you which one is actually fastest from your network.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)](#requirements)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D4)](#requirements)

## Why

GRC's DNS Benchmark v2 went paid ($9.95) in 2026, and most "fastest DNS" benchmark tools either don't exist on Windows, can't test DoH, or are abandonware. This script does the comparison natively using `Resolve-DnsName`, takes 30 seconds, and writes a log so you can review results later.

It also tests your **currently configured system resolver** against alternatives — so if you have DoH enabled in Windows 11, you'll see the real end-to-end latency you actually experience, not just the theoretical speed of public resolver IPs.

## Features

- Tests Cloudflare, Quad9, Google, OpenDNS, and your router by default
- Includes a "Current (DoH)" entry that uses your configured resolver — perfect for comparing your DoH setup against plain alternatives
- Auto-detects which direct resolver matches your system DNS and compares against it
- IPv4 + IPv6 resolver support
- 5 passes per resolver with configurable domain list (override with `-Passes`)
- Reports cold (uncached) vs warm (cached) lookup times separately
- Standard deviation column to spot flaky paths
- Timestamped logs to your Desktop (override with `-LogPath`)
- Dumps your current Windows DNS config and DoH templates so the log captures what was actually tested
- PowerShell 5.1 compatible (works on stock Windows 10 and 11)

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built in) or PowerShell 7+
- DoH cmdlets work on Windows 11 and Windows 10 22H2+ (script gracefully falls back if unavailable)

## Usage

### Quick install (one-liner)

From an open PowerShell window:

```powershell
irm https://raw.githubusercontent.com/hervad/dns-bench-windows/main/dns-bench.ps1 -OutFile "$env:USERPROFILE\Desktop\dns-bench.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\dns-bench.ps1"
```

### Manual install

1. Download [`dns-bench.ps1`](dns-bench.ps1) to your Desktop (or anywhere convenient).
2. Open PowerShell (`Win+X` → Terminal/PowerShell).
3. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\dns-bench.ps1"
   ```

That's it. Takes about 30 seconds. A timestamped log is saved to your Desktop.

> **Tip:** Don't double-click the `.ps1`. If it crashes early, the window closes before you see the error. Always launch from an already-open PowerShell window.

### Parameters

```powershell
.\dns-bench.ps1 [-Passes <int>] [-LogPath <string>] [-NoPause]
```

- `-Passes` — number of measurement passes (default `5`)
- `-LogPath` — where to write the transcript (default: timestamped file on Desktop)
- `-NoPause` — skip the "press any key" prompt at the end (for CI / scripted use)

Run `Get-Help .\dns-bench.ps1 -Full` for the full help block.

## Customizing the resolver list

Edit the `$resolverNames` and `$resolverServers` arrays near the top of the script. They're parallel arrays — index `i` of the names array pairs with index `i` of the servers array.

To find your ISP's DNS:

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4
ipconfig /all
```

`$null` in the servers array means "use the system resolver" — keep that entry to benchmark your live config.

The script includes a commented-out example near the resolver lists showing how to append your ISP's DNS.

## Sample output

Real run on a Windows 11 machine with system DNS configured for Cloudflare DoH (1.1.1.1 / 2606:4700:4700::1111):

### Per-pass detail (cold vs warm)

```
--- Pass 1 ---  (cold, after Clear-DnsClientCache)
Current (DoH)        system                     avg:   18.5ms  min:   11.3ms  max:   39.5ms  stdev:   10.2ms
Cloudflare-direct    1.1.1.1                    avg:   25.1ms  min:     18ms  max:   62.4ms  stdev:     12ms
Cloudflare-v6        2606:4700:4700::1111       avg:   13.5ms  min:   10.5ms  max:     21ms  stdev:    2.6ms
Quad9                9.9.9.9                    avg:   24.3ms  min:   18.2ms  max:   52.7ms  stdev:    9.4ms
Google               8.8.8.8                    avg:     29ms  min:   18.5ms  max:   57.8ms  stdev:   11.7ms
Router               192.168.0.1                avg:   24.7ms  min:   21.2ms  max:   40.8ms  stdev:    5.3ms

--- Pass 5 ---  (warm)
Current (DoH)        system                     avg:   14.3ms  min:   11.7ms  max:   20.1ms  stdev:      2ms
Cloudflare-direct    1.1.1.1                    avg:   27.3ms  min:   17.6ms  max:   52.8ms  stdev:    9.3ms
Cloudflare-v6        2606:4700:4700::1111       avg:   13.8ms  min:   12.7ms  max:   15.3ms  stdev:    0.9ms
Quad9                9.9.9.9                    avg:   20.5ms  min:   18.6ms  max:   24.1ms  stdev:    1.7ms
Google               8.8.8.8                    avg:   25.7ms  min:   19.7ms  max:   44.6ms  stdev:    7.6ms
Router               192.168.0.1                avg:      3ms  min:      2ms  max:    3.9ms  stdev:    0.6ms
```

### Final ranking

```
=== Final ranking (avg of all passes) ===

Resolver           ColdMs WarmMs OverallMs
--------           ------ ------ ---------
Router               24.7    4.9       8.9
Cloudflare-v6        13.5   13.8      13.8
Current (DoH)        18.5   13.8      14.7
Cloudflare-direct    25.1   21.3      22.1
Quad9                24.3   22.6      22.9
Google                 29   25.5      26.2

Fastest overall: Router at 8.9ms avg
(Note: Router entries are usually misleading — they cache after pass 1.)
Current (DoH) is 7.4 ms faster than Cloudflare-direct (likely connection reuse)
```

In this run, **DoH was actually faster than plain UDP** — likely due to TLS/H2 connection reuse against an already-warm cloudflare-dns.com session. Cloudflare-v6 narrowly beats it because the system happened to be using the IPv4 path.

## Interpreting the results

Read the table carefully — the "winner" can be misleading.

**ColdMs** = pass 1 latency, after `Clear-DnsClientCache`. This represents new domain lookups. **This is the number that matters for real-world page-load feel.**

**WarmMs** = passes 2-5 average. Most resolvers will be much faster here because their own caches now contain your test domains.

**Router caveat:** if you're benchmarking your router's IP, it usually "wins" with absurdly low warm numbers (~3-7ms). This is a measurement artifact — your router caches everything Windows queried through it during pass 1, so subsequent passes hit local cache, not real DNS. Look at **ColdMs only** for an honest comparison of your router's path.

**stdev** column: lower is better. >10ms means inconsistent performance.

**DoH vs direct comparison** at the end shows whether your encrypted DNS is faster, slower, or equivalent to plain UDP against the same provider. The script auto-detects which direct resolver matches your system config (it won't hardcode Cloudflare). In some setups (e.g., DS-Lite/CGNAT) DoH is actually *faster* because it bypasses tunnel overhead.

## What this script does NOT do

- **Cannot directly benchmark DoH templates against each other.** Windows' DNS client picks DoH templates based on the IP you query, so you can't easily compare Cloudflare DoH vs Quad9 DoH side-by-side. Only the system-configured resolver is tested with DoH; everything else uses plain UDP/53.
- **Cannot test DNS-over-TLS (DoT)** — Windows doesn't expose this natively.
- **Doesn't test DNS-over-QUIC (DoQ)** — same reason.
- **Won't measure browser-level DoH** (Firefox/Chrome built-in DoH bypasses the Windows resolver entirely).

## Troubleshooting

**Window closes instantly when I run it:**
You're double-clicking. Don't. Open PowerShell first, then run the command in the Usage section.

**"Running scripts is disabled on this system":**
Use `-ExecutionPolicy Bypass` as shown in Usage. This applies only to that one execution; nothing is permanently changed.

**"DoH cmdlets not available":**
You're on Windows 10 < 22H2 or an older build. The benchmark itself still works; only the DoH config dump is skipped.

**One resolver shows ALL QUERIES FAILED:**
That resolver is unreachable from your network. For IPv6 entries, check that you actually have IPv6 connectivity (`Test-NetConnection ipv6.google.com`).

## License

MIT — see [LICENSE](LICENSE).

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for ideas and constraints (chiefly: keep PowerShell 5.1 compatibility, since it's the default on stock Windows installs).

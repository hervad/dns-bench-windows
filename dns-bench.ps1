#Requires -Version 5.1

<#
.SYNOPSIS
    Benchmark DNS resolvers on Windows, including DNS-over-HTTPS (DoH).

.DESCRIPTION
    Measures DNS lookup latency for a configurable list of resolvers using
    Resolve-DnsName. Includes a "Current (DoH)" entry that uses the system
    resolver, so you can compare your live config (including DoH) against
    plain-UDP alternatives.

    Reports cold (first pass, after Clear-DnsClientCache) vs warm (cached)
    lookup times separately, and writes a timestamped transcript to your
    Desktop.

    Notes on interpretation:
      - Pass 1 is cold (cache cleared); passes 2..N show warm/cached behavior
      - Your router will look "fastest" warm because it caches everything
        Windows queried through it. Measurement artifact, not real performance
        for new domains. Look at ColdMs for an honest comparison.
      - stdev = consistency. Lower is better. >10ms = flaky path.

.PARAMETER Passes
    Number of measurement passes per resolver. Default: 5.

.PARAMETER LogPath
    Where to write the transcript log. Default: dns-bench-<timestamp>.log on
    the current user's Desktop.

.PARAMETER NoPause
    Skip the "Press any key to exit" prompt at the end. Use when running from
    an already-open PowerShell window or from CI.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File dns-bench.ps1

.EXAMPLE
    .\dns-bench.ps1 -Passes 10 -NoPause

.LINK
    https://github.com/hervad/dns-bench-windows
#>

[CmdletBinding()]
param(
    [int]$Passes = 5,
    [string]$LogPath = "$env:USERPROFILE\Desktop\dns-bench-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    [switch]$NoPause
)

# Trap any error so the window stays open if something crashes (unless -NoPause)
trap {
    Write-Host "`n=== SCRIPT ERROR ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    if (-not $NoPause) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 1
}

$ErrorActionPreference = "Continue"

# -----------------------------------------------------------------------------
# CONFIGURATION -- edit these lists to suit your needs
# -----------------------------------------------------------------------------

# Resolvers to compare. $null = use the system resolver (DoH path if enabled).
# Use parallel arrays for PowerShell 5.1 compatibility -- index i of names
# pairs with index i of servers.
$resolverNames = @(
    "Current (DoH)",
    "Cloudflare-direct",
    "Cloudflare-v6",
    "Quad9",
    "Google",
    "OpenDNS",
    "Router"
)

$resolverServers = @(
    $null,                  # uses system-configured resolver (DoH if enabled)
    "1.1.1.1",
    "2606:4700:4700::1111",
    "9.9.9.9",
    "8.8.8.8",
    "208.67.222.222",
    "192.168.0.1"           # change to your router IP if different
)

# To benchmark your ISP's DNS, append it to both arrays. Find your ISP DNS via:
#     Get-DnsClientServerAddress -AddressFamily IPv4
# Example (Play, a Polish ISP using IPv6 DNS over DS-Lite):
#   $resolverNames   += "MyISP-v6"
#   $resolverServers += "2a02:a302:0:1::10"

# Mixed domain set: search, dev, gaming, streaming, social
$domains = @(
    "google.com",         "github.com",       "reddit.com",
    "youtube.com",        "twitch.tv",        "steamcommunity.com",
    "discord.com",        "cloudflare.com",   "wikipedia.org",
    "stackoverflow.com",  "nvidia.com",       "anthropic.com"
)

# -----------------------------------------------------------------------------
# BENCHMARK
# -----------------------------------------------------------------------------

Start-Transcript -Path $LogPath -Force | Out-Null

Write-Host "DNS Benchmark - $(Get-Date)" -ForegroundColor Cyan
Write-Host "Log: $LogPath" -ForegroundColor DarkGray
Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray
Write-Host "Domains: $($domains.Count) | Passes: $Passes`n" -ForegroundColor DarkGray

Write-Host "=== Current Windows DNS configuration ===" -ForegroundColor Magenta
$systemDnsV4 = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses -and $_.InterfaceAlias -notlike "*Loopback*" }
$systemDnsV4 | Format-Table InterfaceAlias, ServerAddresses -AutoSize | Out-Host

$systemDnsV6 = Get-DnsClientServerAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses -and $_.InterfaceAlias -notlike "*Loopback*" }
$systemDnsV6 | Format-Table InterfaceAlias, ServerAddresses -AutoSize | Out-Host

Write-Host "=== DoH templates (DNS-over-HTTPS) ===" -ForegroundColor Magenta
if (Get-Command Get-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
    Get-DnsClientDohServerAddress |
        Format-Table ServerAddress, DohTemplate, AllowFallbackToUdp, AutoUpgrade -AutoSize | Out-Host
} else {
    Write-Host "DoH cmdlets not available (requires Win11 or Win10 22H2+)" -ForegroundColor DarkYellow
}

Write-Host "Running $Passes passes...`n" -ForegroundColor Cyan

Clear-DnsClientCache -ErrorAction SilentlyContinue

# Initialize results storage
$results = @{}
for ($i = 0; $i -lt $resolverNames.Count; $i++) {
    $results[$resolverNames[$i]] = @()
}

for ($pass = 1; $pass -le $Passes; $pass++) {
    Write-Host "--- Pass $pass ---" -ForegroundColor Yellow

    for ($i = 0; $i -lt $resolverNames.Count; $i++) {
        $name = $resolverNames[$i]
        $dns  = $resolverServers[$i]
        $times = @()
        $errors = 0

        foreach ($domain in $domains) {
            try {
                if ($null -eq $dns) {
                    # Query through system resolver (uses DoH if configured)
                    $t = Measure-Command {
                        Resolve-DnsName -Name $domain -Type A -DnsOnly -NoHostsFile -ErrorAction Stop | Out-Null
                    }
                } else {
                    $t = Measure-Command {
                        Resolve-DnsName -Name $domain -Server $dns -Type A -DnsOnly -NoHostsFile -ErrorAction Stop | Out-Null
                    }
                }
                $times += $t.TotalMilliseconds
            } catch {
                $errors++
            }
        }

        if ($times.Count -gt 0) {
            $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
            $min = [math]::Round(($times | Measure-Object -Minimum).Minimum, 1)
            $max = [math]::Round(($times | Measure-Object -Maximum).Maximum, 1)

            # Sample standard deviation (n-1)
            if ($times.Count -gt 1) {
                $mean = ($times | Measure-Object -Average).Average
                $sumSq = 0.0
                foreach ($v in $times) { $sumSq += [math]::Pow($v - $mean, 2) }
                $stdev = [math]::Round([math]::Sqrt($sumSq / ($times.Count - 1)), 1)
            } else {
                $stdev = 0
            }

            $errStr = if ($errors -gt 0) { " [$errors errors]" } else { "" }
            $serverLabel = if ($dns) { $dns } else { "system" }

            Write-Host ("{0,-20} {1,-26} avg: {2,6}ms  min: {3,6}ms  max: {4,6}ms  stdev: {5,6}ms{6}" -f `
                $name, $serverLabel, $avg, $min, $max, $stdev, $errStr)

            $results[$name] += $avg
        } else {
            Write-Host ("{0,-20} {1,-26} ALL QUERIES FAILED" -f $name, $dns) -ForegroundColor Red
        }
    }
    Write-Host ""
    Start-Sleep -Milliseconds 500
}

# -----------------------------------------------------------------------------
# RANKING
# -----------------------------------------------------------------------------

Write-Host "=== Final ranking (avg of all passes) ===" -ForegroundColor Green

$ranking = @()
foreach ($name in $resolverNames) {
    $values = $results[$name]
    if ($values.Count -gt 0) {
        $overall  = [math]::Round(($values | Measure-Object -Average).Average, 1)
        $coldPass = [math]::Round($values[0], 1)
        if ($values.Count -gt 1) {
            $warmValues = $values | Select-Object -Skip 1
            $warmAvg = [math]::Round(($warmValues | Measure-Object -Average).Average, 1)
        } else {
            $warmAvg = $coldPass
        }

        $ranking += [PSCustomObject]@{
            Resolver  = $name
            ColdMs    = $coldPass
            WarmMs    = $warmAvg
            OverallMs = $overall
        }
    }
}

$ranking | Sort-Object OverallMs | Format-Table -AutoSize | Out-Host

$winner = $ranking | Sort-Object OverallMs | Select-Object -First 1
if ($winner) {
    Write-Host "Fastest overall: $($winner.Resolver) at $($winner.OverallMs)ms avg" -ForegroundColor Green
    Write-Host "(Note: Router entries are usually misleading -- they cache after pass 1.)" -ForegroundColor DarkGray
}

# Compare DoH against whichever direct resolver matches the system config.
# This auto-detects the user's configured DNS instead of hardcoding Cloudflare.
$systemServers = @()
if ($systemDnsV4) { $systemServers += $systemDnsV4.ServerAddresses }
if ($systemDnsV6) { $systemServers += $systemDnsV6.ServerAddresses }

$systemMatchName = $null
for ($i = 1; $i -lt $resolverNames.Count; $i++) {
    if ($resolverServers[$i] -and ($systemServers -contains $resolverServers[$i])) {
        $systemMatchName = $resolverNames[$i]
        break
    }
}

$current = $ranking | Where-Object { $_.Resolver -eq "Current (DoH)" }
$direct  = $null
if ($systemMatchName) {
    $direct = $ranking | Where-Object { $_.Resolver -eq $systemMatchName }
}

if ($current -and $direct) {
    $overhead = [math]::Round($current.OverallMs - $direct.OverallMs, 1)
    if ($overhead -gt 0) {
        Write-Host "Current (DoH) vs $($systemMatchName): +$overhead ms overhead" -ForegroundColor DarkYellow
    } else {
        Write-Host "Current (DoH) is $([math]::Abs($overhead)) ms faster than $systemMatchName (likely connection reuse)" -ForegroundColor DarkGreen
    }
} elseif ($current) {
    Write-Host "(No matching direct resolver in test list -- skipping DoH-vs-direct comparison.)" -ForegroundColor DarkGray
}

Stop-Transcript | Out-Null

Write-Host "`nLog saved to: $LogPath" -ForegroundColor Cyan
if (-not $NoPause) {
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

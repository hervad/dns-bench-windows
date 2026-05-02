# Contributing

PRs welcome. Open an issue first if you're planning a larger change.

## Reasonable additions

- Additional public resolvers (NextDNS, AdGuard DNS, ControlD, etc.)
- DoT/DoQ testing if a Windows-native way emerges
- JSON/CSV output formats (in addition to the transcript log)
- A small companion script to A/B test by switching system DNS between two resolvers and running the benchmark on each

## Constraints

- **PowerShell 5.1 compatibility.** It's the default on stock Windows installs and most users won't have PS7. Avoid PS7-only syntax (ternary `?:`, null-coalescing `??`, pipeline chain operators `&&`/`||`, `ForEach-Object -Parallel`).
- **Keep it single-file.** No module structure, no external dependencies. The whole point is "drop one .ps1 on your Desktop and run it."
- **Pass PSScriptAnalyzer cleanly.** CI runs `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning` against [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1) on every PR. Run it locally first:

  ```powershell
  Install-Module PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path .\dns-bench.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
  ```

- **Don't break the cold/warm methodology.** Pass 1 must run after `Clear-DnsClientCache`; subsequent passes must not re-clear it. The cold-vs-warm split is the only way the router caveat can be honestly explained.

## Testing

Run on at least one Windows 10 and one Windows 11 machine if possible. The DoH cmdlet branch (`Get-DnsClientDohServerAddress`) needs Win10 22H2+ to exercise.

Quick smoke test from PowerShell:

```powershell
.\dns-bench.ps1 -Passes 2 -NoPause
```

Two passes is enough to verify cold/warm reporting works without sitting through five.

## Code style

- Match the surrounding style. The script uses parallel `$resolverNames` / `$resolverServers` arrays for PS 5.1 ordering reasons — don't switch to `[ordered]@{}` without thinking through the consequences.
- Keep the configuration block (resolvers, domains) at the top, above the benchmark code, so users can edit without scrolling.
- Comments explain *why*, not *what*. Don't narrate the code.

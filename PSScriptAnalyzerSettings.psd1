@{
    # Write-Host is the only reliable way to produce colored console output
    # in PowerShell 5.1 — appropriate for this interactive script.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
}

[CmdletBinding()]
param(
    [switch]$DiscoveryOnly,
    [switch]$DryRun,
    [switch]$FakeCli,
    [switch]$Smoke,
    [switch]$AllowPaidCalls,

    [ValidateRange(1, 600)]
    [int]$SmokeTimeoutSeconds = 60,

    [string]$SmokeResultPath
)

$providerTest = Join-Path $PSScriptRoot 'Test-LLMProviders.ps1'
& $providerTest @PSBoundParameters
exit $LASTEXITCODE

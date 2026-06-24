[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $projectRoot 'src/lib/integrations/ProviderRegistry.ps1')

$test = New-VorceTestContext -Name 'ProviderAliases'

$canonicalIds = @(
    'gemini_cli'
    'claude_code'
    'codex_orchestrator'
    'kiro_cli'
    'cline_cli'
    'copilot_cli'
    'cursor_agent'
    'jules'
)
$aliases = [ordered]@{
    gemini = 'gemini_cli'
    claude = 'claude_code'
    codex = 'codex_orchestrator'
    codex_cli = 'codex_orchestrator'
    kiro = 'kiro_cli'
    cline = 'cline_cli'
    copilot = 'copilot_cli'
    cursor = 'cursor_agent'
    'cursor-agent' = 'cursor_agent'
    jules_cli = 'jules'
    jules_extern = 'jules'
}

foreach ($providerId in $canonicalIds) {
    Write-VorceTestResult `
        -Context $test `
        -Message "Kanonische ID bleibt stabil: $providerId" `
        -Passed ((Resolve-VorceProviderId -ProviderName $providerId) -eq $providerId)
}

foreach ($entry in $aliases.GetEnumerator()) {
    Write-VorceTestResult `
        -Context $test `
        -Message "Legacy-Alias wird normalisiert: $($entry.Key)" `
        -Passed ((Resolve-VorceProviderId -ProviderName $entry.Key -WarningAction SilentlyContinue) -eq $entry.Value)
}

Write-VorceTestResult -Context $test -Message 'Gross-/Kleinschreibung und Whitespace werden normalisiert' -Passed $(
    (Resolve-VorceProviderId -ProviderName '  GeMiNi  ' -WarningAction SilentlyContinue) -eq 'gemini_cli'
)

$unknown = Resolve-VorceProviderId -ProviderName 'hermes_cli'
Write-VorceTestResult -Context $test -Message 'Unbekannter Provider liefert strukturiert unknown_provider' -Passed $(
    $unknown.success -eq $false -and
    $unknown.provider_id -eq $null -and
    $unknown.requested_provider -eq 'hermes_cli' -and
    $unknown.error_class -eq 'unknown_provider'
)

$global:VorceProviderAliasWarnings = $null
$warnings = @()
$null = Resolve-VorceProviderId -ProviderName 'gemini' -WarningVariable +warnings
$null = Resolve-VorceProviderId -ProviderName ' GEMINI ' -WarningVariable +warnings
Write-VorceTestResult -Context $test -Message 'Legacy-Alias warnt hoechstens einmal pro Session' -Passed $(
    @($warnings).Count -eq 1
)

$activeFiles = @(
    (Join-Path $projectRoot 'src/lib/integrations/ProviderRegistry.ps1')
    (Join-Path $projectRoot 'src/lib/integrations/AgentRunner.ps1')
    (Join-Path $projectRoot 'src/lib/engines/QuotaManager.ps1')
)
$resolverDefinitions = 0
foreach ($file in $activeFiles) {
    $resolverDefinitions += @(
        Select-String -LiteralPath $file -Pattern '^\s*function\s+Resolve-VorceProviderId\b'
    ).Count
}
$runnerText = Get-Content -LiteralPath $activeFiles[1] -Raw
$quotaText = Get-Content -LiteralPath $activeFiles[2] -Raw
Write-VorceTestResult -Context $test -Message 'Resolve-VorceProviderId existiert im aktiven Code genau einmal' -Passed $(
    $resolverDefinitions -eq 1
)
Write-VorceTestResult -Context $test -Message 'Runner und QuotaManager nutzen den zentralen Resolver' -Passed $(
    $runnerText -match 'Resolve-VorceProviderId' -and
    $quotaText -match 'Resolve-VorceProviderId'
)

Complete-VorceTest -Context $test

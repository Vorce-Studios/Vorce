# src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__ContextGathering.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Synchronisiere System-Kontext..." -ForegroundColor Gray

# Importiere notwendige Module
if (-not (Get-Command Sync-VorceGitHubIssues -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/github-client.ps1")
}
if (-not (Get-Command Sync-JulesSessionsState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/jules-client.ps1")
}

$repo = $Config.repository

# 1. Sync Jules & GitHub
Sync-JulesSessionsState -State $GlobalState -Config $Config
Sync-VorceGitHubIssues -Repo $repo -Config $Config
Sync-VorcePullRequests -Repo $repo -Config $Config

$SubState.artifacts += @{
    type = "SyncSummary"
    timestamp = (Get-Date).ToString('o')
    status = "OK"
}

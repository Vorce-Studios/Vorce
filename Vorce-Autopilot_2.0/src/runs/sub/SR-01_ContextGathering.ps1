# SR-01_ContextGathering.ps1
# Phase: Planning
# Aufgabe: Synchronisation von GitHub Issues, Pull Requests und Jules-Sessions

param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "[SUB-RUN] Starte Context Gathering (GitHub & Jules Sync)..." -ForegroundColor Cyan

# Importiere notwendige Module falls nicht global verfügbar
if (-not (Get-Command Sync-VorceGitHubIssues -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/github-client.ps1")
}
if (-not (Get-Command Sync-JulesSessionsState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "../../lib/jules-client.ps1")
}

$repo = $Config.repository

# 1. Sync Jules Sessions
Write-Host "[PLANNING-SYNC] Abgleichen der Jules-Sessions..." -ForegroundColor DarkGray
Sync-JulesSessionsState -State $GlobalState -Config $Config

# 2. Sync GitHub Issues
Write-Host "[PLANNING-SYNC] Abgleichen der GitHub Issues ($repo)..." -ForegroundColor DarkGray
Sync-VorceGitHubIssues -Repo $repo -Config $Config

# 3. Sync Pull Requests
Write-Host "[PLANNING-SYNC] Abgleichen der Pull Requests..." -ForegroundColor DarkGray
Sync-VorcePullRequests -Repo $repo -Config $Config

# Artefakte speichern
$SubState.artifacts += @{
    name = "ContextSnapshot"
    timestamp = (Get-Date).ToString('o')
    issue_count = @(Get-Content -Path (Join-Path $PSScriptRoot "../../var/db/github-issues.json") -ErrorAction SilentlyContinue | ConvertFrom-Json).Count
}

Write-Host "[SUB-RUN] Context Gathering abgeschlossen." -ForegroundColor Green

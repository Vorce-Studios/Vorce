# src/runs/SUB-RUN/SUB-RUN-01_MR-02_Monitoring__SystemHealthCheck.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)
Write-Host "[SUB-RUN] Fuehre System Health Check durch..." -ForegroundColor Gray
if (-not (Get-Command Sync-VorceGitHubIssues -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "../../lib/github-client.ps1") }
Sync-VorceGitHubIssues -Repo $Config.repository -Config $Config

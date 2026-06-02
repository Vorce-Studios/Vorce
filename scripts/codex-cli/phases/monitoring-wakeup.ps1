# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Check running Jules sessions, PRs, merge conflicts

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
. (Join-Path $script:LibDir "autopilot-prompts.ps1")

function Add-DecisionPending {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Context
    )

    $exists = $State.decisions_pending | Where-Object { $_.topic -eq $Topic }
    if (-not $exists) {
        $State.decisions_pending += @([ordered]@{
            topic      = $Topic
            context    = $Context
            created_at = (Get-Date -Format 'o')
        })
        Write-Host "[MONITOR] Entscheidung hinzugefuegt: $Topic" -ForegroundColor Yellow
    }
}

function Invoke-MonitoringWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[MONITOR] ========== Monitoring Wake-Up ==========" -ForegroundColor Blue

    # 1. PRs & Sessions Context
    $prsData = gh pr list --repo $repo --state open --json number,title,mergeable,statusCheckRollup --limit 50
    $sessionsData = $State.active_delegations | ConvertTo-Json -Depth 5

    # 2. Run Monitor Task
    $promptVars = @{
        repo     = $repo
        prs      = $prsData
        sessions = $sessionsData
    }
    $monitorPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey "monitoring_prompt" -Variables $promptVars
    $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$monitorPrompt"

    Write-Host "[MONITOR] Sende Monitoring-Anfrage an CEO Alpha..." -ForegroundColor Cyan
    $result = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "monitoring" -DryRun:$DryRun -Prompt $fullPrompt -State $State
    
    if ($result.success) {
        Write-Host "[MONITOR] CEO Alpha Monitoring abgeschlossen." -ForegroundColor Green
    }

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State
}

# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Granular working sessions for health checks

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
. (Join-Path $script:LibDir "autopilot-prompts.ps1")

function Invoke-MonitoringWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[MONITOR] ========== Monitoring Wake-Up (Granular) ==========" -ForegroundColor Blue

    $monitoringContext = ""
    $prsData = gh pr list --repo $repo --state open --json number,title,mergeable,statusCheckRollup --limit 50
    $sessionsData = $State.active_delegations | ConvertTo-Json -Depth 5

    if ($Config.PSObject.Properties.Name -contains "monitoring_sequence") {
        foreach ($step in $Config.monitoring_sequence) {
            Write-Host "[MONITOR] Schritt: $($step.label) ($($step.tier))" -ForegroundColor Cyan
            $promptVars = @{ repo = $repo; prs = $prsData; sessions = $sessionsData; context = $monitoringContext }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "monitoring" -DryRun:$DryRun -Prompt $fullPrompt -State $State -AlphaTierOverride $step.tier
            if ($stepResult.success) {
                $monitoringContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
            }
        }
    }

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State
    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Magenta
}

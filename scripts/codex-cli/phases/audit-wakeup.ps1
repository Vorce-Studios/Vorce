# scripts/codex-cli/phases/audit-wakeup.ps1
# Audit Mode: Granular working sessions for independent review

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
. (Join-Path $script:LibDir "autopilot-prompts.ps1")

function Invoke-AuditWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[AUDIT] ========== Audit Wake-Up (Granular) ==========" -ForegroundColor Blue

    $auditContext = ""
    $issuesData = gh issue list --repo $repo --state open --json number,title --limit 50
    $prsData = gh pr list --repo $repo --state open --json number,title,mergeable --limit 50
    $delegationsData = $State.active_delegations | ConvertTo-Json -Depth 3

    if ($Config.PSObject.Properties.Name -contains "audit_sequence") {
        foreach ($step in $Config.audit_sequence) {
            Write-Host "[AUDIT] Schritt: $($step.label) ($($step.tier))" -ForegroundColor Cyan
            $promptVars = @{ repo = $repo; issues = $issuesData; prs = $prsData; delegations = $delegationsData; context = $auditContext }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "audit" -DryRun:$DryRun -Prompt $fullPrompt -State $State -BetaTierOverride $step.tier
            if ($stepResult.success) {
                $auditContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
            } else {
                Write-Warning "[AUDIT] Schritt $($step.label) fehlgeschlagen."
            }
        }
    }

    Write-Host "[AUDIT] ========== Audit abgeschlossen ==========" -ForegroundColor Magenta
}

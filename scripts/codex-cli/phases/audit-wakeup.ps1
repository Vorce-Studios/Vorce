# scripts/codex-cli/phases/audit-wakeup.ps1
# Beta CEO Audit Mode: Independent review via centralized config prompts

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
. (Join-Path $script:LibDir "autopilot-prompts.ps1")

function Add-AuditDecisionPending {
    param([object]$State, [string]$Topic, [string]$Context, [string]$RemediationCommand = "")
    $exists = $State.decisions_pending | Where-Object { $_.topic -eq $Topic }
    if (-not $exists) {
        $State.decisions_pending += @([ordered]@{
            topic               = $Topic
            context             = $Context
            remediation_command = $RemediationCommand
            created_at          = (Get-Date -Format 'o')
            owner               = "alpha_ceo"
            status              = "awaiting_alpha"
        })
    }
}

function Invoke-AuditWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[AUDIT] ========== Beta CEO Audit Wake-Up ==========" -ForegroundColor Blue

    # 1. Context
    $issuesData = gh issue list --repo $repo --state open --json number,title --limit 50
    $prsData = gh pr list --repo $repo --state open --json number,title,mergeable --limit 50
    $delegationsData = $State.active_delegations | ConvertTo-Json -Depth 3

    # 2. Prompt
    $promptVars = @{
        repo        = $repo
        issues      = $issuesData
        prs         = $prsData
        delegations = $delegationsData
    }
    $auditPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey "audit_prompt" -Variables $promptVars
    $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$auditPrompt"

    Write-Host "[AUDIT] Sende Audit-Anfrage an CEO Beta..." -ForegroundColor Cyan
    $result = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "audit" -DryRun:$DryRun -Prompt $fullPrompt -State $State -AlphaTierOverride "balanced"

    if ($result.success -and -not $DryRun.IsPresent) {
        try {
            $parsed = $result.output | ConvertFrom-Json
            if ($parsed.issues_found) {
                if ($parsed.action -eq "remediate" -and $parsed.remediation_command) {
                    Write-Host "[AUDIT] Starte Remediation: $($parsed.remediation_command)" -ForegroundColor Cyan
                    Invoke-Expression $parsed.remediation_command
                } elseif ($parsed.action -eq "escalate") {
                    Add-AuditDecisionPending -State $State -Topic "Audit Alert" -Context $parsed.dashboard_escalation
                }
            }
        } catch { Write-Warning "[AUDIT] Konnte Audit-JSON nicht parsen." }
    }
}

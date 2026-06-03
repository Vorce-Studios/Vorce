# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Sequential planning steps via session splitting

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
. (Join-Path $script:LibDir "autopilot-prompts.ps1")
. (Join-Path $script:LibDir "autopilot-session-manager.ps1")

function Get-ProviderModelNameForTier {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$Tier
    )

    $provider = $QuotaRegistry.providers.$ProviderName
    if ($provider -and ($provider.PSObject.Properties.Name -contains "models") -and $provider.models -and ($provider.models.PSObject.Properties.Name -contains $Tier)) {
        return [string]$provider.models.$Tier.name
    }

    return $Tier
}

function Convert-PlanningProposalOutput {
    param([string]$Output)
    $newIssues = @()
    if ([string]::IsNullOrWhiteSpace($Output)) { return @() }
    $parsedObj = $null
    try {
        $parsedObj = $Output | ConvertFrom-Json
    } catch {
        # Try to extract JSON array if wrapped in text
        $jsonArrMatch = [regex]::Match($Output, '(?s)\[.*\]')
        if ($jsonArrMatch.Success) { 
            try { $parsedObj = $jsonArrMatch.Value | ConvertFrom-Json } catch {} 
        }
    }
    if ($null -eq $parsedObj) { return @() }
    if ($parsedObj -is [System.Array] -or $parsedObj -is [System.Collections.IList]) {
        $newIssues = @($parsedObj)
    } elseif ($parsedObj.PSObject.Properties.Name -contains "proposal") {
        $newIssues = @($parsedObj.proposal)
    }
    return @($newIssues)
}

function Invoke-PlanningWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[PLANNING] ========== Planning Wake-Up ==========" -ForegroundColor Blue

    # Ensure state arrays exist
    foreach ($prop in @("autopilot_created_issues", "active_delegations", "escalated_issues", "decisions_pending")) {
        if (-not ($State.PSObject.Properties.Name -contains $prop)) {
            $State | Add-Member -MemberType NoteProperty -Name $prop -Value @() -Force
        }
    }

    # --- Step 0: Process Beta-Audit escalations ---
    $auditAlphaEscalations = @($State.decisions_pending | Where-Object {
        $owner = if ($_.PSObject.Properties.Name -contains "owner") { [string]$_.owner } else { "alpha_ceo" }
        $status = if ($_.PSObject.Properties.Name -contains "status") { [string]$_.status } else { "awaiting_alpha" }
        $owner -eq "alpha_ceo" -and $status -eq "awaiting_alpha"
    })

    if ($auditAlphaEscalations.Count -gt 0) {
        Write-Host "[PLANNING] Bearbeite $($auditAlphaEscalations.Count) Audit-Eskalation(en) via Alpha CEO." -ForegroundColor Yellow
        foreach ($decision in $auditAlphaEscalations) {
            $alphaPrompt = "Löse folgende Audit-Eskalation: $($decision.topic). Kontext: $($decision.context). Antworte als JSON mit 'action' (plan_fix|escalate_user) und 'alpha_response'."
            $alphaResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -Prompt $alphaPrompt -State $State -DryRun:$DryRun
            if ($alphaResult.success) {
                $decision.status = "alpha_reviewed"
                $decision.alpha_response = [string]$alphaResult.output
            }
        }
    }

    # --- Step 1: Sequential Planning Sequence (Session Splitting) ---
    $planningContext = ""
    $newIssues = @()

    $julesActiveCount = @($State.active_delegations | Where-Object { -not ($_.PSObject.Properties.Name -contains "agent_type") -or ($_.agent_type -eq "jules") }).Count
    $julesAvailableSlots = [int]$Config.jules.max_concurrent_sessions - $julesActiveCount

    if ($Config.PSObject.Properties.Name -contains "planning_sequence") {
        foreach ($step in $Config.planning_sequence) {
            Write-Host "[PLANNING] Starte Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan
            $promptVars = @{ repo = $repo; context = $planningContext; maxIssues = $Config.max_issues_per_planning_cycle; slots = $julesAvailableSlots }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            if ($step.id -eq "final_synthesis") {
                $resolvedTier = Resolve-CeoModelTier -QuotaRegistry $QuotaRegistry -ProviderName "codex_orchestrator" -RequestedTier ([string]$step.tier) -TaskType "planning"
                $modelName = Get-ProviderModelNameForTier -QuotaRegistry $QuotaRegistry -ProviderName "codex_orchestrator" -Tier $resolvedTier
                Write-Host "[PLANNING] Starte Planning Synthesis als interaktiven Codex-Chat ($resolvedTier / $modelName)." -ForegroundColor Cyan
                $sessionResult = Invoke-AutopilotCodexSession -SessionType "planning-synthesis" -Prompt $fullPrompt -State $State -Model $modelName -VisibleTerminal -ResumeMainSession -DryRun:$DryRun
                $stepResult = [pscustomobject]@{
                    success = [bool]$sessionResult.Success
                    output  = if ($sessionResult.DryRun) { "{`"dry_run`":true,`"interactive_planning_synthesis`":true}" } else { "Interactive Codex planning synthesis completed." }
                }
            } else {
                $stepResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -DryRun:$DryRun -Prompt $fullPrompt -State $State -AlphaTierOverride $step.tier
            }
            if ($stepResult.success) {
                $output = [string]$stepResult.output
                $planningContext += "`n### Ergebnis von $($step.label):`n$output`n"
                if ($step.id -in @("propose_issues", "task_generation") -or $step.prompt_ref -eq "planning_proposal") {
                    $issues = @(Convert-PlanningProposalOutput -Output $output)
                    $newIssues += $issues
                    Write-Host "[PLANNING] $($issues.Count) neue Issues vorgeschlagen." -ForegroundColor DarkGray
                }
            } else {
                Write-Warning "[PLANNING] Schritt $($step.label) fehlgeschlagen."
            }
        }
    }

    # --- Step 2: Create suggested issues ---
    if ($newIssues.Count -gt 0 -and -not $DryRun.IsPresent) {
        # Determine next VOR number
        $issuesRaw = gh issue list --repo $repo --state all --json title --limit 300 | ConvertFrom-Json
        $nextVorNumber = 1
        $usedVorNumbers = @($issuesRaw | ForEach-Object {
            $m = [regex]::Match([string]$_.title, 'VOR-(\d{3})')
            if ($m.Success) { [int]$m.Groups[1].Value }
        })
        if ($usedVorNumbers.Count -gt 0) { $nextVorNumber = ($usedVorNumbers | Measure-Object -Maximum).Maximum + 1 }

        foreach ($issue in $newIssues) {
            if ($null -eq $issue.title) { continue }
            $issueTitle = [string]$issue.title
            if ($issueTitle -match "VOR-000") {
                $issueTitle = $issueTitle -replace "VOR-000", ("VOR-{0:D3}" -f $nextVorNumber)
                $nextVorNumber++
            }
            $agent = if ($issue.PSObject.Properties.Name -contains "agent") { $issue.agent } else { "jules" }
            $labels = @($issue.labels) + @($Config.issue_filters.autopilot_label) + @("agent:$agent")
            $labelArgs = ($labels | ForEach-Object { "--label `"$_`"" }) -join " "
            
            gh issue create --repo $repo --title $issueTitle --body $issue.body $labelArgs | Out-Null
            Write-Host "[PLANNING] Issue erstellt: $issueTitle" -ForegroundColor Green
        }
    }

    # --- Step 3: Delegation ---
    $GetCandidates = {
        $issuesRaw = gh issue list --repo $repo --state open --json number,title,labels,body --limit 100 | ConvertFrom-Json
        if (-not $issuesRaw) { return @() }
        
        $includeLabels = @($Config.issue_filters.include_labels)
        $excludeLabels = @($Config.issue_filters.exclude_labels)
        
        $delegatedNumbers = @($State.active_delegations | ForEach-Object { [int]$_.issue_number })

        return @($issuesRaw | Where-Object { 
            $labels = @($_.labels.name)
            $hasInclude = (@($includeLabels | Where-Object { $labels -contains $_ }).Count -gt 0)
            $hasExclude = (@($excludeLabels | Where-Object { $labels -contains $_ }).Count -gt 0)
            $notDelegated = $delegatedNumbers -notcontains [int]$_.number
            $hasInclude -and -not $hasExclude -and $notDelegated
        })
    }

    $candidates = @(& $GetCandidates)
    $toPick = [Math]::Min($Config.max_issues_per_planning_cycle, $candidates.Count)
    Write-Host "[PLANNING] Untersuche $toPick Issues für Delegation (von $($candidates.Count) Kandidaten)." -ForegroundColor Cyan

    for ($i = 0; $i -lt $toPick; $i++) {
        $issue = $candidates[$i]
        $targetAgent = "jules"
        foreach ($label in $issue.labels.name) { if ($label -match "^agent:(.+)") { $targetAgent = $Matches[1] } }

        if ($targetAgent -eq "jules" -and $julesAvailableSlots -le 0) {
            Write-Host "[PLANNING] Keine Jules-Slots frei fuer #$($issue.number). Ueberspringe." -ForegroundColor Gray
            continue
        }

        Write-Host "[PLANNING] Delegiere #$($issue.number): $($issue.title) an $targetAgent" -ForegroundColor Green
        if (-not $DryRun.IsPresent) {
            if ($targetAgent -eq "jules") {
                # Start Jules session logic would go here
                Add-Delegation -State $State -IssueNumber $issue.number -IssueTitle $issue.title -JulesSessionId "jules-task-$($issue.number)" -AgentType "jules"
                $julesAvailableSlots--
            } else {
                # Start CLI agent logic would go here
                Add-Delegation -State $State -IssueNumber $issue.number -IssueTitle $issue.title -JulesSessionId "cli-task-$($issue.number)" -AgentType $targetAgent
            }
        }
    }

    $State.last_planning_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State
    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}

function Add-Delegation {
    param($State, $IssueNumber, $IssueTitle, $JulesSessionId, $AgentType)
    if (-not ($State.PSObject.Properties.Name -contains "active_delegations")) {
        $State | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
    }
    $State.active_delegations += [ordered]@{
        issue_number     = [int]$IssueNumber
        issue_title      = [string]$IssueTitle
        jules_session_id = [string]$JulesSessionId
        jules_state      = "STARTED"
        agent_type       = [string]$AgentType
        delegated_at     = (Get-Date -Format 'o')
        last_checked_at  = (Get-Date -Format 'o')
        retry_count      = 0
    }
}

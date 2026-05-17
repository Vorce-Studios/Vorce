# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Scan issues, create new ones, delegate to Jules

Set-StrictMode -Version Latest

$PromptLibPath = Join-Path (Split-Path -Parent $PSScriptRoot) "lib\autopilot-prompts.ps1"
if (Test-Path $PromptLibPath) {
    . $PromptLibPath
}

function Invoke-PlanningWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[PLANNING] ========== Planning Wake-Up ==========" -ForegroundColor Magenta

    # --- Step 1: Fetch open issues ---
    Write-Host "[PLANNING] Lade offene Issues..." -ForegroundColor Cyan

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 'gh' ist nicht verfuegbar."
    }

    $issuesRaw = & gh issue list --repo $repo --state open --json number,title,labels,assignees,body --limit 50 2>&1
    $issues = @()
    if ($LASTEXITCODE -eq 0) {
        try { $issues = @(($issuesRaw | Out-String) | ConvertFrom-Json -ErrorAction Stop) } catch { Write-Warning "Issue-Fetch fehlgeschlagen: $($_.Exception.Message)" }
    } else {
        Write-Warning "Issue-Fetch fehlgeschlagen: $($issuesRaw | Out-String)"
    }

    # Filter by include labels
    $includeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($l in $Config.issue_filters.include_labels) { $includeSet.Add($l) | Out-Null }
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($l in $Config.issue_filters.exclude_labels) { $excludeSet.Add($l) | Out-Null }

    $candidates = @($issues | Where-Object {
        $labelNames = @($_.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
        $hasInclude = @($labelNames | Where-Object { $includeSet.Contains($_) }).Count -gt 0
        $hasExclude = @($labelNames | Where-Object { $excludeSet.Contains($_) }).Count -gt 0
        $hasInclude -and (-not $hasExclude)
    })

    # Exclude already delegated issues
    $delegatedNumbers = @($State.active_delegations | ForEach-Object { [int]$_.issue_number })
    if ($delegatedNumbers.Count -gt 0) {
        $candidates = @($candidates | Where-Object { $delegatedNumbers -notcontains [int]$_.number })
    }

    Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation." -ForegroundColor Green

    # --- Step 2: Check if we should create new issues ---
    $enableCliIssueDiscovery = $false
    if ($Config.PSObject.Properties.Name -contains "planning" -and
        $Config.planning -and
        $Config.planning.PSObject.Properties.Name -contains "enable_cli_issue_discovery") {
        $enableCliIssueDiscovery = [bool]$Config.planning.enable_cli_issue_discovery
    }

    if ($enableCliIssueDiscovery -and $candidates.Count -lt 3) {
        Write-Host "[PLANNING] Wenige offene Issues - pruefe ob neue erstellt werden sollten." -ForegroundColor Yellow

        $promptText = Get-VorcePlanningIssueDiscoveryPrompt `
            -Repository $repo `
            -CandidateCount $candidates.Count `
            -MaxIssues ([int]$Config.max_issues_per_planning_cycle)
        $planResult = Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType "planning" -DryRun:$DryRun -Prompt $promptText

        if (-not $DryRun.IsPresent -and $planResult.success -and $planResult.output -match '^\s*\[') {
            try {
                $jsonMatch = [regex]::Match($planResult.output, '\[.*\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                if ($jsonMatch.Success) {
                    $newIssues = $jsonMatch.Value | ConvertFrom-Json
                    foreach ($newIssue in @($newIssues)) {
                        if ([string]::IsNullOrWhiteSpace([string]$newIssue.title) -or [string]::IsNullOrWhiteSpace([string]$newIssue.body)) {
                            continue
                        }

                        if ($DryRun.IsPresent) {
                            Write-Host "[PLANNING] [DRY RUN] Wuerde Issue erstellen: $($newIssue.title)" -ForegroundColor DarkYellow
                        } else {
                            $issueLabels = if ($newIssue.PSObject.Properties.Name -contains "labels") { @($newIssue.labels) } else { @() }
                            $labels = $issueLabels + @($Config.issue_filters.autopilot_label) |
                                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                                Select-Object -Unique
                            $ghArgs = @(
                                "issue", "create",
                                "--repo", $repo,
                                "--title", $newIssue.title,
                                "--body", $newIssue.body
                            )
                            foreach ($l in $labels) { $ghArgs += "--label"; $ghArgs += $l }

                            $created = & gh @ghArgs 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[PLANNING] Issue erstellt: $created" -ForegroundColor Green
                                $State.autopilot_created_issues += @($newIssue.title)
                            } else {
                                Write-Warning "[PLANNING] Issue-Erstellung fehlgeschlagen: $($created | Out-String)"
                            }
                        }
                    }
                }
            } catch {
                Write-Warning "[PLANNING] Konnte CLI-Antwort nicht parsen: $_"
            }
        }
    } elseif (-not $enableCliIssueDiscovery) {
        Write-Host "[PLANNING] CLI Issue Discovery deaktiviert; keine Gemini/Kiro/Cursor Planning-Route in diesem Zyklus." -ForegroundColor DarkGray
    }

    # --- Step 3: Delegate to Jules ---
    $julesProvider = $QuotaRegistry.providers.jules
    $currentSessions = if ($julesProvider.usage_today -and $julesProvider.usage_today.PSObject.Properties["account_sessions_observed_rolling_24h"]) {
        [int]$julesProvider.usage_today.account_sessions_observed_rolling_24h
    } elseif ($julesProvider.usage_today -and $julesProvider.usage_today.PSObject.Properties["calls"]) {
        [int]$julesProvider.usage_today.calls
    } else {
        0
    }
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $liveActiveSessions = 0
    if ($julesProvider.usage_today) {
        if ($julesProvider.usage_today.PSObject.Properties.Name -contains "scoped_live_capacity_sessions") {
            $liveActiveSessions = [int]$julesProvider.usage_today.scoped_live_capacity_sessions
        } elseif ($julesProvider.usage_today.PSObject.Properties.Name -contains "live_capacity_sessions") {
            $liveActiveSessions = [int]$julesProvider.usage_today.live_capacity_sessions
        } elseif ($julesProvider.usage_today.PSObject.Properties.Name -contains "active_sessions") {
            $liveActiveSessions = [int]$julesProvider.usage_today.active_sessions
        }
    }
    $activeDelegations = [Math]::Max([int]$State.active_delegations.Count, $liveActiveSessions)

    $availableSlots = [Math]::Min(
        ($maxDaily - $currentSessions),
        ($maxConcurrent - $activeDelegations)
    )
    $availableSlots = [Math]::Max(0, $availableSlots)

    $toPick = [Math]::Min($availableSlots, $Config.max_issues_per_planning_cycle)
    $toPick = [Math]::Min($toPick, $candidates.Count)

    $State.delegation_backlog = @($candidates | Select-Object -Skip $toPick | ForEach-Object {
        [ordered]@{
            issue_number = [int]$_.number
            issue_title = [string]$_.title
            source = "planning"
            queued_at = (Get-Date -Format 'o')
        }
    })
    Write-Host "[PLANNING] Jules Slots: $availableSlots verfuegbar, delegiere $toPick Issues, Backlog: $($State.delegation_backlog.Count)." -ForegroundColor Cyan

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"

    for ($i = 0; $i -lt $toPick; $i++) {
        $issue = $candidates[$i]
        $issueNum = [int]$issue.number
        $issueTitle = [string]$issue.title

        Write-Host ("[PLANNING] Delegiere Issue #{0}: {1}" -f $issueNum, $issueTitle) -ForegroundColor Green

        if ($DryRun.IsPresent) {
            Write-Host "[PLANNING] [DRY RUN] Wuerde Jules Session starten." -ForegroundColor DarkYellow
            continue
        }

        try {
            $sessionResult = & "$JulesScriptDir\create-jules-session.ps1" `
                -IssueNumber $issueNum `
                -Repository $repo `
                -Prompt (Get-VorceJulesImplementationPrompt -IssueNumber $issueNum -Repository $repo) `
                -AutoCreatePr `
                -ApiKey $env:JULES_API_KEY

            $sessionObject = @($sessionResult | Where-Object {
                $null -ne $_ -and
                $_ -isnot [string] -and
                ($_.PSObject.Properties.Name -contains "SessionId")
            } | Select-Object -Last 1)
            $sessionId = if ($sessionObject.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$sessionObject[0].SessionId)) {
                [string]$sessionObject[0].SessionId
            } else {
                "unknown"
            }
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId
            if (Get-Command Add-AutopilotJournalEvent -ErrorAction SilentlyContinue) {
                Add-AutopilotJournalEvent -SessionType "planning" -Message ("Started Jules session {0} for issue #{1}: {2}" -f $sessionId, $issueNum, $issueTitle)
            }
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
        } catch {
            Write-Warning "[PLANNING] Jules Session fuer #$issueNum fehlgeschlagen: $_"
            Add-ErrorLog -State $State -Message "Jules delegation failed for #$issueNum" -Context $_.Exception.Message
        }
    }

    if (-not $DryRun.IsPresent) {
        $State.last_planning_at = (Get-Date -Format 'o')
        Save-AutopilotState -State $State
    }

    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}

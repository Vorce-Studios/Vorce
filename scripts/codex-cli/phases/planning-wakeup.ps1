# scripts/codex-cli/phases/planning-wakeup.ps1
# Planning Mode: Scan issues, create new ones, delegate to Jules

Set-StrictMode -Version Latest

function Invoke-PlanningWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[PLANNING] ========== Planning Wake-Up ==========" -ForegroundColor Magenta

    # Define script block to fetch candidates to avoid duplication
    $GetCandidates = {
        Write-Host "[PLANNING] Lade offene Issues..." -ForegroundColor Cyan
        $includeLabels = ($Config.issue_filters.include_labels | ForEach-Object { "--label `"$_`"" }) -join " "
        $excludeLabels = $Config.issue_filters.exclude_labels

        $issuesRaw = gh issue list --repo $repo --state open --json number,title,labels,assignees,body --limit 50 2>&1
        $issues = @()
        try {
            $issues = @($issuesRaw | Out-String | ConvertFrom-Json | ForEach-Object { $_ })
        } catch {
            Write-Warning "Issue-Fetch fehlgeschlagen: $_"
        }

        # Filter by include labels
        $includeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($l in $Config.issue_filters.include_labels) { $includeSet.Add($l) | Out-Null }
        $excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($l in $Config.issue_filters.exclude_labels) { $excludeSet.Add($l) | Out-Null }

        $c = @($issues | Where-Object {
            $labelNames = @($_.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
            $hasInclude = @($labelNames | Where-Object { $includeSet.Contains($_) }).Count -gt 0
            $hasExclude = @($labelNames | Where-Object { $excludeSet.Contains($_) }).Count -gt 0
            $hasInclude -and (-not $hasExclude)
        })

        # Exclude already delegated issues
        $delegatedNumbers = @($State.active_delegations | ForEach-Object { [int]$_.issue_number })
        if ($delegatedNumbers.Count -gt 0) {
            $c = @($c | Where-Object {
                $val = $_.number
                if ($val -is [System.Collections.IList]) { $val = $val[0] }
                if ($null -eq $val) { $true } else { $delegatedNumbers -notcontains [int]$val }
            })
        }
        return ,$c
    }

    # --- Step 1: Fetch open issues ---
    $candidates = @(& $GetCandidates)
    Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation." -ForegroundColor Green

    # --- Step 2: Check if we should create new issues ---
    if ($candidates.Count -lt 3) {
        Write-Host "[PLANNING] Wenige offene Issues - pruefe ob neue erstellt werden sollten." -ForegroundColor Yellow

        $promptText = @"
Du bist der Autopilot fuer das Vorce-Projekt (Rust Projection-Mapping Software).
Repository: $repo

Aktuell gibt es nur $($candidates.Count) offene, delegierbare Issues.

Analysiere das Repository und schlage bis zu $($Config.max_issues_per_planning_cycle) neue Issues vor.
Fokus: fehlende Tests, Code-Qualitaet, offene TODOs, Performance.

Antworte NUR mit einer JSON-Liste im Format:
[{"title": "MF-StIs_Issue-Title", "body": "Beschreibung", "labels": ["jules-task"]}]

Wenn keine neuen Issues noetig sind, antworte mit einem leeren Array.
"@
        $planResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "planning" -DryRun:$DryRun -Prompt $promptText -State $State

        if ($planResult.success -and $planResult.output -match '\[') {
            try {
                $jsonMatch = [regex]::Match($planResult.output, '\[.*\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                if ($jsonMatch.Success) {
                    $newIssues = $jsonMatch.Value | ConvertFrom-Json
                    $newIssuesCreated = $false
                    foreach ($newIssue in $newIssues) {
                        if ($DryRun.IsPresent) {
                            Write-Host "[PLANNING] [DRY RUN] Wuerde Issue erstellen: $($newIssue.title)" -ForegroundColor DarkYellow
                        } else {
                            $labels = @($newIssue.labels) + @($Config.issue_filters.autopilot_label)
                            $labelArgs = ($labels | ForEach-Object { "--label `"$_`"" }) -join " "
                            $createCmd = "gh issue create --repo $repo --title `"$($newIssue.title)`" --body `"$($newIssue.body)`" $labelArgs"
                            $created = Invoke-Expression $createCmd 2>&1
                            Write-Host "[PLANNING] Issue erstellt: $created" -ForegroundColor Green
                            $State.autopilot_created_issues += @($newIssue.title)
                            $newIssuesCreated = $true
                        }
                    }
                    if ($newIssuesCreated) {
                        Write-Host "[PLANNING] Neue Issues wurden erstellt. Lade Kandidatenliste neu..." -ForegroundColor Cyan
                        $candidates = @(& $GetCandidates)
                        Write-Host "[PLANNING] $($candidates.Count) Issues bereit fuer Delegation (nach Reload)." -ForegroundColor Green
                    }
                }
            } catch {
                Write-Warning "[PLANNING] Konnte CLI-Antwort nicht parsen: $_"
            }
        }
    }

    # --- Step 3: Delegate to Jules ---
    $julesProvider = $QuotaRegistry.providers.jules
    $currentSessions = [int]$julesProvider.usage_today.calls
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $activeDelegations = $State.active_delegations.Count

    $availableSlots = [Math]::Min(
        ($maxDaily - $currentSessions),
        ($maxConcurrent - $activeDelegations)
    )
    $availableSlots = [Math]::Max(0, $availableSlots)

    $toPick = [Math]::Min($availableSlots, $Config.max_issues_per_planning_cycle)
    $toPick = [Math]::Min($toPick, $candidates.Count)

    Write-Host "[PLANNING] Jules Slots: $availableSlots verfuegbar, delegiere $toPick Issues." -ForegroundColor Cyan

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $JulesScriptDir = Join-Path (Split-Path -Parent $ScriptDir) "jules"

    for ($i = 0; $i -lt $toPick; $i++) {
        $issue = $candidates[$i]
        $issueNum = [int]$issue.number
        $issueTitle = [string]$issue.title

        Write-Host ("[PLANNING] Delegiere Issue #{0}: {1}" -f $issueNum, $issueTitle) -ForegroundColor Green

        if ($DryRun.IsPresent) {
            Write-Host "[PLANNING] [DRY RUN] Wuerde Jules Session starten." -ForegroundColor DarkYellow
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "dry-run-$issueNum"
            continue
        }

        try {
            $sessionResult = & "$JulesScriptDir\create-jules-session.ps1" `
                -IssueNumber $issueNum `
                -Repository $repo `
                -AutoCreatePr `
                -ApiKey $env:JULES_API_KEY

            $sessionId = "unknown"
            if ($sessionResult) {
                if ($sessionResult -is [System.Array]) {
                    $targetObj = $sessionResult | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "SessionId") -and $_.SessionId } | Select-Object -First 1
                    if ($targetObj) {
                        $sessionId = [string]$targetObj.SessionId
                    } else {
                        $lastObj = $sessionResult[-1]
                        if ($lastObj -and ($lastObj.PSObject.Properties.Name -contains "SessionId")) {
                            $sessionId = [string]$lastObj.SessionId
                        }
                    }
                } elseif (($sessionResult.PSObject.Properties.Name -contains "SessionId") -and $sessionResult.SessionId) {
                    $sessionId = [string]$sessionResult.SessionId
                }
            }
            Add-Delegation -State $State -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
        } catch {
            Write-Warning "[PLANNING] Jules Session fuer #$issueNum fehlgeschlagen: $_"
            Add-ErrorLog -State $State -Message "Jules delegation failed for #$issueNum" -Context $_.Exception.Message
        }
    }

    $State.last_planning_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State

    Write-Host "[PLANNING] ========== Planning abgeschlossen ==========" -ForegroundColor Magenta
}

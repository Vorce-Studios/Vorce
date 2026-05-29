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
        return $c
    }

    # --- Step 0: Process escalated issues (CEO Re-Planning) ---
    $escalated = @($State.escalated_issues | Where-Object { $_.status -eq "NEEDS_PLANNING" })
    if ($escalated.Count -gt 0) {
        Write-Host "[PLANNING] Gefunden: $($escalated.Count) eskalierte Issues zur Re-Planung." -ForegroundColor Yellow
        foreach ($escIssue in $escalated) {
            $issueNum = [int]$escIssue.issue_number
            $issueTitle = [string]$escIssue.issue_title
            $lastSessionId = [string]$escIssue.last_jules_session_id

            Write-Host "[PLANNING] Re-Planning fuer eskaliertes Issue #$issueNum ($issueTitle) via Dual-CEO Deliberation..." -ForegroundColor Yellow

            $promptText = @"
Das Issue #$issueNum ("$issueTitle") wurde an Jules delegiert (letzte Session: $lastSessionId), ist aber im Monitoring-Modus fehlgeschlagen oder hängengeblieben (Timeout/Fehler).

Deine Rolle: Analysiere diese Eskalation im Dual-CEO Team.
Erstelle eine neue, präzisere Handlungsanweisung (Prompt-Ergänzung oder überarbeitete Issue-Beschreibung), um Jules beim nächsten Versuch erfolgreich zu leiten.
Antworte mit einem konkreten, korrigierten Handlungsplan für Jules.
"@

            # Erzwinge Dual-CEO Deliberation
            $planResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "planning" `
                -Prompt $promptText `
                -State $State `
                -ForceDeliberation `
                -DryRun:$DryRun

            if ($planResult.success) {
                $ceoPlan = $planResult.output
                Write-Host "[PLANNING] Re-Planning erfolgreich für #$issueNum." -ForegroundColor Green

                if (-not $DryRun.IsPresent) {
                    $commentBody = "CEO Re-Planning Handlungsplan für den nächsten Versuch:`n`n$ceoPlan"
                    gh issue comment $issueNum --repo $repo --body $commentBody | Out-Null
                    Write-Host "[PLANNING] CEO-Plan auf GitHub-Issue #$issueNum gepostet." -ForegroundColor Green
                    
                    $escIssue.planning_resolutions = [int]$escIssue.planning_resolutions + 1
                    $escIssue.status = "RESOLVED_BY_PLANNING"
                    Save-AutopilotState -State $State
                }
            } else {
                Write-Warning "[PLANNING] Re-Planning fuer #$issueNum fehlgeschlagen."
            }
        }
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

        if ($planResult.success) {
            try {
                $newIssues = @()
                $parsedObj = $null
                try {
                    # Try to parse the entire output first
                    $parsedObj = $planResult.output | ConvertFrom-Json
                } catch {
                    # Best-effort extraction if there's header/footer noise
                    $jsonObjMatch = [regex]::Match($planResult.output, '(?s)\{.*\}')
                    if ($jsonObjMatch.Success) {
                        try { $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json } catch {}
                    }
                    if ($null -eq $parsedObj) {
                        $jsonArrMatch = [regex]::Match($planResult.output, '(?s)\[.*\]')
                        if ($jsonArrMatch.Success) {
                            try { $parsedObj = $jsonArrMatch.Value | ConvertFrom-Json } catch {}
                        }
                    }
                }

                if ($null -ne $parsedObj) {
                    if ($parsedObj -is [System.Array] -or $parsedObj -is [System.Collections.IList]) {
                        $newIssues = @($parsedObj)
                    } elseif ($parsedObj.PSObject.Properties.Name -contains "proposal") {
                        $propVal = $parsedObj.proposal
                        if ($propVal -is [string]) {
                            try { $newIssues = @($propVal | ConvertFrom-Json) } catch {}
                        } else {
                            $newIssues = @($propVal)
                        }
                    } elseif ($parsedObj.PSObject.Properties.Name -contains "response") {
                        $respVal = $parsedObj.response
                        if ($respVal -is [string]) {
                            try {
                                # If it's a JSON string inside response
                                $nestedObj = $respVal | ConvertFrom-Json
                                if ($nestedObj -is [System.Array] -or $nestedObj -is [System.Collections.IList]) {
                                    $newIssues = @($nestedObj)
                                } elseif ($nestedObj.PSObject.Properties.Name -contains "proposal") {
                                    $newIssues = @($nestedObj.proposal)
                                }
                            } catch {
                                # Try extracting list from response text
                                $jsonMatch = [regex]::Match($respVal, '(?s)\[.*\]')
                                if ($jsonMatch.Success) {
                                    try { $newIssues = @($jsonMatch.Value | ConvertFrom-Json) } catch {}
                                }
                            }
                        } else {
                            $newIssues = @($respVal)
                        }
                    }
                } else {
                    # Final fallback: regex match on raw text
                    $jsonMatch = [regex]::Match($planResult.output, '(?s)\[.*\]')
                    if ($jsonMatch.Success) {
                        try { $newIssues = @($jsonMatch.Value | ConvertFrom-Json) } catch {}
                    }
                }

                if ($newIssues.Count -gt 0) {
                    $newIssuesCreated = $false
                    foreach ($newIssue in $newIssues) {
                        # Validate that newIssue has a title
                        if ($null -eq $newIssue -or -not ($newIssue.PSObject.Properties.Name -contains "title")) { continue }
                        
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

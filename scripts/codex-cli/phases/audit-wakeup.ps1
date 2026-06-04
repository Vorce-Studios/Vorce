# scripts/codex-cli/phases/audit-wakeup.ps1
# Beta CEO Audit Mode: Unabhaengige Pruefung von PRs, Issues und Jules Sessions

Set-StrictMode -Version Latest

function Invoke-AuditWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[AUDIT] ========== Beta CEO Audit Wake-Up ==========" -ForegroundColor Blue

    # Ensure state array exists
    if ($null -eq $State.decisions_pending) {
        $State | Add-Member -MemberType NoteProperty -Name "decisions_pending" -Value @() -Force
    }

    $ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

    # 1. Daten aus dem Cache sammeln
    $issuesData = ""
    $cachedIssuePath = Join-Path $ScriptDir "dashboard\public\github-issues.json"
    if (Test-Path $cachedIssuePath) {
        try {
            $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
                $issuesData = ($issuesRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- #$($_.number) [$($_.state)]: $($_.title)" }) -join "`n"
            }
        } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten Issues." }
    }

    $prsData = ""
    $cachedPrPath = Join-Path $ScriptDir "dashboard\public\pull-requests.json"
    if (Test-Path $cachedPrPath) {
        try {
            $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
                $prsData = ($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- PR #$($_.number) [$($_.mergeable)]: $($_.title)" }) -join "`n"
            }
        } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten PRs." }
    }

    $delegationsData = ""
    if ($null -ne $State.active_delegations) {
        $delegationsData = ($State.active_delegations | ForEach-Object { "- Issue #$($_.issue_number) an $($_.agent_type) (Session: $($_.jules_session_id)) - Status: $($_.jules_state)" }) -join "`n"
    }

    # 2. Run Audit Sequence if configured
    $auditContext = ""
    if ($Config.PSObject.Properties.Name -contains "audit_sequence") {
        Write-Host "[AUDIT] Starte sequentielle Audit-Sequenz (Session Splitting)..." -ForegroundColor Yellow
        
        $LagebildText = ""
        try {
            $LagebildText = Get-VorceLagebildSummary -State $State -Config $Config -QuotaRegistry $QuotaRegistry
        } catch {
            Write-Warning "[AUDIT] Konnte Lagebild-Zusammenfassung nicht generieren: $_"
        }

        foreach ($step in $Config.audit_sequence) {
            Write-Host "[AUDIT] Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan
            
            $promptVars = @{ repo = $repo }
            if ($step.id -eq "consistency_audit" -or $step.prompt_ref -eq "audit_consistency") {
                $promptVars.issues = $issuesData
                $promptVars.prs = $prsData
                $promptVars.delegations = $delegationsData
            } elseif ($step.id -eq "performance_audit" -or $step.prompt_ref -eq "audit_performance") {
                $promptVars.delegations = $delegationsData
            } elseif ($step.id -eq "audit_synthesis" -or $step.prompt_ref -eq "audit_synthesis") {
                $promptVars.context = $auditContext
            } else {
                $promptVars.issues = $issuesData
                $promptVars.prs = $prsData
                $promptVars.delegations = $delegationsData
                $promptVars.context = $auditContext
            }

            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            
            $fullPrompt = ""
            if ($step.id -eq "audit_synthesis" -or $step.prompt_ref -eq "audit_synthesis") {
                $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$LagebildText`n`n$stepPrompt"
            } else {
                $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"
            }

            $stepResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "audit" `
                -DryRun:$DryRun `
                -Prompt $fullPrompt `
                -State $State
                
            if ($stepResult.success) {
                $auditContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
                
                # Parse final synthesis results for remediation/escalation
                if ($step.id -eq "audit_synthesis" -or $step.prompt_ref -eq "audit_synthesis") {
                    Write-Host "[AUDIT] Analysiere Audit-Synthese Ergebnis..." -ForegroundColor Cyan
                    try {
                        $parsedObj = $null
                        $cleanOutput = $stepResult.output
                        $jsonObjMatch = [regex]::Match($cleanOutput, '(?s)\{.*\}')
                        if ($jsonObjMatch.Success) {
                            $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json
                        }

                        if ($null -ne $parsedObj -and $parsedObj.issues_found -eq $true) {
                            Write-Host "[AUDIT] CEO Beta hat Probleme gefunden!" -ForegroundColor Yellow

                            if ($parsedObj.action -eq "remediate" -and -not [string]::IsNullOrWhiteSpace($parsedObj.remediation_command)) {
                                Write-Host "[AUDIT] Fuehre Remediation-Befehl aus: $($parsedObj.remediation_command)" -ForegroundColor Cyan
                                try {
                                    if (-not $DryRun.IsPresent) {
                                        Invoke-Expression $parsedObj.remediation_command | Out-Null
                                    } else {
                                        Write-Host "[AUDIT] [DRY RUN] Wuerde Remediation ausfuehren: $($parsedObj.remediation_command)" -ForegroundColor DarkYellow
                                    }
                                    Write-Host "[AUDIT] Remediation erfolgreich gestartet." -ForegroundColor Green
                                } catch {
                                    Write-Warning "[AUDIT] Remediation fehlgeschlagen: $_"
                                    $State.decisions_pending += @([ordered]@{
                                        topic      = "Beta CEO Remediation Failed"
                                        context    = "Der Versuch, das Problem automatisch zu beheben, schlug fehl. Befehl: $($parsedObj.remediation_command). Fehler: $_"
                                        created_at = (Get-Date -Format 'o')
                                    })
                                }
                            } elseif ($parsedObj.action -eq "escalate") {
                                Write-Host "[AUDIT] CEO Beta eskaliert zum Dashboard und erzeugt Working Session." -ForegroundColor Red
                                $State.decisions_pending += @([ordered]@{
                                    topic      = "Beta CEO Audit Alert"
                                    context    = $parsedObj.dashboard_escalation
                                    created_at = (Get-Date -Format 'o')
                                })

                                # Automatisches Erstellen einer Working Session für den Audit Alert
                                if (-not $DryRun.IsPresent) {
                                    $issueTitle = "MF-StIs_Resolve-Audit-Alert: $($parsedObj.dashboard_escalation)"
                                    if ($issueTitle.Length -gt 100) { $issueTitle = $issueTitle.Substring(0, 100) + "..." }
                                    $issueBody = "Ein automatischer Audit-Alert wurde registriert:`n`n$($parsedObj.dashboard_escalation)`n`nBitte untersuche das Problem und beheben es."
                                    $targetAgent = "gemini_cli"
                                    
                                    $newIssueUrl = gh issue create --repo $repo --title $issueTitle --body $issueBody --label "priority: high,bug,agent:$targetAgent" 2>&1
                                    if ($LASTEXITCODE -eq 0 -and $newIssueUrl -match "/issues/(\d+)") {
                                        $newIssueNum = [int]$Matches[1]
                                        Write-Host "[AUDIT] -> Audit-Alert Issue #$newIssueNum erfolgreich erstellt! Zuweisung an $targetAgent." -ForegroundColor Green
                                        
                                        Confirm-WorkingSessionsState -State $State
                                        $State.working_queue += @([ordered]@{
                                            id             = "work-$newIssueNum-$(Get-Date -Format 'yyyyMMddHHmmss')"
                                            issue_number   = $newIssueNum
                                            issue_title    = $issueTitle
                                            agent_provider = $targetAgent
                                            status         = "QUEUED"
                                            queued_at      = (Get-Date -Format 'o')
                                        })
                                        Save-AutopilotState -State $State
                                    }
                                }
                            }
                        } else {
                            Write-Host "[AUDIT] CEO Beta meldet: Keine gravierenden Probleme gefunden." -ForegroundColor Green
                        }
                    } catch {
                        Write-Warning "[AUDIT] Konnte Audit-Ergebnis nicht parsen: $_"
                    }
                }
            } else {
                Write-Warning "[AUDIT] Schritt $($step.label) fehlgeschlagen."
            }
        }
    }

    # 4. Smart Memory Optimization
    Optimize-AutopilotMemories -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
}

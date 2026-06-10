# Vorce-Autopilot/src/phases/audit-wakeup.ps1
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
    if (-not ($State.PSObject.Properties.Name -contains "decisions_pending")) {
        $State | Add-Member -MemberType NoteProperty -Name "decisions_pending" -Value @() -Force
    }

    $ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")
    $VarDbDir = Join-Path $ScriptDir "var/db"

    # 1. Daten aus dem Cache (var/db) sammeln
    $issuesData = ""
    $cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
    if (Test-Path $cachedIssuePath) {
        try {
            $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
                $issuesData = ($issuesRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- #$($_.number) [$($_.state)]: $($_.title)" }) -join "`n"
            }
        } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten Issues." }
    }

    $prsData = ""
    $cachedPrPath = Join-Path $VarDbDir "pull-requests.json"
    if (Test-Path $cachedPrPath) {
        try {
            $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
                $prsData = ($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo } | ForEach-Object { "- PR #$($_.number) [$($_.mergeable)]: $($_.title)" }) -join "`n"
            }
        } catch { Write-Warning "[AUDIT] Fehler beim Lesen der gecachten PRs." }
    }

    $delegationsData = ""
    if ($State.PSObject.Properties.Name -contains "active_delegations" -and $null -ne $State.active_delegations) {
        $delegationsData = ($State.active_delegations | ForEach-Object { "- Issue #$($_.issue_number) an $($_.agent_type) (Session: $($_.jules_session_id)) - Status: $($_.jules_state)" }) -join "`n"
    }

    # 2. Run Audit Sequence if configured
    $auditContext = ""
    if ($Config.PSObject.Properties.Name -contains "audit_sequence") {
        Write-Host "[AUDIT] Starte sequentielle Audit-Sequenz (Session Splitting)..." -ForegroundColor Yellow

        foreach ($step in $Config.audit_sequence) {
            Write-Host "[AUDIT] Schritt: $($step.label) (Thinking: $($step.tier))" -ForegroundColor Cyan
            $promptVars = @{
                repo        = $repo
                issues      = $issuesData
                prs         = $prsData
                delegations = $delegationsData
                context     = $auditContext
            }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = Invoke-DualCeoTask `
                -QuotaRegistry $QuotaRegistry `
                -Config $Config `
                -TaskType "audit" `
                -DryRun:$DryRun `
                -Prompt $fullPrompt `
                -State $State

            if ($stepResult.success) {
                $auditContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
            } else {
                Write-Warning "[AUDIT] Schritt $($step.label) fehlgeschlagen: $(Format-AutopilotTaskFailure -Result $stepResult)"
            }
        }
    }

    # 3. Prompt fuer finalen Audit-Entscheidungsschritt bauen
    $promptText = @"
Du bist CEO BETA (Gemini) des Vorce-Autopiloten.
Deine Aufgabe ist ein unabhaengiges AUDIT des aktuellen Projektstatus.

MANDAT DES USERS (VERLETZUNG FUEHRT ZUM ABBRUCH):
1. Du MUSST DEINE ANTWORT ZWINGEND AUF DEUTSCH VERFASSEN! Jede andere Sprache ist verboten.
2. Wenn du Probleme findest (z.B. fehlschlagende CI), DARFST DU NIEMALS SOFORT ESKALIEREN! Du MUSST zuerst eine Aktion ('remediate') vorschlagen.
3. STRENGES VERBOT FÜR MERGE-KONFLIKTE: Du darfst NIEMALS eigenmächtig Jules-Sessions für PR-Merge-Konflikte starten! Das Starten von Jules-Sessions für Merge-Konflikte wird bereits automatisch und gebündelt in der Planning-Phase übernommen. Jede redundante Jules-Session kostet den User wertvolles Tageslimit (100 Sessions/Tag).
4. STRENGES VERBOT FÜR JULES-CANCEL: Du darfst NIEMALS Befehle vorschlagen, die eine Jules-Session abbrechen, stoppen oder löschen! Das Limit von 100 Jules-Sessions pro Tag erfordert, dass fehlgeschlagene/hängende Sessions maximal pausiert (und vom User später re-purposed) werden, aber niemals gelöscht/gecancelt.
5. Nur wenn absolut klar ist, dass eine KI das Problem nicht loesen kann (z.B. fehlende Zugriffsrechte oder User-Entscheidung zwingend erforderlich), darfst du 'escalate' waehlen.
6. JEDE Eskalation muss hochdetailliert sein! Kein unspezifisches BlaBla wie 'Erfordert sofortige manuelle Intervention'.
7. Eine korrekte Eskalation enthaelt:
   - Exakt WELCHER PR/Issue betroffen ist.
   - WARUM die KI es nicht selbst loesen konnte (welche Limits/Gruende?).
   - WAS genau der User tun soll (Schritt fuer Schritt).

WICHTIG FÜR ALERTS:
Bevor du einen neuen Alert erstellst, prüfe ob eine ähnliche Situation bereits bearbeitet wurde (z.B. PR #779 Namenskonflikt). Wenn ja, gib keine Eskalation sondern sei vorsichtig mit der Erstellung neuer decision_pending-Einträge.

Aktuelle offene Issues:
$issuesData

Aktuelle offene Pull Requests:
$prsData

Aktive Agent-Delegationen (Tasks in Arbeit):
$delegationsData

Hier sind die Detail-Audit-Ergebnisse aus den vorherigen Schritten:
$auditContext

Antworte strikt im JSON-Format:
{
  "issues_found": true/false,
  "action": "remediate|escalate|none",
  "remediation_command": "<Dein powershell Befehl zum autonomen Beheben, falls action=remediate>",
  "dashboard_escalation": "<DEUTSCHE, hochdetaillierte Fehler-Analyse und Handlungsanweisung, NUR falls action=escalate>"
}
"@

    Write-Host "[AUDIT] Sende Audit-Anfrage an QA Manager (Gemini)..." -ForegroundColor Cyan

    $ToolsDir = Join-Path $ScriptDir "tools"
    $runVisibleCmd = Join-Path $ToolsDir "run-visible-ceo-phase.ps1"

    $promptFile = Join-Path $VarDbDir "beta-audit-prompt.txt"
    $outputFile = Join-Path $VarDbDir "beta-audit-result.json"
    $cliArgsFile = Join-Path $VarDbDir "beta-audit-args.json"
    $statusFile = Join-Path $VarDbDir "beta-audit-status.txt"

    try {
        $promptText | Out-File -FilePath $promptFile -Encoding UTF8
        @("-m", "gemini-2.5-flash", "--output-format", "json", "-y") | ConvertTo-Json -Depth 5 -Compress | Out-File $cliArgsFile -Encoding UTF8

        $cliArgs = @{
            CliCommand   = "gemini"
            CliArgsFile  = $cliArgsFile
            OutputFile   = $outputFile
            StatusFile   = $statusFile
            PhaseName    = "Audit"
            ProviderName = "Gemini"
            PromptFile   = $promptFile
        }

        if ($DryRun.IsPresent) {
            Write-Host "[AUDIT] [DRY RUN] Audit uebersprungen." -ForegroundColor DarkYellow
        } else {
            & $runVisibleCmd @cliArgs | Out-Null

            if (Test-Path $outputFile) {
                try {
                    $resultJson = Get-Content $outputFile -Raw -Encoding UTF8
                    $parsedObj = $null
                    $jsonObjMatch = [regex]::Match($resultJson, '(?s)\{.*\}')
                    if ($jsonObjMatch.Success) {
                        $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json

                        # Handle wrapper JSON from CLI router if present
                        if ($null -ne $parsedObj -and $parsedObj.PSObject.Properties.Name -contains "response") {
                            $cleanJson = $parsedObj.response -replace '(?s)```json\s*', '' -replace '(?s)```\s*$', ''
                            try {
                                $parsedObj = $cleanJson | ConvertFrom-Json
                            } catch {
                                Write-Warning "[AUDIT] Konnte eingebettetes JSON im Response nicht parsen."
                            }
                        }
                    }

                    if ($null -ne $parsedObj -and $parsedObj.issues_found -eq $true) {
                        Write-Host "[AUDIT] QA Manager hat Probleme gefunden!" -ForegroundColor Yellow

                        if ($parsedObj.action -eq "remediate" -and -not [string]::IsNullOrWhiteSpace($parsedObj.remediation_command)) {
                            Write-Host "[AUDIT] Fuehre Remediation-Befehl aus: $($parsedObj.remediation_command)" -ForegroundColor Cyan
                            try {
                                Invoke-Expression $parsedObj.remediation_command | Out-Null
                                Write-Host "[AUDIT] Remediation erfolgreich gestartet." -ForegroundColor Green
                            } catch {
                                Write-Warning "[AUDIT] Remediation fehlgeschlagen: $_"
                                # Fallback to escalation
                                $State.decisions_pending += @([ordered]@{
                                    topic      = "Beta CEO Remediation Failed"
                                    context    = "Der Versuch, das Problem automatisch zu beheben, schlug fehl. Befehl: $($parsedObj.remediation_command). Fehler: $_"
                                    created_at = (Get-Date -Format 'o')
                                })
                            }
                        } elseif ($parsedObj.action -eq "escalate") {
                            Write-Host "[AUDIT] QA Manager eskaliert zum Dashboard." -ForegroundColor Red
                            $State.decisions_pending += @([ordered]@{
                                topic      = "Beta CEO Audit Alert"
                                context    = $parsedObj.dashboard_escalation
                                created_at = (Get-Date -Format 'o')
                            })
                        }
                    } else {
                        Write-Host "[AUDIT] QA Manager meldet: Keine gravierenden Probleme gefunden." -ForegroundColor Green
                    }
                } catch {
                    Write-Warning "[AUDIT] Konnte Audit-Ergebnis nicht parsen: $_"
                }
            }
        }
    } finally {
        # Safe try/finally cleanup of temp files
        Remove-Item -Path $promptFile, $outputFile, $cliArgsFile, $statusFile -Force -ErrorAction SilentlyContinue
    }
}

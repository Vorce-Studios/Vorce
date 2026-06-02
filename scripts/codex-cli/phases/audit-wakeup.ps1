# scripts/codex-cli/phases/audit-wakeup.ps1
# Beta CEO Audit Mode: Unabhaengige Pruefung von PRs, Issues und Jules Sessions

Set-StrictMode -Version Latest

function Get-AuditAlertId {
    param([Parameter(Mandatory)][string]$Topic, [Parameter(Mandatory)][string]$Context)
    $raw = "$Topic|$Context"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return "audit-" + ([System.BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16).ToLowerInvariant())
}

function Add-AuditDecisionPending {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Context,
        [string]$Status = "awaiting_alpha",
        [string]$Owner = "alpha_ceo",
        [string]$ProcessStage = "alpha_review",
        [string]$EscalationLevel = "alpha",
        [string]$RemediationCommand = "",
        [string]$RemediationResult = "",
        [string]$UserEscalationReason = ""
    )

    $id = Get-AuditAlertId -Topic $Topic -Context $Context
    $exists = @($State.decisions_pending | Where-Object {
        ($_.PSObject.Properties.Name -contains "id" -and $_.id -eq $id) -or
        ($_.topic -eq $Topic -and $_.context -eq $Context)
    })
    if ($exists.Count -gt 0) {
        $existing = $exists[0]
        $hasAlphaAttempt = ($existing.PSObject.Properties.Name -contains "alpha_response" -and -not [string]::IsNullOrWhiteSpace([string]$existing.alpha_response)) -or
                           ($existing.PSObject.Properties.Name -contains "status" -and [string]$existing.status -match "^alpha_")
        if ($hasAlphaAttempt -and [string]$existing.owner -ne "user") {
            $existing | Add-Member -MemberType NoteProperty -Name "owner" -Value "user" -Force
            $existing | Add-Member -MemberType NoteProperty -Name "status" -Value "awaiting_user" -Force
            $existing | Add-Member -MemberType NoteProperty -Name "process_stage" -Value "user_decision" -Force
            $existing | Add-Member -MemberType NoteProperty -Name "escalation_level" -Value "user" -Force
            $existing | Add-Member -MemberType NoteProperty -Name "user_escalation_reason" -Value "Beta CEO hat denselben Audit-Fund erneut gemeldet, nachdem Alpha CEO bereits eingebunden war. Alpha konnte die Ursache offenbar nicht zielfuehrend beheben." -Force
            Write-Host "[AUDIT] Wiederholter Fund nach Alpha-Stufe: Eskalation an User hochgestuft." -ForegroundColor Yellow
            return
        }
        Write-Host "[AUDIT] Eskalation '$Topic' existiert bereits, keine Dublette." -ForegroundColor DarkGray
        return
    }

    $State.decisions_pending += @([ordered]@{
        id                       = $id
        topic                    = $Topic
        context                  = $Context
        created_at               = (Get-Date -Format 'o')
        status                   = $Status
        owner                    = $Owner
        source                   = "audit"
        process_stage            = $ProcessStage
        escalation_level         = $EscalationLevel
        remediation_command      = $RemediationCommand
        remediation_result       = $RemediationResult
        remediation_attempted_at = if ($RemediationResult) { (Get-Date -Format 'o') } else { $null }
        alpha_attempts           = 0
        user_escalation_reason   = $UserEscalationReason
    })
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

    # Ensure state array exists
    if (-not ($State.PSObject.Properties.Name -contains "decisions_pending")) {
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
    if ($State.PSObject.Properties.Name -contains "active_delegations" -and $null -ne $State.active_delegations) {
        $delegationsData = ($State.active_delegations | ForEach-Object { "- Issue #$($_.issue_number) an $($_.agent_type) (Session: $($_.jules_session_id)) - Status: $($_.jules_state)" }) -join "`n"
    }

    # 2. Prompt bauen
    $promptText = @"
Du bist CEO BETA (Gemini) des Vorce-Autopiloten.
Deine Aufgabe ist ein unabhaengiges AUDIT des aktuellen Projektstatus.

MANDAT DES USERS (VERLETZUNG FUEHRT ZUM ABBRUCH):
1. Du MUSST DEINE ANTWORT ZWINGEND AUF DEUTSCH VERFASSEN! Jede andere Sprache ist verboten.
2. Wenn du Probleme findest (z.B. fehlschlagende CI), DARFST DU NIEMALS SOFORT AN DEN USER ESKALIEREN! Du MUSST zuerst eine Aktion ('remediate') vorschlagen und damit selbst einen zielgerichteten Behebungsversuch starten.
3. STRENGES VERBOT FÜR MERGE-KONFLIKTE: Du darfst NIEMALS eigenmächtig Jules-Sessions für PR-Merge-Konflikte starten! Das Starten von Jules-Sessions für Merge-Konflikte wird bereits automatisch und gebündelt in der Planning-Phase übernommen. Jede redundante Jules-Session kostet den User wertvolles Tageslimit (100 Sessions/Tag).
4. STRENGES VERBOT FÜR JULES-CANCEL: Du darfst NIEMALS Befehle vorschlagen, die eine Jules-Session abbrechen, stoppen oder löschen! Das Limit von 100 Jules-Sessions pro Tag erfordert, dass fehlgeschlagene/hängende Sessions maximal pausiert (und vom User später re-purposed) werden, aber niemals gelöscht/gecancelt.
5. Nur wenn Remediation nicht zielfuehrend ist oder absolut klar ist, dass CEO Alpha planen/entscheiden muss, darfst du 'escalate' waehlen. Diese Eskalation geht IMMER zuerst an CEO Alpha, niemals direkt an den User.
6. JEDE Eskalation muss hochdetailliert sein! Kein unspezifisches BlaBla wie 'Erfordert sofortige manuelle Intervention'.
7. Eine korrekte Eskalation enthaelt:
   - Exakt WELCHER PR/Issue betroffen ist.
   - WARUM die KI es nicht selbst loesen konnte (welche Limits/Gruende?).
   - WAS genau der User tun soll (Schritt fuer Schritt).
8. Eskalationsprozess ist strikt: Beta CEO versucht Remediation -> falls nicht zielfuehrend: Eskalation an CEO Alpha fuer die naechste Planning-Session -> nur wenn Alpha nicht helfen konnte oder Owner-Rechte/Produktentscheidung zwingend sind: Eskalation an den User.
9. Nutze fuer einfache Analyse-/Fix-Aufgaben bevorzugt ein verfuegbares CLI Tool mit kurzem Prompt oder einen klar begrenzten lokalen Befehl. Keine langen Kontext-Dumps.

Aktuelle offene Issues:
$issuesData

Aktuelle offene Pull Requests:
$prsData

Aktive Agent-Delegationen (Tasks in Arbeit):
$delegationsData

Antworte strikt im JSON-Format:
{
  "issues_found": true/false,
  "action": "remediate|escalate|none",
  "remediation_command": "<Dein powershell Befehl zum autonomen Beheben, falls action=remediate>",
  "dashboard_escalation": "<DEUTSCHE, hochdetaillierte Fehler-Analyse und Handlungsanweisung, NUR falls action=escalate>"
}
"@

    Write-Host "[AUDIT] Sende Audit-Anfrage an CEO Beta (Gemini)..." -ForegroundColor Cyan

    $ToolsDir = Join-Path $ScriptDir "tools"
    $runVisibleCmd = Join-Path $ToolsDir "run-visible-ceo-phase.ps1"

    $promptFile = Join-Path $ScriptDir "tmp\beta-audit-prompt.txt"
    $promptText | Out-File -FilePath $promptFile -Encoding UTF8

    $outputFile = Join-Path $ScriptDir "tmp\beta-audit-result.json"

    $cliArgsFile = Join-Path $ScriptDir "tmp\beta-audit-args.json"
    @("-m", "gemini-2.5-flash", "--output-format", "json", "-y") | ConvertTo-Json -Depth 5 -Compress | Out-File $cliArgsFile -Encoding UTF8

    $statusFile = Join-Path $ScriptDir "tmp\beta-audit-status.txt"

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
                $dashboardAuditPath = Join-Path $ScriptDir "dashboard\public\audit-result.json"
                $rawAuditObj = Get-Content $outputFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $rawAuditObj | Add-Member -MemberType NoteProperty -Name "updated_at" -Value ((Get-Item $outputFile).LastWriteTime.ToString("o")) -Force
                if (Get-Command Write-SafeJson -ErrorAction SilentlyContinue) {
                    Write-SafeJson -FilePath $dashboardAuditPath -Data $rawAuditObj
                } else {
                    $rawAuditObj | ConvertTo-Json -Depth 20 | Set-Content $dashboardAuditPath -Encoding UTF8
                }

                $resultJson = Get-Content $outputFile -Raw -Encoding UTF8
                $parsedObj = $null
                $jsonObjMatch = [regex]::Match($resultJson, '(?s)\{.*\}')
                if ($jsonObjMatch.Success) {
                    $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json

                    # Handle wrapper JSON from CLI router if present
                    if ($null -ne $parsedObj -and $parsedObj.PSObject.Properties.Name -contains "response") {
                        # The response string might contain markdown json blocks like ```json ... ```
                        $cleanJson = $parsedObj.response -replace '(?s)```json\s*', '' -replace '(?s)```\s*$', ''
                        try {
                            $parsedObj = $cleanJson | ConvertFrom-Json
                        } catch {
                            Write-Warning "[AUDIT] Konnte eingebettetes JSON im Response nicht parsen."
                        }
                    }
                }

                if ($null -ne $parsedObj -and $parsedObj.issues_found -eq $true) {
                    Write-Host "[AUDIT] CEO Beta hat Probleme gefunden!" -ForegroundColor Yellow

                    if ($parsedObj.action -eq "remediate" -and -not [string]::IsNullOrWhiteSpace($parsedObj.remediation_command)) {
                        Write-Host "[AUDIT] Fuehre Remediation-Befehl aus: $($parsedObj.remediation_command)" -ForegroundColor Cyan
                        try {
                            Invoke-Expression $parsedObj.remediation_command | Out-Null
                            Write-Host "[AUDIT] Remediation erfolgreich gestartet." -ForegroundColor Green
                        } catch {
                            Write-Warning "[AUDIT] Remediation fehlgeschlagen: $_"
                            Add-AuditDecisionPending `
                                -State $State `
                                -Topic "Beta CEO Remediation Failed" `
                                -Context "Der Versuch, das Problem automatisch zu beheben, schlug fehl. Befehl: $($parsedObj.remediation_command). Fehler: $_`n`nNaechster Schritt: CEO Alpha muss in der naechsten Planning-Session zuerst einen konkreten Folgeplan erstellen. Erst wenn das nicht zielfuehrend ist, darf an den User eskaliert werden." `
                                -RemediationCommand ([string]$parsedObj.remediation_command) `
                                -RemediationResult "failed: $($_.Exception.Message)"
                        }
                    } elseif ($parsedObj.action -eq "escalate") {
                        Write-Host "[AUDIT] CEO Beta eskaliert an CEO Alpha fuer Planning." -ForegroundColor Red
                        Add-AuditDecisionPending `
                            -State $State `
                            -Topic "Beta CEO Audit Alert" `
                            -Context ([string]$parsedObj.dashboard_escalation) `
                            -RemediationCommand ([string]$parsedObj.remediation_command) `
                            -RemediationResult "beta_escalated_to_alpha"
                    }
                } else {
                    Write-Host "[AUDIT] CEO Beta meldet: Keine gravierenden Probleme gefunden." -ForegroundColor Green
                }
            } catch {
                Write-Warning "[AUDIT] Konnte Audit-Ergebnis nicht parsen: $_"
            }
        }
    }
}

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
    if (-not ($State.PSObject.Properties.Name -contains "decisions_pending") -or $null -eq $State.decisions_pending) {
        if (-not ($State.PSObject.Properties.Name -contains "decisions_pending")) {
            $State | Add-Member -MemberType NoteProperty -Name "decisions_pending" -Value @() -Force
        } else {
            $State.decisions_pending = @()
        }
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

    # 2. Prompt bauen
    $promptText = @"
Du bist der Auditor (Gemini CLI) des Vorce-Autopiloten.
Deine Aufgabe ist ein unabhaengiges AUDIT des aktuellen Projektstatus.

Aktuelle offene Issues:
$issuesData

Aktuelle offene Pull Requests:
$prsData

Aktive Agent-Delegationen (Tasks in Arbeit):
$delegationsData

AUFGABE:
Untersuche diese Daten auf logische Fehler, haengende Tasks (z.B. PRs im Konflikt ohne Fortschritt), blinde Flecken in der Planung oder architektonische Probleme.
Gibt es Aspekte, bei denen der User eingreifen muss, oder PRs, die einen Kommentar benoetigen?

Antworte strikt im JSON-Format:
{
  "issues_found": true/false,
  "dashboard_escalation": "<Wenn issues_found=true, beschreibe hier kurz das gefundene Problem als Eskalation fuer das Dashboard, sonst leer lassen>",
  "reasoning": "<Kurze Begruendung>"
}
"@

    Write-Host "[AUDIT] Starte Auditor-Session..." -ForegroundColor Cyan

    $promptFile = Join-Path $ScriptDir "tmp\beta-audit-prompt.txt"
    $promptText | Out-File -FilePath $promptFile -Encoding UTF8
    $outputFile = Join-Path $ScriptDir "tmp\beta-audit-result.json"

    if ($DryRun.IsPresent) {
        Write-Host "[AUDIT] [DRY RUN] Audit uebersprungen." -ForegroundColor DarkYellow
    } else {
        $auditResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "audit" -Prompt $promptText -WorkingDirectory $ScriptDir -State $State
        if (-not $auditResult.success) {
            Write-Warning "[AUDIT] Fehler beim Aufruf der Auditor-Session."
        }

        $resultJson = $auditResult.output
        if (-not [string]::IsNullOrWhiteSpace($resultJson)) {
            try {
                $parsedObj = $null
                # Strip markdown blocks if present
                $cleanJson = $resultJson -replace '(?s)```json\s*(.*?)\s*```', '$1'
                $cleanJson = $cleanJson -replace '(?s)```\s*(.*?)\s*```', '$1'

                # Attempt to parse directly first
                try {
                    $parsedObj = $cleanJson | ConvertFrom-Json
                } catch {
                    # Fallback regex extraction
                    $jsonObjMatch = [regex]::Match($cleanJson, '(?s)\{.*\}')
                    if ($jsonObjMatch.Success) {
                        $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json
                    }
                }

                if ($null -ne $parsedObj -and $parsedObj.issues_found -eq $true -and -not [string]::IsNullOrWhiteSpace($parsedObj.dashboard_escalation)) {
                    Write-Host "[AUDIT] Der Auditor hat Probleme gefunden und eine Eskalation erstellt!" -ForegroundColor Red

                    # Add to decisions pending
                    $State.decisions_pending += @([ordered]@{
                        topic      = "Auditor Alert"
                        context    = $parsedObj.dashboard_escalation
                        created_at = (Get-Date -Format 'o')
                    })
                    Write-Host "[AUDIT] Eskalation zum Dashboard gesendet." -ForegroundColor Yellow
                } else {
                    Write-Host "[AUDIT] Der Auditor meldet: Keine gravierenden Probleme gefunden." -ForegroundColor Green
                }
            } catch {
                Write-Warning "[AUDIT] Konnte Audit-Ergebnis nicht parsen: $_"
            }
        }
    }
}

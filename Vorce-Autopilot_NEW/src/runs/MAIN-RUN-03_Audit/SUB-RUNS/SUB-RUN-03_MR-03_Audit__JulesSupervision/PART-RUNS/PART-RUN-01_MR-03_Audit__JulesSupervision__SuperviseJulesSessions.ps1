# SUB-RUN-03_JulesSupervision.ps1 (Vorce 3.0)
# Überwacht Jules-Sessions auf Compliance und Sicherheit
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")

Write-VorceStep -Message "Starte JulesSupervision..." -Status "RUN"

# Überwache aktive Jules-Sessions
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
    Write-VorceStep -Message "Keine aktiven Jules-Sessions zum Überwachen." -Status "INFO"
    return @{ status="no_sessions_to_supervise"; sessions_supervised=0; compliance_issues_found=0; timestamp=(Get-Date).ToString("o") }
}

$julesSessions = $ConfigBag.GlobalState.active_delegations | Where-Object { $_.delegatedTo -eq "jules" }
$sessionsSupervised = 0
$complianceIssues = @()
$safetyIssues = @()

foreach ($session in $julesSessions) {
    $sessionsSupervised++
    Write-VorceStep -Message "Überwache Session #$($session.issueNumber): $($session.title)" -Status "RUN"

    # 1. Compliance-Checks
    $sessionCompliance = @{
        session_id = $session.issueNumber
        checks = @()
    }

    # Check 1: Ist der Status aktuell?
    $sessionCompliance.checks += @{
        type = "status_current";
        status = $session.status ?? "unknown";
        timestamp = $session.timestamp ?? "unknown"
    }

    # Check 2: Hat der Session eine gültige URL?
    if ($session.url -and ($session.url -match "github\.com.*issues")) {
        $sessionCompliance.checks += @{ type = "valid_github_url"; status = "ok" }
    } else {
        $sessionCompliance.checks += @{ type = "valid_github_url"; status = "error"; message = "Ungültige GitHub URL" }
        $complianceIssues += @{
            session = $session.issueNumber;
            issue = "invalid_github_url";
            severity = "high";
            message = "Session hat ungültige GitHub URL"
        }
    }

    # Check 3: Ist der Status "assigned", "active" oder "stalled"?
    $validStatuses = @("assigned", "active", "stalled")
    if ($validStatuses -contains $session.status) {
        $sessionCompliance.checks += @{ type = "valid_status"; status = "ok" }
    } else {
        $sessionCompliance.checks += @{ type = "valid_status"; status = "warning"; message = "Ungültiger Status: $($session.status)" }
        $complianceIssues += @{
            session = $session.issueNumber;
            issue = "invalid_status";
            severity = "medium";
            message = "Session hat ungültigen Status: $($session.status)"
        }
    }

    # 2. Safety-Checks
    $sessionSafety = @{
        session_id = $session.issueNumber;
        checks = @()
    }

    # Safety Check 1: Prüfe ob der Session innerhalb der Timeout-Grenzen ist
    if ($session.timestamp) {
        try {
            $sessionAge = (Get-Date) - [datetime]$session.timestamp
            if ($sessionAge.TotalHours -gt 48) {
                $sessionSafety.checks += @{
                    type = "timeout_check";
                    status = "warning";
                    age_hours = [math]::Round($sessionAge.TotalHours, 2)
                }
                $safetyIssues += @{
                    session = $session.issueNumber;
                    issue = "approaching_timeout";
                    severity = "medium";
                    message = "Session ist $($sessionAge.TotalHours) Stunden alt"
                }
            } else {
                $sessionSafety.checks += @{
                    type = "timeout_check";
                    status = "ok";
                    age_hours = [math]::Round($sessionAge.TotalHours, 2)
                }
            }
        } catch {
            $sessionSafety.checks += @{
                type = "timeout_check";
                status = "error";
                message = "Timestamp-Fehler: $($_.Exception.Message)"
            }
        }
    } else {
        $sessionSafety.checks += @{
            type = "timeout_check";
            status = "error";
            message = "Kein Timestamp verfügbar"
        }
    }

    # Speichere Ergebnisse in ParentState
    if (-not $ParentState.sessions_supervision) {
        $ParentState | Add-Member -MemberType NoteProperty -Name "sessions_supervision" -Value @{} -Force
    }
    $ParentState.sessions_supervision[$session.issueNumber] = @{
        compliance = $sessionCompliance;
        safety = $sessionSafety;
        timestamp = (Get-Date).ToString("o")
    }
}

# Erstelle Compliance-Bericht
$julesSupervisionResult = @{
    status = "completed"
    sessions_supervised = $sessionsSupervised
    compliance_issues_found = $complianceIssues.Count
    safety_issues_found = $safetyIssues.Count
    compliance_details = $complianceIssues
    safety_details = $safetyIssues
    timestamp = (Get-Date).ToString("o")
}

if ($complianceIssues.Count -gt 0 -or $safetyIssues.Count -gt 0) {
    Write-VorceStep -Message "JulesSupervision abgeschlossen: $($complianceIssues.Count) Compliance, $($safetyIssues.Count) Safety Issues" -Status "WARN"
} else {
    Write-VorceStep -Message "JulesSupervision abgeschlossen: $sessionsSupervised Sessions, keine Issues" -Status "OK"
}

return $julesSupervisionResult

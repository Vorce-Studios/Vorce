# SUB-RUN-02_JulesCheck.ps1 (Vorce 3.0)
# Prüft Status aktiver Jules-Sessions auf Fehler, Timeouts und Kompletions
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
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")
. (Join-Path $global:LibDir "integrations/ApiClient.ps1")

Write-VorceStep -Message "Starte JulesCheck..." -Status "RUN"

# 1. Lese active_delegations aus GlobalState
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
    Write-VorceStep -Message "Keine aktiven Delegations gefunden." -Status "INFO"
    return @{ status="no_active_sessions"; sessionsChecked=0; errorsFound=0; timestamp=(Get-Date).ToString("o") }
}

$activeDelegations = $ConfigBag.GlobalState.active_delegations | Where-Object { $_.delegatedTo -eq "jules" }
$sessionsChecked = 0
$errorsFound = 0
$sessionsCompleted = 0

# 2. Für jede Jules-Session: Prüfe Status
foreach ($session in $activeDelegations) {
    $sessionsChecked++

    Write-VorceStep -Message "Prüfe Jules-Session für Issue #$($session.issueNumber): $($session.title)" -Status "RUN"

    # 2a. Prüfe ob die Session noch aktiv ist
    try {
        $ghCommand = "gh issue view $($session.issueNumber) --repo $($ConfigBag.Config.repository) --json state,assignees,closedAt"

        $ghResult = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$($ConfigBag.Config.repository)/issues/$($session.issueNumber)" -Method GET

        # Status der GitHub Issue prüfen
        if ($ghResult.state -eq "closed") {
            $session.status = "completed"
            $session.completedAt = $ghResult.closedAt
            $session.completionReason = "github_closed"

            $sessionsCompleted++
            Write-VorceStep -Message "Session abgeschlossen (GitHub Issue geschlossen)" -Status "OK"
            continue
        }

        # 2b. Prüfe ob Jules der Assignee ist
        $isJulesAssigned = $false
        if ($ghResult.assignees) {
            foreach ($assignee in $ghResult.assignees) {
                if ($assignee.login -eq "jules" -or $assignee.login -eq "jules-studio") {
                    $isJulesAssigned = $true
                    break
                }
            }
        }

        if (-not $isJulesAssigned) {
            $session.status = "orphaned"
            $session.error = "Jules ist kein Assignee mehr"

            $errorsFound++
            Write-VorceStep -Message "ORPHANED: Jules ist kein Assignee mehr" -Status "ERROR"
            continue
        }

        # 2c. Prüfe ob die Session Timeout hat
        $maxSessionAge = 48 * 60 * 60  # 48 Stunden in Sekunden
        if ($session.timestamp) {
            $sessionAge = (Get-Date).ToUniversalTime().Subtract([datetime]$session.timestamp).TotalSeconds
            if ($sessionAge -gt $maxSessionAge) {
                $session.status = "timeout"
                $session.error = "Session älter als 48 Stunden"
                $session.timeoutAt = (Get-Date).ToString("o")

                $errorsFound++
                Write-VorceStep -Message "TIMEOUT: Session ist $($sessionAge/3600) Stunden alt" -Status "ERROR"
                continue
            }
        }

        # 2d. Prüfe ob Comments von Jules vorhanden sind
        $commentsResult = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$($ConfigBag.Config.repository)/issues/$($session.issueNumber)/comments" -Method GET
        $julesComments = @($commentsResult | Where-Object { $_.user.login -eq "jules" -or $_.user.login -eq "jules-studio" })

        if ($julesComments.Count -eq 0) {
            $session.status = "stalled"
            $session.lastActivity = ($commentsResult[0]?.created_at ?? $ghResult.createdAt)

            Write-VorceStep -Message "STALLED: Keine Jules Comments gefunden" -Status "WARN"
        } else {
            $session.status = "active"
            $session.lastActivity = ($julesComments[-1].created_at)

            Write-VorceStep -Message "ACTIVE: $($julesComments.Count) Jules Comments" -Status "OK"
        }

    } catch {
        $session.status = "error"
        $session.error = $($_.Exception.Message)

        $errorsFound++
        Write-VorceStep -Message "ERROR: $_" -Status "ERROR"
    }
}

# 3. Speichere aktualisierten GlobalState
Save-VorceGlobalState -State $ConfigBag.GlobalState

# 4. Gib State mit Statistik zurück
$julesCheckResult = @{
    status = "completed"
    sessionsChecked = $sessionsChecked
    sessionsCompleted = $sessionsCompleted
    errorsFound = $errorsFound
    activeSessions = ($activeDelegations | Where-Object { $_.status -eq "active" }).Count
    stalledSessions = ($activeDelegations | Where-Object { $_.status -eq "stalled" }).Count
    timeoutSessions = ($activeDelegations | Where-Object { $_.status -eq "timeout" }).Count
    orphanedSessions = ($activeDelegations | Where-Object { $_.status -eq "orphaned" }).Count
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "JulesCheck abgeschlossen: $sessionsChecked Sessions geprüft, $sessionsCompleted abgeschlossen, $errorsFound Fehler." -Status "OK"
return $julesCheckResult

# SUB-RUN-05_JulesRefill.ps1 (Vorce 3.0)
# Prüft ob freie Jules-Slots verfügbar und erstellt neue Sessions für unassigned Tasks
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
. (Join-Path $global:LibDir "integrations/ApiClient.ps1")

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

Write-VorceStep -Message "Starte JulesRefill..." -Status "RUN"

# 1. Prüfe ob monitoring_refill_enabled
if (-not $ConfigBag.Config.monitoring_refill_enabled) {
    Write-VorceStep -Message "JulesRefill ist deaktiviert." -Status "INFO"
    return @{ status="disabled"; refill_sessions_created=0; timestamp=(Get-Date).ToString("o") }
}

# 2. Prüfe ob freie Jules-Slots verfügbar
$quotaOK = Test-VorceQuota -AgentName "jules"
if (-not $quotaOK) {
    Write-VorceStep -Message "Keine freien Jules-Slots verfügbar." -Status "WARN"
    return @{ status="no_quota_available"; refill_sessions_created=0; timestamp=(Get-Date).ToString("o") }
}

# 3. Lese task-journal.json nach unassigned Tasks suchen
$taskJournalPath = Join-Path $global:VarDir "db/task-journal.json"
$unassignedTasks = @()

if (Test-Path $taskJournalPath) {
    try {
        $taskJournal = Get-Content $taskJournalPath -Raw | ConvertFrom-Json
        $unassignedTasks = @($taskJournal.delegations | Where-Object {
            $_.status -eq "pending" -and $_.agent -eq "jules" -and $_.sessionCreatedAt -eq $null
        })
    } catch {
        Write-VorceStep -Message "Fehler beim Lesen von task-journal.json: $($_.Exception.Message)" -Status "ERROR"
    }
}

if ($unassignedTasks.Count -eq 0) {
    Write-VorceStep -Message "Keine unassigned Jules-Tasks gefunden." -Status "INFO"
    return @{ status="no_unassigned_tasks"; refill_sessions_created=0; timestamp=(Get-Date).ToString("o") }
}

Write-VorceStep -Message "Gefunden $($unassignedTasks.Count) unassigned Tasks" -Status "INFO"

# 4. Für jeden freien Task: Erstelle neue Jules-Session
$refillSessionsCreated = 0
$maxSessionsToCreate = [Math]::Min($unassignedTasks.Count, 3)  # Max 3 neue Sessions pro Lauf

for ($i = 0; $i -lt $maxSessionsToCreate; $i++) {
    $task = $unassignedTasks[$i]

    Write-VorceStep -Message "Erstelle Jules-Session für Task: $($task.title)" -Status "RUN"

    try {
        # Erstelle GitHub Issue für den Task
        $repo = $ConfigBag.Config.repository
        $taskTitle = "Jules Task: $($task.title)"
        $taskBody = @"
**Task Type:** $($task.taskType ?? "general")

**Original Issue:** #$(if ($task.issueNumber) { $task.issueNumber } else { "unknown" })

**Delegated from:** Vorce Autopilot

**Task Details:**
$(if ($task.description) { $task.description } else { "Keine zusätzlichen Details."})

**Requirements:**
- Erledige diese Aufgabe gemäß den Vorgaben
- Aktualisiere den Status dieser Issue
- Nutze die im Task beschriebenen Vorgaben

**Status:** In Progress
**Assigned to:** @jules
**Created by:** Vorce Autopilot
"@

        # GitHub Issue erstellen
        $newIssue = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$repo/issues" -Method POST -Body @{
            title = $taskTitle
            body = $taskBody
            labels = @("jules-task", "autopilot-created", "in-progress")
        }

        # Aktualisiere Task mit Issue Information
        $task.sessionCreatedAt = (Get-Date).ToString("o")
        $task.issueUrl = $newIssue.html_url
        $task.issueNumber = $newIssue.number
        $task.status = "assigned"

        # Aktualisiere task-journal.json
        $taskJournal | ConvertTo-Json -Depth 10 | Set-Content $taskJournalPath -Encoding UTF8

        # Aktualisiere GlobalState.active_delegations
        if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
            $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
        }

        $newDelegation = @{
            issueNumber = $newIssue.number
            title = $task.title
            url = $newIssue.html_url
            status = "assigned"
            delegatedTo = "jules"
            timestamp = (Get-Date).ToString("o")
        }
        $ConfigBag.GlobalState.active_delegations += $newDelegation

        # Registriere Quota-Usage
        Register-VorceQuotaUsage -AgentName "jules" -Cost 0.5

        $refillSessionsCreated++

        Write-VorceStep -Message "Jules Session erstellt: $($newIssue.html_url)" -Status "OK"

    } catch {
        Write-VorceStep -Message "Fehler beim Erstellen von Jules Session: $($_.Exception.Message)" -Status "ERROR"
        $task.status = "failed"
        $task.error = $_.Exception.Message
    }
}

# 5. Speichere GlobalState
Save-VorceGlobalState -State $ConfigBag.GlobalState

# 6. Gib State mit Statistik zurück
$julesRefillResult = @{
    status = "completed"
    refill_sessions_created = $refillSessionsCreated
    quota_available_before = $quotaOK
    unassigned_tasks_found = $unassignedTasks.Count
    remaining_unassigned = ($unassignedTasks.Count - $refillSessionsCreated)
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "JulesRefill abgeschlossen: $refillSessionsCreated neue Sessions erstellt." -Status "OK"
return $julesRefillResult

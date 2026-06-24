# SUB-RUN-05_JulesRefill.ps1 (Vorce 3.0)
# Creates GitHub issues for unassigned Jules tasks when capacity is available.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [hashtable]$ConfigBag,

    [Parameter(Mandatory)]
    [object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'state/StateManager.ps1')
. (Join-Path $global:LibDir 'engines/QuotaManager.ps1')
. (Join-Path $global:LibDir 'integrations/GitHubClient.ps1')

function Set-VorceRefillTaskProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Task,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($Task.PSObject.Properties.Name -contains $Name) {
        $Task.$Name = $Value
    } else {
        $Task | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

Write-VorceStep -Message 'Starte JulesRefill...' -Status 'RUN'

if (-not $ConfigBag.Config.jules.monitoring_refill_enabled) {
    Write-VorceStep -Message 'JulesRefill ist deaktiviert.' -Status 'INFO'
    return @{ status = 'disabled'; refill_sessions_created = 0; timestamp = (Get-Date).ToString('o') }
}

$quotaOK = Test-VorceQuota -AgentName 'jules'
if (-not $quotaOK) {
    Write-VorceStep -Message 'Keine freien Jules-Slots verfuegbar.' -Status 'WARN'
    return @{ status = 'no_quota_available'; refill_sessions_created = 0; timestamp = (Get-Date).ToString('o') }
}

$taskJournalPath = Join-Path $global:VarDir 'db/task-journal.json'
$unassignedTasks = @()
$taskJournal = $null
if (Test-Path -LiteralPath $taskJournalPath -PathType Leaf) {
    try {
        $taskJournal = Get-Content -LiteralPath $taskJournalPath -Raw | ConvertFrom-Json
        $unassignedTasks = @($taskJournal.delegations | Where-Object {
            $_.status -eq 'pending' -and
            ($_.agent -eq 'jules' -or $_.delegatedTo -eq 'jules') -and
            $null -eq $_.sessionCreatedAt
        })
    } catch {
        Write-VorceStep -Message "Fehler beim Lesen von task-journal.json: $($_.Exception.Message)" -Status 'ERROR'
    }
}

if ($unassignedTasks.Count -eq 0) {
    Write-VorceStep -Message 'Keine unassigned Jules-Tasks gefunden.' -Status 'INFO'
    return @{ status = 'no_unassigned_tasks'; refill_sessions_created = 0; timestamp = (Get-Date).ToString('o') }
}

Write-VorceStep -Message "Gefunden $($unassignedTasks.Count) unassigned Tasks" -Status 'INFO'

$refillSessionsCreated = 0
$maxSessionsToCreate = [Math]::Min($unassignedTasks.Count, 3)
$repo = [string]$ConfigBag.Config.repository

for ($index = 0; $index -lt $maxSessionsToCreate; $index++) {
    $task = $unassignedTasks[$index]
    $commandResult = $null
    Write-VorceStep -Message "Erstelle Jules-Session fuer Task: $($task.title)" -Status 'RUN'

    try {
        $taskTitle = "Jules Task: $($task.title)"
        $taskType = if ($null -ne $task.taskType) { $task.taskType } else { 'general' }
        $originalIssue = if ($task.issueNumber) { $task.issueNumber } else { 'unknown' }
        $details = if ($task.description) { $task.description } else { 'Keine zusaetzlichen Details.' }
        $taskBody = @"
**Task Type:** $taskType

**Original Issue:** #$originalIssue

**Delegated from:** Vorce-Factory

**Task Details:**
$details

**Requirements:**
- Erledige diese Aufgabe gemaess den Vorgaben
- Aktualisiere den Status dieser Issue
- Nutze die im Task beschriebenen Vorgaben

**Status:** In Progress
**Assigned to:** @jules
**Created by:** Vorce-Factory
"@

        $commandResult = Invoke-VorceGitHubCommand -Arguments @(
            'issue', 'create',
            '--repo', $repo,
            '--title', $taskTitle,
            '--label', 'jules-task',
            '--label', 'autopilot-created',
            '--label', 'in-progress',
            '--body', $taskBody
        )
        if (-not $commandResult.Succeeded) {
            throw "gh issue create fehlgeschlagen: $(Get-VorceGitHubCommandDiagnostic -Result $commandResult)"
        }

        $issueUrl = ([string]$commandResult.StdOut).Trim()
        if ($issueUrl -match '(https?://\S+)') {
            $issueUrl = $Matches[1]
        }
        if ([string]::IsNullOrWhiteSpace($issueUrl)) {
            throw 'gh issue create lieferte keine Issue-URL.'
        }

        $issueNumber = $null
        if ($issueUrl -match '/issues/(\d+)(?:$|[/?#])') {
            $issueNumber = [int]$Matches[1]
        }

        Set-VorceRefillTaskProperty -Task $task -Name 'sessionCreatedAt' -Value (Get-Date).ToString('o')
        Set-VorceRefillTaskProperty -Task $task -Name 'issueUrl' -Value $issueUrl
        Set-VorceRefillTaskProperty -Task $task -Name 'issueNumber' -Value $issueNumber
        Set-VorceRefillTaskProperty -Task $task -Name 'status' -Value 'assigned'
        $taskJournal | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $taskJournalPath -Encoding UTF8

        if ($ConfigBag.GlobalState.PSObject.Properties.Name -notcontains 'active_delegations') {
            $ConfigBag.GlobalState |
                Add-Member -MemberType NoteProperty -Name 'active_delegations' -Value @() -Force
        }

        $ConfigBag.GlobalState.active_delegations += @{
            issueNumber = $issueNumber
            title = $task.title
            url = $issueUrl
            status = 'assigned'
            delegatedTo = 'jules'
            timestamp = (Get-Date).ToString('o')
        }

        Register-VorceQuotaUsage -AgentName 'jules' -Cost 0.5 | Out-Null
        $refillSessionsCreated++
        Write-VorceStep -Message "Jules Session erstellt: $issueUrl" -Status 'OK'
    } catch {
        Write-VorceStep -Message "Fehler beim Erstellen von Jules Session: $($_.Exception.Message)" -Status 'ERROR'
        Set-VorceRefillTaskProperty -Task $task -Name 'status' -Value 'failed'
        Set-VorceRefillTaskProperty -Task $task -Name 'error' -Value $_.Exception.Message
        if ($commandResult) {
            Set-VorceRefillTaskProperty -Task $task -Name 'error_class' -Value $commandResult.ErrorClass
        }
    }
}

Save-VorceGlobalState -State $ConfigBag.GlobalState

$julesRefillResult = @{
    status = 'completed'
    refill_sessions_created = $refillSessionsCreated
    quota_available_before = $quotaOK
    unassigned_tasks_found = $unassignedTasks.Count
    remaining_unassigned = $unassignedTasks.Count - $refillSessionsCreated
    timestamp = (Get-Date).ToString('o')
}

Write-VorceStep -Message "JulesRefill abgeschlossen: $refillSessionsCreated neue Sessions erstellt." -Status 'OK'
return $julesRefillResult

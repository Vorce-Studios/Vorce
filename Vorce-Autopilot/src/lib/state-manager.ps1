# Vorce-Autopilot/src/lib/state-manager.ps1
# Manages autopilot-state.json for crash recovery in the new var/db/ structure
# Includes atomic writes and orphan TMP cleanup

Set-StrictMode -Version Latest

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:VarDbDir = Join-Path $script:ScriptRoot "var/db"
$script:StateFilePath = Join-Path $script:VarDbDir "autopilot-state.json"

# Ensure var/db directory exists
if (-not (Test-Path -Path $script:VarDbDir)) {
    New-Item -ItemType Directory -Path $script:VarDbDir -Force | Out-Null
}

function Write-SafeJson {
    <#
    .SYNOPSIS
    Atomic JSON write: writes to a temp file first, then renames.
    Cleans up any orphaned TMP files for the target path.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][object]$Data,
        [int]$Depth = 10
    )

    $dir = Split-Path -Parent $FilePath
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $baseName = Split-Path -Leaf $FilePath
    $tmpPath = Join-Path $dir "$baseName.$([guid]::NewGuid().ToString('N')).tmp"

    try {
        $Data | ConvertTo-Json -Depth $Depth | Set-Content $tmpPath -Encoding UTF8 -ErrorAction Stop
        # Atomic rename
        if (Test-Path $FilePath) {
            [System.IO.File]::Delete($FilePath)
        }
        [System.IO.File]::Move($tmpPath, $FilePath)
    }
    catch {
        # Cleanup failed temp file
        if (Test-Path $tmpPath) {
            Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue
        }
        # Fallback: direct write
        $Data | ConvertTo-Json -Depth $Depth | Set-Content $FilePath -Encoding UTF8
    }
}

function Read-JsonLocked {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    $attempts = 3
    while ($attempts -gt 0) {
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
            if ([string]::IsNullOrWhiteSpace($content)) { return $null }
            return ($content | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            $attempts--
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { return $null }
        return ($content | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Write-JsonLocked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Data,
        [int]$Depth = 10
    )

    Write-SafeJson -FilePath $Path -Data $Data -Depth $Depth
}

function Update-JsonLocked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Updater,
        [object]$DefaultValue = $null
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $attempts = 3
    $lastError = $null
    while ($attempts -gt 0) {
        $fileStream = $null
        $reader = $null
        $writer = $null
        try {
            $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
            $content = $reader.ReadToEnd()
            $reader.Dispose()

            $data = $null
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $data = $content | ConvertFrom-Json -ErrorAction Stop
            } else {
                $data = $DefaultValue
            }

            $updatedData = & $Updater $data

            $fileStream.SetLength(0)
            $fileStream.Position = 0
            $writer = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8, 1024, $true)
            $json = $updatedData | ConvertTo-Json -Depth 10
            $writer.Write($json)
            $writer.Flush()

            $writer.Dispose()
            $fileStream.Dispose()
            return $updatedData
        } catch {
            $lastError = $_.Exception
            if ($null -ne $writer) { $writer.Dispose() }
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $fileStream) { $fileStream.Dispose() }
            if ($lastError -isnot [System.IO.IOException]) {
                throw "JSON-Update fuer '$Path' fehlgeschlagen: $($lastError.Message)"
            }
            $attempts--
            Start-Sleep -Milliseconds 100
        }
    }
    throw "Konnte JSON-Datei nach 10 Versuchen nicht exklusiv sperren und updaten: $Path. Letzter Fehler: $($lastError.Message)"
}


function Remove-OrphanedTmpFiles {
    <#
    .SYNOPSIS
    Removes orphaned .tmp files matching the pattern: <filename>.<guid>.tmp
    Only removes files older than the specified threshold (default 5 minutes).
    #>
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$FilePattern = "*.tmp",
        [int]$OlderThanMinutes = 5
    )

    $cutoff = (Get-Date).AddMinutes(-$OlderThanMinutes)
    $orphans = Get-ChildItem -Path $Directory -Filter $FilePattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff }

    $count = 0
    foreach ($f in $orphans) {
        try {
            Remove-Item $f.FullName -Force -ErrorAction Stop
            $count++
        } catch {
            # File may be locked, skip
        }
    }

    if ($count -gt 0) {
        Write-Host "[CLEANUP] $count verwaiste TMP-Dateien aus $(Split-Path -Leaf $Directory) entfernt." -ForegroundColor DarkGray
    }

    return $count
}

function Test-ObjectProperty {
    <#
    .SYNOPSIS
    Safely tests if a PSObject has a given property.
    Centralized here so all modules can use it.
    #>
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) { return $false }
    try {
        if ($Object -is [System.Collections.IDictionary]) {
            return $Object.Contains($Name)
        }
        return @($Object.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name
    } catch {
        return $false
    }
}

function Update-AutopilotStateObject {
    <#
    .SYNOPSIS
    Ensures all expected properties exist on the state object and that
    array fields are actual arrays. Call this at the start of any phase
    that mutates state to avoid "property not found" errors.
    #>
    param([Parameter(Mandatory)][object]$State)

    $defaults = New-AutopilotState

    # Ensure every default property exists
    foreach ($key in $defaults.PSObject.Properties.Name) {
        if (-not ($State.PSObject.Properties.Name -contains $key)) {
            $State | Add-Member -MemberType NoteProperty -Name $key -Value $defaults.$key -Force
        }
    }

    # Validate that array fields are actual arrays (deserialization can turn them into single objects or $null)
    $arrayFields = @(
        "active_delegations", "working_queue", "working_sessions",
        "review_queue", "autopilot_created_issues", "completed_this_session",
        "decisions_pending", "escalated_issues", "error_log", "deliberation_log",
        "optimizer_queue"
    )
    foreach ($key in $arrayFields) {
        if ($null -eq $State.$key) {
            $State.$key = @()
        } elseif ($State.$key -isnot [System.Array] -and $State.$key -isnot [System.Collections.IList]) {
            $State.$key = @($State.$key)
        }
    }

    return $State
}

function Invoke-StartupCleanup {
    <#
    .SYNOPSIS
    Runs cleanup on all known directories that accumulate TMP files.
    Called once at autopilot startup.
    #>

    $dirsToClean = @(
        $script:VarDbDir,
        (Join-Path $script:ScriptRoot "dashboard/public")
    )

    $totalCleaned = 0
    foreach ($dir in $dirsToClean) {
        if (Test-Path $dir) {
            $totalCleaned += Remove-OrphanedTmpFiles -Directory $dir -OlderThanMinutes 2
        }
    }

    if ($totalCleaned -gt 0) {
        Write-Host "[CLEANUP] Startup-Bereinigung: $totalCleaned TMP-Dateien insgesamt entfernt." -ForegroundColor Green
    }
}

function New-AutopilotState {
    return [PSCustomObject]@{
        schema_version          = 1
        session_id              = "autopilot-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
        started_at              = (Get-Date -Format 'o')
        last_heartbeat          = (Get-Date -Format 'o')
        last_planning_at        = $null
        last_monitoring_at      = $null
        active_delegations      = @()
        working_queue           = @()
        working_sessions        = @()
        review_queue            = @()
        autopilot_created_issues = @()
        completed_this_session  = @()
        decisions_pending       = @()
        escalated_issues        = @()
        error_log               = @()
        deliberation_log        = @()
        optimizer_queue         = @()
        last_optimizer_analysis_at = $null
        optimizer_last_run      = $null
        run_summaries           = [pscustomobject]@{
            planning = $null
            monitoring = $null
        }
        run_control             = [pscustomobject]@{}
    }
}

function Read-AutopilotState {
    if (-not (Test-Path $script:StateFilePath)) {
        return $null
    }

    try {
        $content = Get-Content $script:StateFilePath -Raw -Encoding UTF8
        return ($content | ConvertFrom-Json)
    } catch {
        Write-Warning "State-Datei beschaedigt: $_"
        return $null
    }
}

function Save-AutopilotState {
    param([Parameter(Mandatory)][object]$State)

    $State.last_heartbeat = (Get-Date -Format 'o')
    Write-SafeJson -FilePath $script:StateFilePath -Data $State
}

function Initialize-AutopilotState {
    [CmdletBinding()]
    param([switch]$Force)

    # Run startup cleanup before anything else
    Invoke-StartupCleanup

    $existing = Read-AutopilotState
    $defaults = New-AutopilotState

    if ($null -ne $existing -and -not $Force.IsPresent -and ($existing -is [System.Management.Automation.PSCustomObject] -or $existing -is [System.Collections.IDictionary])) {
        # Ensure all default properties exist on the existing state
        foreach ($key in $defaults.PSObject.Properties.Name) {
            if (-not ($existing.PSObject.Properties.Name -contains $key)) {
                $existing | Add-Member -MemberType NoteProperty -Name $key -Value $defaults.$key -Force
            }
        }

        # Validate that arrays are indeed arrays (sometimes deserialized as single object or null)
        foreach ($key in @("active_delegations", "working_queue", "working_sessions", "review_queue", "autopilot_created_issues", "completed_this_session", "decisions_pending", "escalated_issues", "error_log", "deliberation_log", "optimizer_queue")) {
            if ($null -eq $existing.$key) {
                $existing.$key = @()
            } elseif ($existing.$key -isnot [System.Array] -and $existing.$key -isnot [System.Collections.IList]) {
                $existing.$key = @($existing.$key)
            }
        }

        $lastBeat = $null
        if ($existing.last_heartbeat) {
            try {
                $lastBeat = [datetimeoffset]::Parse($existing.last_heartbeat, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            } catch {
                try {
                    # Fallback: try current culture
                    $lastBeat = [datetimeoffset]::Parse([string]$existing.last_heartbeat)
                } catch {
                    Write-Warning "[INIT] Konnte last_heartbeat nicht parsen: $($existing.last_heartbeat)"
                }
            }
        }

        $ago = if ($lastBeat) {
            $diff = (Get-Date) - $lastBeat.LocalDateTime
            "{0:N0} Minuten" -f $diff.TotalMinutes
        } else { "unbekannt" }

        Write-Host ""
        Write-Host "=====================================================" -ForegroundColor Yellow
        Write-Host "  VORCE AUTOPILOT - Recovery Mode (Optimized Version)" -ForegroundColor Yellow
        Write-Host "=====================================================" -ForegroundColor Yellow
        Write-Host "  Session:        $($existing.session_id)"
        Write-Host "  Letzter Beat:   vor $ago"
        Write-Host "  Delegierungen:  $($existing.active_delegations.Count) aktiv"
        Write-Host "  Review-Queue:   $($existing.review_queue.Count)"
        Write-Host "  Entscheidungen: $($existing.decisions_pending.Count) offen"
        Write-Host "=====================================================" -ForegroundColor Yellow
        Write-Host ""

        return $existing
    }

    $state = New-AutopilotState
    Save-AutopilotState -State $state
    Write-Host "[AUTOPILOT] Neuer State erstellt: $($state.session_id)" -ForegroundColor Green
    return $state
}

function Confirm-WorkingSessionsState {
    param([Parameter(Mandatory)][object]$State)

    foreach ($prop in @("working_queue", "working_sessions")) {
        if (-not ($State.PSObject.Properties.Name -contains $prop)) {
            $State | Add-Member -MemberType NoteProperty -Name $prop -Value @() -Force
        } elseif ($null -eq $State.$prop) {
            $State.$prop = @()
        } elseif ($State.$prop -isnot [System.Array] -and $State.$prop -isnot [System.Collections.IList]) {
            $State.$prop = @($State.$prop)
        }
    }
}

function Add-Delegation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$IssueTitle,
        [string]$JulesSessionId,
        [string]$AgentType = "jules",
        [string]$JobId = ""
    )

    $delegation = [ordered]@{
        issue_number     = $IssueNumber
        issue_title      = $IssueTitle
        jules_session_id = $JulesSessionId
        agent_type       = $AgentType
        job_id           = $JobId
        jules_state      = "QUEUED"
        pr_url           = $null
        delegated_at     = (Get-Date -Format 'o')
        last_checked_at  = (Get-Date -Format 'o')
        retry_count      = 0
    }

    $State.active_delegations += @($delegation)
    Save-AutopilotState -State $State
}

function Update-DelegationState {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$JulesState,
        [string]$PrUrl
    )

    foreach ($d in $State.active_delegations) {
        if ([int]$d.issue_number -eq $IssueNumber) {
            $d.jules_state = $JulesState
            $d.last_checked_at = (Get-Date -Format 'o')
            if (-not [string]::IsNullOrWhiteSpace($PrUrl)) {
                $d.pr_url = $PrUrl
            }
            break
        }
    }

    Save-AutopilotState -State $State
}

function Complete-Delegation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$Result = "merged"
    )

    $completed = $State.active_delegations | Where-Object { [int]$_.issue_number -eq $IssueNumber }
    $State.active_delegations = @($State.active_delegations | Where-Object { [int]$_.issue_number -ne $IssueNumber })

    if ($completed) {
        $State.completed_this_session += @([ordered]@{
            issue_number = $IssueNumber
            result       = $Result
            completed_at = (Get-Date -Format 'o')
        })
    }

    Save-AutopilotState -State $State
}

function Add-ReviewItem {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$PrUrl,
        [int]$PrNumber,
        [string]$PrUpdatedAt
    )

    $existing = $State.review_queue | Where-Object { [int]$_.pr_number -eq $PrNumber } | Select-Object -First 1
    if ($existing) {
        if (-not [string]::IsNullOrWhiteSpace($PrUrl)) {
            $existing.pr_url = $PrUrl
        }
        if ($IssueNumber -gt 0) {
            $existing.issue_number = $IssueNumber
        }
        if (-not [string]::IsNullOrWhiteSpace($PrUpdatedAt)) {
            $reviewedRevision = if (Test-ObjectProperty -Object $existing -Name "reviewed_pr_updated_at") { [string]$existing.reviewed_pr_updated_at } else { "" }
            $existing | Add-Member -MemberType NoteProperty -Name "pr_updated_at" -Value $PrUpdatedAt -Force
            if ($existing.review_status -eq "completed" -and $reviewedRevision -ne $PrUpdatedAt) {
                $existing.review_status = "pending"
                $existing | Add-Member -MemberType NoteProperty -Name "review_provider" -Value $null -Force
            }
        }
        Save-AutopilotState -State $State
        return
    }

    $State.review_queue += @([ordered]@{
        issue_number  = $IssueNumber
        pr_url        = $PrUrl
        pr_number     = $PrNumber
        review_status = "pending"
        review_provider = $null
        pr_updated_at = $PrUpdatedAt
        reviewed_pr_updated_at = $null
        reviewed_at = $null
    })

    Save-AutopilotState -State $State
}

function Add-ErrorLog {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Message,
        [string]$Context
    )

    $State.error_log += @([ordered]@{
        timestamp = (Get-Date -Format 'o')
        message   = $Message
        context   = $Context
    })

    # Keep only last 50 errors
    if ($State.error_log.Count -gt 50) {
        $State.error_log = @($State.error_log | Select-Object -Last 50)
    }

    Save-AutopilotState -State $State
}

function Add-DeliberationLog {
    <#
    .SYNOPSIS
    Adds a deliberation summary to the autopilot state for dashboard display.
    Keeps only the last 20 entries.
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Protocol
    )

    # Ensure deliberation_log exists
    $hasField = $State.PSObject.Properties.Name -contains "deliberation_log"
    if (-not $hasField) {
        $State | Add-Member -NotePropertyName "deliberation_log" -NotePropertyValue @() -Force
    }

    $totalMs = 0
    if ($Protocol.rounds) {
        $totalMs = ($Protocol.rounds | ForEach-Object { $_.duration_ms } | Measure-Object -Sum).Sum
    }

    $entry = [ordered]@{
        deliberation_id   = $Protocol.deliberation_id
        task_type         = $Protocol.task_type
        alpha_provider    = $Protocol.alpha.provider
        beta_provider     = $Protocol.beta.provider
        consensus_reached = $Protocol.consensus_reached
        phases_completed  = $Protocol.rounds.Count
        total_duration_ms = [int]$totalMs
        completed_at      = $Protocol.completed_at
        rounds            = $Protocol.rounds
    }

    $State.deliberation_log += @($entry)

    # Keep only last 20
    if ($State.deliberation_log.Count -gt 20) {
        $State.deliberation_log = @($State.deliberation_log | Select-Object -Last 20)
    }

    Save-AutopilotState -State $State
}

function Set-DelegationEscalation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$Reason,
        [string]$FailureDetails,
        [string]$NextRetryAt
    )

    $delegation = $State.active_delegations | Where-Object { [int]$_.issue_number -eq $IssueNumber }
    if (-not $delegation) { return }

    # Sichern der Werte, da die Delegation gleich geloescht wird
    $issueTitle = $delegation.issue_title
    $sessionId = $delegation.jules_session_id

    # Entferne aus active_delegations
    $State.active_delegations = @($State.active_delegations | Where-Object { [int]$_.issue_number -ne $IssueNumber })

    # Suche in escalated_issues
    $esc = $State.escalated_issues | Where-Object { [int]$_.issue_number -eq $IssueNumber }
    $maxPlanningResolutions = 2 # Konfigurierbar, standardmäßig 2 Re-Planning Versuche
    if ($null -eq $esc) {
        $newEsc = [ordered]@{
            issue_number          = $IssueNumber
            issue_title           = $issueTitle
            last_jules_session_id = $sessionId
            monitoring_failures   = 1
            planning_resolutions  = 0
            status                = "QUEUED_FOR_RETRY"
            escalated_at          = (Get-Date -Format 'o')
            failure_reason        = $Reason
            failure_details       = $FailureDetails
            next_retry_phase      = "planning"
            next_retry_at         = $NextRetryAt
        }
        $State.escalated_issues += @($newEsc)
        Write-Host "[STATE] Issue #$IssueNumber fehlgeschlagen (1. Versuch). Wird für Retry eingereiht." -ForegroundColor Yellow
    } else {
        $esc.monitoring_failures = [int]$esc.monitoring_failures + 1
        $esc.last_jules_session_id = $sessionId
        $esc | Add-Member -MemberType NoteProperty -Name "failure_reason" -Value $Reason -Force
        $esc | Add-Member -MemberType NoteProperty -Name "failure_details" -Value $FailureDetails -Force
        $esc | Add-Member -MemberType NoteProperty -Name "next_retry_phase" -Value "planning" -Force
        $esc | Add-Member -MemberType NoteProperty -Name "next_retry_at" -Value $NextRetryAt -Force

        if ([int]$esc.monitoring_failures -lt 3) {
            $esc.status = "QUEUED_FOR_RETRY"
            Write-Host "[STATE] Issue #$IssueNumber fehlgeschlagen ($($esc.monitoring_failures). Versuch). Wird für Retry eingereiht." -ForegroundColor Yellow
        } else {
            if ([int]$esc.planning_resolutions -ge $maxPlanningResolutions) {
                # Letzte Eskalationsstufe: An User eskalieren!
                $esc.status = "ESCALATED_TO_USER"

                $topic = "Issue #$IssueNumber endgueltig eskaliert an User"
                $exists = $State.decisions_pending | Where-Object { $_.topic -eq $topic }
                if (-not $exists) {
                    $State.decisions_pending += @([ordered]@{
                        topic      = $topic
                        context    = "Das Issue konnte auch nach CEO-Re-Planning nicht geloest werden. Letzte Jules Session: $sessionId."
                        created_at = (Get-Date -Format 'o')
                    })
                }

                # In Completed eintragen als final failed
                $State.completed_this_session += @([ordered]@{
                    issue_number = $IssueNumber
                    result       = "failed_escalated"
                    completed_at = (Get-Date -Format 'o')
                })
                Write-Host "[STATE] Issue #$IssueNumber endgueltig an User eskaliert." -ForegroundColor Red
            } else {
                $esc.status = "NEEDS_PLANNING"
                Write-Host "[STATE] Issue #$IssueNumber hat $($esc.monitoring_failures) Fehlversuche erreicht. Eskaliert an CEO für Re-Planning!" -ForegroundColor Red
            }
        }
    }

    Save-AutopilotState -State $State
}

# Vorce-Autopilot/src/lib/state-manager.ps1
# Zentrales State Management fuer den Vorce Autopilot
# Verwendet JSON Dateien in var/db/ zur Persistenz

Set-StrictMode -Version Latest

function Write-SafeJson {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][object]$Data
    )

    $dir = Split-Path $FilePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $Data | ConvertTo-Json -Depth 20 -Compress
    $tempFile = "$FilePath.tmp"
    $mutex = New-Object System.Threading.Mutex($false, "Global\VorceAutopilotStateMutex")
    try {
        $mutex.WaitOne() | Out-Null
        $json | Out-File -FilePath $tempFile -Encoding UTF8 -Force
        if (Test-Path $tempFile) {
            Move-Item -Path $tempFile -Destination $FilePath -Force
        }
    } catch {
        Write-Warning ("Fehler beim Schreiben von {0}: {1}" -f $FilePath, $_.Exception.Message)
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

function New-AutopilotState {
    return [pscustomobject]@{
        schema_version          = 2
        session_id              = "autopilot-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
        started_at              = (Get-Date -Format 'o')
        last_heartbeat          = (Get-Date -Format 'o')
        last_planning_at        = ""
        last_monitoring_at      = ""
        last_check_and_doing_at = ""
        active_delegations      = @()
        working_queue           = @()
        working_sessions        = @()
        review_queue            = @()
        autopilot_created_issues = @()
        completed_this_session  = @()
        decisions_pending       = @()
        deliberation_log        = @()
        optimizer_queue         = @()
        last_optimizer_analysis_at = ""
        optimizer_last_run      = $null
        run_control             = [pscustomobject]@{}
        escalated_issues        = @()
    }
}

function Read-AutopilotState {
    if ($null -eq (Get-Variable -Name "VorceAutopilotStateFilePath" -Scope Global -ErrorAction SilentlyContinue)) {
        $global:VorceAutopilotStateFilePath = Join-Path $PSScriptRoot "../../../var/db/active-sessions.json"
    }

    if (-not (Test-Path $global:VorceAutopilotStateFilePath)) {
        return $null
    }

    $mutex = New-Object System.Threading.Mutex($false, "Global\VorceAutopilotStateMutex")
    try {
        $mutex.WaitOne() | Out-Null
        $content = Get-Content -LiteralPath $global:VorceAutopilotStateFilePath -Raw -Encoding UTF8
        $state = $content | ConvertFrom-Json
        if ($null -ne $state) {
            $state = Update-AutopilotStateObject -State $state
        }
        return $state
    } catch {
        Write-Warning "Fehler beim Lesen der Autopilot-State-Datei: $_"
        return $null
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

function Save-AutopilotState {
    param([Parameter(Mandatory)][object]$State)

    if ($null -eq (Get-Variable -Name "VorceAutopilotStateFilePath" -Scope Global -ErrorAction SilentlyContinue)) {
        $global:VorceAutopilotStateFilePath = Join-Path $PSScriptRoot "../../../var/db/active-sessions.json"
    }

    $State.last_heartbeat = (Get-Date -Format 'o')
    Write-SafeJson -FilePath $global:VorceAutopilotStateFilePath -Data $State
}

function Update-AutopilotStateObject {
    param([Parameter(Mandatory)][object]$State)

    $defaults = New-AutopilotState
    foreach ($prop in $defaults.PSObject.Properties) {
        if (-not ($State.PSObject.Properties.Name -contains $prop.Name)) {
            $State | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
        }
    }

    # Validate that arrays are indeed arrays (sometimes deserialized as single object or null)
    foreach ($key in @("active_delegations", "working_queue", "working_sessions", "review_queue", "autopilot_created_issues", "completed_this_session", "decisions_pending", "deliberation_log", "optimizer_queue", "escalated_issues")) {
        if ($null -eq $State.$key) {
            $State.$key = @()
        } elseif ($State.$key -isnot [System.Array] -and $State.$key -isnot [System.Collections.IList]) {
            $State.$key = @($State.$key)
        }
    }

    return $State
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

function Initialize-AutopilotState {
    [CmdletBinding()]
    param([switch]$Force)

    # Run startup cleanup before anything else
    Invoke-StartupCleanup

    $existing = Read-AutopilotState
    $defaults = New-AutopilotState

    if ($null -eq $existing -or $Force) {
        Write-Host "[STATE] Initialisiere neuen State..." -ForegroundColor Gray
        Save-AutopilotState -State $defaults
        return $defaults
    }

    # Ensure all defaults are present in the existing state
    $existing = Update-AutopilotStateObject -State $existing

    # Schema Migration Check (1.0 -> 2.0)
    if (-not ($existing.PSObject.Properties.Name -contains "schema_version") -or $existing.schema_version -lt 2) {
        Write-Host "[STATE] Migriere State auf Schema V2..." -ForegroundColor Yellow
        $existing.schema_version = 2
        Save-AutopilotState -State $existing
    }

    return $existing
}

function Invoke-StartupCleanup {
    Write-Host "[INIT] Startup Cleanup wird ausgefuehrt..." -ForegroundColor DarkGray
    # Hier koennen temporaere Dateien oder Locks entfernt werden
    $ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
    $lockFile = Join-Path $ScriptDir "var/runtime/autopilot.lock"
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
}

function Add-DeliberationLog {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Protocol
    )

    if (-not ($State.PSObject.Properties.Name -contains "deliberation_log")) {
        $State | Add-Member -MemberType NoteProperty -Name "deliberation_log" -Value @()
    }

    $totalMs = ($Protocol.rounds | ForEach-Object { $_.duration_ms } | Measure-Object -Sum).Sum

    $entry = [ordered]@{
        deliberation_id   = $Protocol.deliberation_id
        task_type         = $Protocol.task_type
        ceo_provider      = $Protocol.ceo.provider
        qa_manager_provider = $Protocol.qa_manager.provider
        consensus_reached = $Protocol.consensus_reached
        phases_completed  = $Protocol.rounds.Count
        total_duration_ms = [int]$totalMs
        completed_at      = $Protocol.completed_at
        rounds            = $Protocol.rounds
    }

    $State.deliberation_log += @($entry)

    # Limit log size
    if ($State.deliberation_log.Count -gt 50) {
        $State.deliberation_log = $State.deliberation_log | Select-Object -Last 50
    }

    Save-AutopilotState -State $State
}

function Add-ErrorLog {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Message,
        [string]$Context
    )

    if (-not ($State.PSObject.Properties.Name -contains "error_log")) {
        $State | Add-Member -MemberType NoteProperty -Name "error_log" -Value @() -Force
    }

    $State.error_log += @([ordered]@{
        timestamp = (Get-Date -Format 'o')
        message   = $Message
        context   = $Context
    })

    # Limit log size
    if ($State.error_log.Count -gt 50) {
        $State.error_log = $State.error_log | Select-Object -Last 50
    }

    Save-AutopilotState -State $State
}

function Add-Delegation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$IssueTitle,
        [Parameter(Mandatory)][string]$JulesSessionId,
        [Parameter(Mandatory)][string]$AgentType,
        [string]$JobId = ""
    )

    if (-not ($State.PSObject.Properties.Name -contains "active_delegations")) {
        $State | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
    }

    $existing = @($State.active_delegations | Where-Object { [int]$_.issue_number -eq $IssueNumber })
    if ($existing.Count -gt 0) {
        Write-Host "[STATE] Delegation fuer Issue #$IssueNumber existiert bereits." -ForegroundColor DarkGray
        return
    }

    $State.active_delegations += @([ordered]@{
        issue_number     = $IssueNumber
        issue_title      = $IssueTitle
        jules_session_id = $JulesSessionId
        agent_type       = $AgentType
        job_id           = $JobId
        delegated_at     = (Get-Date -Format 'o')
    })

    Save-AutopilotState -State $State
}

function Update-DelegationState {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$JulesState
    )

    if (-not ($State.PSObject.Properties.Name -contains "active_delegations")) { return }

    $delegation = $State.active_delegations | Where-Object { [int]$_.issue_number -eq $IssueNumber } | Select-Object -First 1
    if ($delegation) {
        $delegation | Add-Member -MemberType NoteProperty -Name "jules_state" -Value $JulesState -Force
        Save-AutopilotState -State $State
    }
}

# Export-ModuleMember ist nur fuer .psm1 Module relevant.
# Bei dot-sourcing (. file.ps1) sind alle Funktionen automatisch sichtbar.
# Export-ModuleMember -Function Read-AutopilotState, Save-AutopilotState, Initialize-AutopilotState, Add-DeliberationLog, Update-AutopilotStateObject, Confirm-WorkingSessionsState, Add-ErrorLog, Add-Delegation, Update-DelegationState

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $false }
    return [bool]($Object.PSObject.Properties.Match($Name).Count -gt 0)
}

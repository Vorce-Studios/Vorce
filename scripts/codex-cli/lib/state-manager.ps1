# scripts/codex-cli/lib/state-manager.ps1
# Manages autopilot-state.json for crash recovery

Set-StrictMode -Version Latest

$script:CodexCliRoot = Split-Path -Parent $PSScriptRoot
$script:StateFilePath = Join-Path $script:CodexCliRoot "autopilot-state.json"

function Get-JsonMutexName {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        $hex = ([System.BitConverter]::ToString($hash)).Replace("-", "")
        return "Global\VorceJson_$($hex.Substring(0, 32))"
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-WithJsonMutex {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    $mutexName = Get-JsonMutexName -Path $Path
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $hasHandle = $false
    try {
        $hasHandle = $mutex.WaitOne([TimeSpan]::FromSeconds(15))
        if (-not $hasHandle) {
            throw "Timeout beim Warten auf JSON-Mutex: $Path"
        }
        & $ScriptBlock
    }
    finally {
        if ($hasHandle) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Read-JsonLocked {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    for ($i = 0; $i -lt 5; $i++) {
        $fileStream = $null
        $reader = $null
        try {
            if (-not (Test-Path $fullPath)) { return $null }
            $fileStream = [System.IO.File]::Open($fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $reader = New-Object System.IO.StreamReader($fileStream, [System.Text.Encoding]::UTF8)
                $content = $reader.ReadToEnd()
                if ([string]::IsNullOrWhiteSpace($content)) { return $null }
                return ($content | ConvertFrom-Json -ErrorAction Stop)
            }
            finally {
                if ($null -ne $reader) { $reader.Dispose() }
                if ($null -ne $fileStream) { $fileStream.Dispose() }
            }
        }
        catch {
            if (Test-Path $fullPath) {
                Write-Warning "Read-JsonLocked retry $($i+1): $($_.Exception.Message)"
                Start-Sleep -Milliseconds 200
            } else {
                return $null
            }
        }
    }
    return $null
}

function Read-JsonUnlocked {
    param([Parameter(Mandatory)][string]$Path)

    Read-JsonLocked -Path $Path
}

function Write-JsonLocked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Data
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parentDir = Split-Path -Parent $fullPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    for ($i = 0; $i -lt 10; $i++) {
        $tmpPath = Join-Path $parentDir ("{0}.{1}.tmp" -f (Split-Path -Leaf $fullPath), [Guid]::NewGuid().ToString("N"))
        try {
            $json = $Data | ConvertTo-Json -Depth 10
            Set-Content -Path $tmpPath -Value $json -Encoding UTF8 -ErrorAction Stop

            if (Test-Path $fullPath) {
                $backupPath = Join-Path $parentDir ("{0}.{1}.bak" -f (Split-Path -Leaf $fullPath), [Guid]::NewGuid().ToString("N"))
                [System.IO.File]::Replace($tmpPath, $fullPath, $backupPath, $true)
                if (Test-Path $backupPath) { Remove-Item $backupPath -Force -ErrorAction SilentlyContinue }
            } else {
                [System.IO.File]::Move($tmpPath, $fullPath)
            }
            return $true
        }
        catch {
            Write-Warning "Write-JsonLocked retry $($i+1): $($_.Exception.Message)"
            if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds (100 + (Get-Random -Minimum 1 -Maximum 200))
        }
    }
    return $false
}

function Update-JsonLocked {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$DefaultValue,
        [Parameter(Mandatory)][scriptblock]$Updater
    )

    Invoke-WithJsonMutex -Path $Path -ScriptBlock {
        $data = Read-JsonUnlocked -Path $Path
        if ($null -eq $data) { $data = $DefaultValue }
        $updated = & $Updater $data
        if ($null -eq $updated) { $updated = $data }
        Write-JsonLocked -Path $Path -Data $updated | Out-Null
        return $updated
    }
}

function Ensure-StateArrayProperty {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not ($State.PSObject.Properties.Name -contains $Name) -or $null -eq $State.$Name) {
        $State | Add-Member -MemberType NoteProperty -Name $Name -Value @() -Force
        return $true
    }

    $State.$Name = @($State.$Name)
    return $false
}

function Repair-AutopilotState {
    param([Parameter(Mandatory)][object]$State)

    $changed = $false
    foreach ($arrayProp in @("active_delegations", "active_pr_actions", "delegation_backlog", "review_queue", "autopilot_created_issues", "completed_this_session", "decisions_pending", "error_log", "jules_feedback_responses")) {
        if (Ensure-StateArrayProperty -State $State -Name $arrayProp) { $changed = $true }
    }

    if (-not ($State.PSObject.Properties.Name -contains "schema_version")) {
        $State | Add-Member -MemberType NoteProperty -Name "schema_version" -Value 1 -Force
        $changed = $true
    }

    if (-not ($State.PSObject.Properties.Name -contains "session_id") -or [string]::IsNullOrWhiteSpace([string]$State.session_id)) {
        $State | Add-Member -MemberType NoteProperty -Name "session_id" -Value "autopilot-$(Get-Date -Format 'yyyy-MM-dd-HHmm')" -Force
        $changed = $true
    }

    $validDelegations = @()
    foreach ($delegation in @($State.active_delegations)) {
        $issueNumber = 0
        [void][int]::TryParse([string]$delegation.issue_number, [ref]$issueNumber)
        $sessionId = [string]$delegation.jules_session_id
        if ($issueNumber -le 0 -or [string]::IsNullOrWhiteSpace($sessionId) -or $sessionId -like "dry-run-*") {
            $changed = $true
            continue
        }

        foreach ($prop in @(
            @{ Name = "issue_title"; Value = "" },
            @{ Name = "jules_state"; Value = "QUEUED" },
            @{ Name = "pr_url"; Value = $null },
            @{ Name = "delegated_at"; Value = (Get-Date -Format 'o') },
            @{ Name = "last_checked_at"; Value = (Get-Date -Format 'o') },
            @{ Name = "retry_count"; Value = 0 }
        )) {
            if (-not ($delegation.PSObject.Properties.Name -contains $prop.Name)) {
                $delegation | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
                $changed = $true
            }
        }
        $validDelegations += $delegation
    }
    $State.active_delegations = @($validDelegations)

    return $changed
}

function New-AutopilotState {
    return [ordered]@{
        schema_version          = 1
        session_id              = "autopilot-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
        started_at              = (Get-Date -Format 'o')
        last_heartbeat          = (Get-Date -Format 'o')
        last_planning_at        = $null
        last_monitoring_at      = $null
        active_delegations      = @()
        active_pr_actions       = @()
        delegation_backlog      = @()
        review_queue            = @()
        autopilot_created_issues = @()
        completed_this_session  = @()
        decisions_pending       = @()
        error_log               = @()
        jules_feedback_responses = @()
    }
}

function Read-AutopilotState {
    return Read-JsonLocked -Path $script:StateFilePath
}

function Save-AutopilotState {
    param([Parameter(Mandatory)][object]$State)

    $State.last_heartbeat = (Get-Date -Format 'o')
    Write-JsonLocked -Path $script:StateFilePath -Data $State | Out-Null
}

function Initialize-AutopilotState {
    [CmdletBinding()]
    param([switch]$Force)

    $existing = Read-AutopilotState
    if ($null -ne $existing -and -not $Force.IsPresent) {
        if (Repair-AutopilotState -State $existing) {
            Save-AutopilotState -State $existing
            Write-Host "[AUTOPILOT] State normalisiert (ungueltige/alte Eintraege bereinigt)." -ForegroundColor DarkGray
        }

        $lastBeat = [datetimeoffset]::MinValue
        $hasLastBeat = $false
        if ($existing.last_heartbeat) {
            if ($existing.last_heartbeat -is [datetimeoffset]) {
                $lastBeat = $existing.last_heartbeat
                $hasLastBeat = $true
            } elseif ($existing.last_heartbeat -is [datetime]) {
                $lastBeat = [datetimeoffset]::new([datetime]$existing.last_heartbeat)
                $hasLastBeat = $true
            } else {
                $hasLastBeat = [datetimeoffset]::TryParse([string]$existing.last_heartbeat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$lastBeat)
            }
        }

        $ago = if ($hasLastBeat) {
            $diff = (Get-Date) - $lastBeat.LocalDateTime
            "{0:N0} Minuten" -f $diff.TotalMinutes
        } else { "unbekannt" }

        Write-Host ""
        Write-Host "=====================================================" -ForegroundColor Yellow
        Write-Host "  VORCE AUTOPILOT - Recovery Mode" -ForegroundColor Yellow
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

function Add-Delegation {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$IssueTitle,
        [string]$JulesSessionId
    )

    $delegation = [ordered]@{
        issue_number     = $IssueNumber
        issue_title      = $IssueTitle
        jules_session_id = $JulesSessionId
        jules_state      = "QUEUED"
        pr_url           = $null
        delegated_at     = (Get-Date -Format 'o')
        last_checked_at  = (Get-Date -Format 'o')
        retry_count      = 0
    }

    $existing = @($State.active_delegations | Where-Object { [int]$_.issue_number -eq $IssueNumber } | Select-Object -First 1)
    if ($existing.Count -gt 0) {
        $existing[0].issue_title = $IssueTitle
        $existing[0].jules_session_id = $JulesSessionId
        $existing[0].jules_state = "QUEUED"
        $existing[0].last_checked_at = (Get-Date -Format 'o')
    } else {
        $State.active_delegations += @($delegation)
    }
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
        [int]$PrNumber
    )

    $existing = @($State.review_queue | Where-Object {
        ([int]$_.issue_number -eq $IssueNumber) -or ($PrNumber -gt 0 -and [int]$_.pr_number -eq $PrNumber)
    } | Select-Object -First 1)

    if ($existing.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace($PrUrl)) { $existing[0].pr_url = $PrUrl }
        if ($PrNumber -gt 0) { $existing[0].pr_number = $PrNumber }
        $existing[0].review_status = "pending"
        Save-AutopilotState -State $State
        return
    }

    $State.review_queue += @([ordered]@{
        issue_number  = $IssueNumber
        pr_url        = $PrUrl
        pr_number     = $PrNumber
        review_status = "pending"
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

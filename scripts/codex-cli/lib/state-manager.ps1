# scripts/codex-cli/lib/state-manager.ps1
# Manages autopilot-state.json for crash recovery

Set-StrictMode -Version Latest

$script:StateFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "autopilot-state.json"

function New-AutopilotState {
    return [ordered]@{
        schema_version          = 1
        session_id              = "autopilot-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
        started_at              = (Get-Date -Format 'o')
        last_heartbeat          = (Get-Date -Format 'o')
        last_planning_at        = $null
        last_monitoring_at      = $null
        active_delegations      = @()
        review_queue            = @()
        autopilot_created_issues = @()
        completed_this_session  = @()
        decisions_pending       = @()
        error_log               = @()
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
    $State | ConvertTo-Json -Depth 10 | Set-Content $script:StateFilePath -Encoding UTF8
}

function Initialize-AutopilotState {
    [CmdletBinding()]
    param([switch]$Force)

    $existing = Read-AutopilotState
    if ($null -ne $existing -and -not $Force.IsPresent) {
        $lastBeat = if ($existing.last_heartbeat) {
            [datetimeoffset]::Parse($existing.last_heartbeat)
        } else { $null }

        $ago = if ($lastBeat) {
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
        [int]$PrNumber
    )

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

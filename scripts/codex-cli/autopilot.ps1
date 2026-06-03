# scripts/codex-cli/autopilot.ps1
# Vorce Autopilot - AI CEO Orchestrator
# Main entry point with timer-based wake-up loop

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnce,
    [switch]$MonitorOnce,
    [int]$PlanningIntervalOverride,
    [int]$MonitoringIntervalOverride
)

Set-StrictMode -Version Latest
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $PSCommandPath

# --- Load libraries ---
. (Join-Path $ScriptDir "lib\state-manager.ps1")
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")
. (Join-Path $ScriptDir "phases\planning-wakeup.ps1")
. (Join-Path $ScriptDir "phases\monitoring-wakeup.ps1")

# --- Load config ---
$configPath = Join-Path $ScriptDir "autopilot-config.json"
if (-not (Test-Path $configPath)) {
    throw "autopilot-config.json nicht gefunden: $configPath"
}
$Config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

# --- Intervals ---
$planMinutes = if ($PlanningIntervalOverride -gt 0) { $PlanningIntervalOverride } else { $Config.wake_intervals.planning_minutes }
$monMinutes = if ($MonitoringIntervalOverride -gt 0) { $MonitoringIntervalOverride } else { $Config.wake_intervals.monitoring_minutes }

# --- Banner ---
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  VORCE AUTOPILOT - AI CEO Orchestrator" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
$planStr = $planMinutes.ToString().PadLeft(4)
$monStr = $monMinutes.ToString().PadLeft(4)
Write-Host "  Planning Interval:   $planStr min" -ForegroundColor Cyan
Write-Host "  Monitoring Interval: $monStr min" -ForegroundColor Cyan
if ($DryRun.IsPresent) {
    Write-Host "  Mode: DRY RUN (keine echten API-Calls)" -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# --- Initialize state ---
$State = Initialize-AutopilotState
$QuotaRegistry = Read-QuotaRegistry

function Ensure-RunControl {
    param([Parameter(Mandatory)][object]$State)
    if (-not ($State.PSObject.Properties.Name -contains "run_control") -or $null -eq $State.run_control) {
        $State | Add-Member -MemberType NoteProperty -Name "run_control" -Value ([PSCustomObject]@{
            cancel_next_planning   = $false
            cancel_next_monitoring = $false
            next_planning_note     = ""
            next_monitoring_note   = ""
            updated_at             = $null
        }) -Force
    }
}

function Get-RunControlNote {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][ValidateSet("planning", "monitoring")][string]$RunType
    )
    Ensure-RunControl -State $State
    if ($RunType -eq "planning") { return [string]$State.run_control.next_planning_note }
    return [string]$State.run_control.next_monitoring_note
}

# --- Single-shot modes ---
if ($PlanOnce.IsPresent) {
    Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

if ($MonitorOnce.IsPresent) {
    Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

# --- Main loop ---
$lastPlanTime = if ($State.last_planning_at) {
    [datetimeoffset]::Parse($State.last_planning_at).LocalDateTime
} else {
    [datetime]::MinValue
}

$lastMonTime = if ($State.last_monitoring_at) {
    [datetimeoffset]::Parse($State.last_monitoring_at).LocalDateTime
} else {
    [datetime]::MinValue
}

Write-Host "[LOOP] Starte Hauptschleife. Ctrl+C zum Beenden." -ForegroundColor Green
Write-Host ""

while ($true) {
    $now = Get-Date
    $QuotaRegistry = Read-QuotaRegistry

    $planDue = ($now - $lastPlanTime).TotalMinutes -ge $planMinutes
    $monDue = ($now - $lastMonTime).TotalMinutes -ge $monMinutes

    if ($planDue) {
        Ensure-RunControl -State $State
        if ($State.run_control.cancel_next_planning -eq $true) {
            Write-Host "[LOOP] Naechster Planning-Run wurde via Dashboard gecancelt." -ForegroundColor Yellow
            $State.run_control.cancel_next_planning = $false
            $State.run_control.updated_at = (Get-Date -Format 'o')
            $lastPlanTime = Get-Date
            $State.last_planning_at = $lastPlanTime.ToString('o')
            Save-AutopilotState -State $State
        } else {
            $planningNote = Get-RunControlNote -State $State -RunType "planning"
            if (-not [string]::IsNullOrWhiteSpace($planningNote)) {
                Write-Host "[LOOP] Info fuer kommenden Planning-Run: $planningNote" -ForegroundColor Cyan
            }
        try {
            Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastPlanTime = Get-Date
            if (-not [string]::IsNullOrWhiteSpace($planningNote)) {
                $State.run_control.next_planning_note = ""
                $State.run_control.updated_at = (Get-Date -Format 'o')
            }
        } catch {
            Write-Host "[LOOP] Planning-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Planning wake-up failed" -Context $_.Exception.Message
        }

        # Planning hat Prioritaet: Wenn beide gleichzeitig faellig waren,
        # wird Monitoring auf den naechsten Zyklus verschoben.
        if ($monDue) {
            Write-Host "[LOOP] Monitoring verschoben - Planning hat Prioritaet." -ForegroundColor DarkGray
            $monDue = $false
        }

        # Asynchroner Audit-Lauf durch CEO Beta direkt nach dem Planning
        try {
            Invoke-AuditWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        } catch {
            Write-Host "[LOOP] Audit-Fehler: $_" -ForegroundColor Red
        }
    }

    if ($monDue) {
        Ensure-RunControl -State $State
        if ($State.run_control.cancel_next_monitoring -eq $true) {
            Write-Host "[LOOP] Naechster Monitoring-Run wurde via Dashboard gecancelt." -ForegroundColor Yellow
            $State.run_control.cancel_next_monitoring = $false
            $State.run_control.updated_at = (Get-Date -Format 'o')
            $lastMonTime = Get-Date
            $State.last_monitoring_at = $lastMonTime.ToString('o')
            Save-AutopilotState -State $State
        } else {
            $monitoringNote = Get-RunControlNote -State $State -RunType "monitoring"
            if (-not [string]::IsNullOrWhiteSpace($monitoringNote)) {
                Write-Host "[LOOP] Info fuer kommenden Monitoring-Run: $monitoringNote" -ForegroundColor Cyan
            }
        try {
            Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastMonTime = Get-Date
            if (-not [string]::IsNullOrWhiteSpace($monitoringNote)) {
                $State.run_control.next_monitoring_note = ""
                $State.run_control.updated_at = (Get-Date -Format 'o')
            }
        } catch {
            Write-Host "[LOOP] Monitoring-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Monitoring wake-up failed" -Context $_.Exception.Message
        }
        }
    }

    # --- Status report ---
    $timeStr = $now.ToString("HH:mm:ss")
    $delegCount = $State.active_delegations.Count
    $reviewCount = $State.review_queue.Count
    $doneCount = $State.completed_this_session.Count
    $decCount = $State.decisions_pending.Count

    Write-Host ""
    Write-Host "[$timeStr] Status: Delegiert=$delegCount Review=$reviewCount Fertig=$doneCount Entscheidungen=$decCount" -ForegroundColor DarkGray

    if ($decCount -gt 0) {
        Write-Host ""
        Write-Host "  [!] ENTSCHEIDUNGEN OFFEN:" -ForegroundColor Yellow
        foreach ($d in $State.decisions_pending) {
            $topic = $d.topic
            Write-Host "    -> $topic" -ForegroundColor Yellow
        }
    }

    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray

    # --- Calculate next wake-up ---
    $nextPlan = $lastPlanTime.AddMinutes($planMinutes)
    $nextMon = $lastMonTime.AddMinutes($monMinutes)
    $nextWake = @($nextPlan, $nextMon) | Sort-Object | Select-Object -First 1
    $sleepSeconds = [Math]::Max(10, ($nextWake - (Get-Date)).TotalSeconds)

    if ($nextWake -eq $nextPlan) { $nextType = "Planning" } else { $nextType = "Monitoring" }
    $sleepMin = [Math]::Round($sleepSeconds / 60, 1)
    $nextTimeStr = $nextWake.ToString("HH:mm:ss")
    $loopMsg = "[LOOP] Naechster Wake-Up ({0}): {1} (in {2} min)" -f $nextType, $nextTimeStr, $sleepMin
    Write-Host $loopMsg -ForegroundColor DarkGray
    Write-Host ""

    Save-AutopilotState -State $State
    Start-Sleep -Seconds $sleepSeconds
}

# scripts/codex-cli/autopilot.ps1
# Vorce Autopilot - AI CEO Orchestrator
# Main entry point with timer-based wake-up loop

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnce,
    [switch]$MonitorOnce,
    [switch]$ForcePlanningOnStart,
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
. (Join-Path $ScriptDir "lib\memory-store.ps1")
. (Join-Path $ScriptDir "lib\deliberation-engine.ps1")
. (Join-Path $ScriptDir "lib\autopilot-session-manager.ps1")
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

# --- Initialize state (includes startup cleanup) ---
$State = Initialize-AutopilotState
$QuotaRegistry = Read-QuotaRegistry

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
$lastPlanTime = [datetime]::MinValue
if (-not $ForcePlanningOnStart.IsPresent -and $State.last_planning_at) {
    try {
        $lastPlanTime = [datetimeoffset]::Parse($State.last_planning_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
    } catch {
        Write-Warning "[INIT] Konnte last_planning_at nicht parsen: $_"
    }
}

$lastMonTime = [datetime]::MinValue
if ($State.last_monitoring_at) {
    try {
        $lastMonTime = [datetimeoffset]::Parse($State.last_monitoring_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
    } catch {
        Write-Warning "[INIT] Konnte last_monitoring_at nicht parsen: $_"
    }
}

# Track cleanup cycles (clean every 10th loop iteration)
$loopCount = 0
$cleanupEveryN = 10

Write-Host "[LOOP] Starte Hauptschleife. Ctrl+C zum Beenden." -ForegroundColor Green
Write-Host ""

while ($true) {
    $now = Get-Date
    $QuotaRegistry = Read-QuotaRegistry

    $planDue = ($now - $lastPlanTime).TotalMinutes -ge $planMinutes
    $monDue = ($now - $lastMonTime).TotalMinutes -ge $monMinutes

    if ($planDue) {
        try {
            Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastPlanTime = Get-Date
        } catch {
            Write-Host "[LOOP] Planning-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Planning wake-up failed" -Context $_.Exception.Message
        }
    }

    if ($monDue) {
        try {
            Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastMonTime = Get-Date
        } catch {
            Write-Host "[LOOP] Monitoring-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Monitoring wake-up failed" -Context $_.Exception.Message
        }
    }

    # --- Periodic TMP cleanup ---
    $loopCount++
    if ($loopCount % $cleanupEveryN -eq 0) {
        $dashboardPublic = Join-Path $ScriptDir "dashboard" "public"
        Remove-OrphanedTmpFiles -Directory $ScriptDir -OlderThanMinutes 5
        if (Test-Path $dashboardPublic) {
            Remove-OrphanedTmpFiles -Directory $dashboardPublic -OlderThanMinutes 5
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

    $nextPlan = if ($lastPlanTime -eq [datetime]::MinValue) { (Get-Date).AddMinutes($planMinutes) } else { $lastPlanTime.AddMinutes($planMinutes) }
    $nextMon = if ($lastMonTime -eq [datetime]::MinValue) { (Get-Date).AddMinutes($monMinutes) } else { $lastMonTime.AddMinutes($monMinutes) }
    $nextWake = @($nextPlan, $nextMon) | Sort-Object | Select-Object -First 1
    $sleepSeconds = [Math]::Max(10, [double]($nextWake - (Get-Date)).TotalSeconds)

    if ($nextWake -eq $nextPlan) { $nextType = "Planning" } else { $nextType = "Monitoring" }
    $sleepMin = [Math]::Round($sleepSeconds / 60, 1)
    $nextTimeStr = $nextWake.ToString("HH:mm:ss")
    $loopMsg = "[LOOP] Naechster Wake-Up ({0}): {1} (in {2} min)" -f $nextType, $nextTimeStr, $sleepMin
    Write-Host $loopMsg -ForegroundColor DarkGray
    Write-Host ""

    Save-AutopilotState -State $State
    $remainingSleep = [Math]::Max(1, [int]$sleepSeconds)
    while ($remainingSleep -gt 0) {
        Start-Sleep -Seconds 1
        $remainingSleep--
    }
}

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

# Set-StrictMode -Version Latest
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $PSCommandPath

# --- Load libraries ---
. (Join-Path $ScriptDir "lib\state-manager.ps1")
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")
. (Join-Path $ScriptDir "lib\autopilot-prompts.ps1")
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

# --- Initialize state ---
$State = Initialize-AutopilotState
$QuotaRegistry = Read-QuotaRegistry

# --- Single-shot modes ---
if ($PlanOnce.IsPresent) {
    $planningPrompt = Get-VorceCodexPlanningSessionPrompt -Repository ([string]$Config.repository) -TaskJournalPath (Get-AutopilotTaskJournalPath) -SessionLockPath (Get-AutopilotSessionLockPath)
    Invoke-AutopilotCodexSession -SessionType "planning" -Prompt $planningPrompt -State $State -Model "gpt-5.5" -ResumeMainSession -VisibleTerminal -DryRun:$DryRun | Out-Null
    Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

if ($MonitorOnce.IsPresent) {
    $monitoringPrompt = Get-VorceCodexMonitoringSessionPrompt -Repository ([string]$Config.repository) -TaskJournalPath (Get-AutopilotTaskJournalPath) -SessionLockPath (Get-AutopilotSessionLockPath)
    Invoke-AutopilotCodexSession -SessionType "monitoring" -Prompt $monitoringPrompt -State $State -Model "gpt-5.4-mini" -DryRun:$DryRun | Out-Null
    Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

# --- Main loop ---
# Robustly parse last activity times
[datetime]$lastPlanTime = [datetime]::MinValue
if ($State.last_planning_at) {
    try { $lastPlanTime = [datetimeoffset]::Parse($State.last_planning_at).LocalDateTime } catch { }
}
if ($ForcePlanningOnStart.IsPresent) {
    Write-Host "[LOOP] ForcePlanningOnStart aktiv: sichtbare Planning-Session wird beim Start erzwungen." -ForegroundColor Yellow
    Add-AutopilotJournalEvent -SessionType "planning" -Message "ForcePlanningOnStart active; forcing visible planning session on loop start."
    $lastPlanTime = [datetime]::MinValue
}

[datetime]$lastMonTime = [datetime]::MinValue
if ($State.last_monitoring_at) {
    try { $lastMonTime = [datetimeoffset]::Parse($State.last_monitoring_at).LocalDateTime } catch { }
}

Write-Host "[LOOP] Starte Hauptschleife. Ctrl+C zum Beenden." -ForegroundColor Green
Write-Host ""

while ($true) {
    $now = Get-Date
    $QuotaRegistry = Read-QuotaRegistry
    $planningRanThisCycle = $false

    # Ensure lastPlanTime and lastMonTime are always valid DateTimes
    if ($null -eq $lastPlanTime) { $lastPlanTime = [datetime]::MinValue }
    if ($null -eq $lastMonTime) { $lastMonTime = [datetime]::MinValue }

    $planDue = ($now - $lastPlanTime).TotalMinutes -ge $planMinutes
    $monDue = ($now - $lastMonTime).TotalMinutes -ge $monMinutes

    if ($planDue) {
        try {
            Write-Host "[LOOP] Starte Planning-Zyklus: sichtbare Codex-Planning-Session wird geoeffnet." -ForegroundColor Green
            $planningPrompt = Get-VorceCodexPlanningSessionPrompt -Repository ([string]$Config.repository) -TaskJournalPath (Get-AutopilotTaskJournalPath) -SessionLockPath (Get-AutopilotSessionLockPath)
            Invoke-AutopilotCodexSession -SessionType "planning" -Prompt $planningPrompt -State $State -Model "gpt-5.5" -ResumeMainSession -VisibleTerminal -DryRun:$DryRun | Out-Null
            Write-Host "[LOOP] Codex-Planning beendet. Starte deterministischen Planning-Wake-Up." -ForegroundColor Green
            Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastPlanTime = Get-Date
            $lastMonTime = $lastPlanTime
            $monDue = $false
            $planningRanThisCycle = $true
            Write-Host "[LOOP] Monitoring-Intervall startet nach Planning-Ende neu: $($lastMonTime.ToString('HH:mm:ss'))" -ForegroundColor DarkGray
        } catch {
            Write-Host "[LOOP] Planning-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Planning wake-up failed" -Context $_.Exception.Message
        }
    }

    if ($monDue -and -not $planningRanThisCycle) {
        try {
            Write-Host "[LOOP] Starte Monitoring-Zyklus: headless Codex-Monitoring plus deterministische Checks." -ForegroundColor Green
            $monitoringPrompt = Get-VorceCodexMonitoringSessionPrompt -Repository ([string]$Config.repository) -TaskJournalPath (Get-AutopilotTaskJournalPath) -SessionLockPath (Get-AutopilotSessionLockPath)
            Invoke-AutopilotCodexSession -SessionType "monitoring" -Prompt $monitoringPrompt -State $State -Model "gpt-5.4-mini" -VisibleExecTerminal -DryRun:$DryRun | Out-Null
            Write-Host "[LOOP] Codex-Monitoring beendet. Starte deterministischen Monitoring-Wake-Up." -ForegroundColor Green
            Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastMonTime = Get-Date
        } catch {
            Write-Host "[LOOP] Monitoring-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Monitoring wake-up failed" -Context $_.Exception.Message
        }
    }

    # --- Status report ---
    $timeStr = $now.ToString("HH:mm:ss")
    $delegCount = if ($State.active_delegations) { $State.active_delegations.Count } else { 0 }
    $reviewCount = if ($State.review_queue) { $State.review_queue.Count } else { 0 }
    $doneCount = if ($State.completed_this_session) { $State.completed_this_session.Count } else { 0 }
    $decCount = if ($State.decisions_pending) { $State.decisions_pending.Count } else { 0 }

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

    # Defaults to 60 seconds if something goes wrong with date math
    $sleepSeconds = 60
    try {
        $diff = ($nextWake - (Get-Date)).TotalSeconds
        $sleepSeconds = [Math]::Max(10, $diff)
    } catch { }

    $nextType = if ($nextWake -eq $nextPlan) { "Planning" } else { "Monitoring" }
    $sleepMin = [Math]::Round($sleepSeconds / 60, 1)
    $nextTimeStr = $nextWake.ToString("HH:mm:ss")
    $loopMsg = "[LOOP] Naechster Wake-Up ({0}): {1} (in {2} min)" -f $nextType, $nextTimeStr, $sleepMin
    Write-Host $loopMsg -ForegroundColor DarkGray
    Write-Host ""

    Save-AutopilotState -State $State

    # --- Responsive Sleep ---
    $wakeupFile = Join-Path $ScriptDir "autopilot.wakeup"
    $remainingSleep = $sleepSeconds
    $step = 10

    while ($remainingSleep -gt 0) {
        if (Test-Path $wakeupFile) {
            Write-Host "[LOOP] Wake-up Trigger gefunden. Breche Sleep ab." -ForegroundColor Yellow
            try { Remove-Item $wakeupFile -ErrorAction SilentlyContinue } catch {}
            break
        }

        $currentStep = [Math]::Min($step, $remainingSleep)
        Start-Sleep -Seconds $currentStep
        $remainingSleep -= $currentStep
    }
}

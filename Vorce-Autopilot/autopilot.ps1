# Vorce-Autopilot/autopilot.ps1
# Vorce Autopilot - AI CEO Orchestrator
# Main entry point with timer-based wake-up loop

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnce,
    [switch]$MonitorOnce,
    [switch]$SkipPlanningOnStart,
    [int]$PlanningIntervalOverride,
    [int]$MonitoringIntervalOverride
)

Set-StrictMode -Version Latest
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$script:VarLogDir = Join-Path $ScriptDir "var/log"
$script:VarDbDir = Join-Path $ScriptDir "var/db"
$script:AutopilotLiveLogPath = Join-Path $script:VarLogDir "autopilot-live.log"
$script:AutopilotMainLockPath = Join-Path $script:VarDbDir "autopilot-main-lock.json"
$global:VorceAutopilotLiveLogPath = $script:AutopilotLiveLogPath

# Ensure directories exist
if (-not (Test-Path -Path $script:VarLogDir)) {
    New-Item -ItemType Directory -Path $script:VarLogDir -Force | Out-Null
}
if (-not (Test-Path -Path $script:VarDbDir)) {
    New-Item -ItemType Directory -Path $script:VarDbDir -Force | Out-Null
}

# Custom Write-Host to pipe logs to var/log/autopilot-live.log in real time
function Write-Host {
    param(
        [Parameter(ValueFromPipeline, Position=0)][object]$Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewLine
    )

    $params = @{}
    if ($Object) { $params["Object"] = $Object }
    if ($ForegroundColor) { $params["ForegroundColor"] = $ForegroundColor }
    if ($BackgroundColor) { $params["BackgroundColor"] = $BackgroundColor }
    if ($NoNewLine) { $params["NoNewLine"] = $true }

    Microsoft.PowerShell.Utility\Write-Host @params

    if ($Object) {
        $liveLogPath = $null
        $globalLiveLogPath = Get-Variable -Name "VorceAutopilotLiveLogPath" -Scope Global -ErrorAction SilentlyContinue
        if ($null -ne $globalLiveLogPath -and -not [string]::IsNullOrWhiteSpace([string]$globalLiveLogPath.Value)) {
            $liveLogPath = [string]$globalLiveLogPath.Value
        } elseif ($null -ne (Get-Variable -Name "AutopilotLiveLogPath" -Scope Script -ErrorAction SilentlyContinue)) {
            $liveLogPath = [string]$script:AutopilotLiveLogPath
        } elseif ($null -ne (Get-Variable -Name "VarLogDir" -Scope Script -ErrorAction SilentlyContinue)) {
            $liveLogPath = Join-Path $script:VarLogDir "autopilot-live.log"
        }

        if ([string]::IsNullOrWhiteSpace($liveLogPath)) {
            return
        }

        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        try {
            $cleanMsg = $Object.ToString() -replace '\e\[[0-9;]*m', ''
            Add-Content -Path $liveLogPath -Value "[$timestamp] $cleanMsg" -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Get-AutopilotRunMode {
    if ($PlanOnce.IsPresent) { return "plan-once" }
    if ($MonitorOnce.IsPresent) { return "monitor-once" }
    return "loop"
}

function Read-AutopilotMainRunLock {
    if (-not (Test-Path -LiteralPath $script:AutopilotMainLockPath)) { return $null }
    try {
        return Get-Content -LiteralPath $script:AutopilotMainLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-AutopilotMainRunLockActive {
    param([object]$Lock)

    if ($null -eq $Lock) { return $false }
    if (-not ($Lock.PSObject.Properties.Name -contains "pid")) { return $false }

    $lockPid = 0
    if (-not [int]::TryParse([string]$Lock.pid, [ref]$lockPid) -or $lockPid -le 0) { return $false }

    $process = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }

    if ($Lock.PSObject.Properties.Name -contains "started_at") {
        try {
            $lockStarted = [datetimeoffset]::Parse([string]$Lock.started_at).LocalDateTime
            if ($process.StartTime -gt $lockStarted.AddMinutes(1)) { return $false }
        } catch {}
    }

    return $true
}

function Register-AutopilotMainRunLock {
    param([Parameter(Mandatory)][string]$Mode)

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $existingLock = Read-AutopilotMainRunLock
        if (Test-AutopilotMainRunLockActive -Lock $existingLock) {
            $existingMode = if ($existingLock.PSObject.Properties.Name -contains "mode") { [string]$existingLock.mode } else { "unknown" }
            $existingPid = [string]$existingLock.pid
            throw "Autopilot laeuft bereits (PID=$existingPid, Mode=$existingMode). Zweite Instanz blockiert, damit Planning/Monitoring nicht parallel laufen."
        }

        if (Test-Path -LiteralPath $script:AutopilotMainLockPath) {
            Remove-Item -LiteralPath $script:AutopilotMainLockPath -Force -ErrorAction SilentlyContinue
        }

        $now = Get-Date
        $lockJson = [pscustomobject]@{
            pid               = $PID
            mode              = $Mode
            phase             = "starting"
            started_at        = $now.ToString("o")
            last_heartbeat_at = $now.ToString("o")
            script_path       = $PSCommandPath
        } | ConvertTo-Json -Depth 4

        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($lockJson)
            $stream = [System.IO.File]::Open($script:AutopilotMainLockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }
            return
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 150
            continue
        }
    }

    $existingLock = Read-AutopilotMainRunLock
    $existingMode = if ($null -ne $existingLock -and $existingLock.PSObject.Properties.Name -contains "mode") { [string]$existingLock.mode } else { "unknown" }
    $existingPid = if ($null -ne $existingLock -and $existingLock.PSObject.Properties.Name -contains "pid") { [string]$existingLock.pid } else { "unknown" }
    throw "Autopilot-Run-Lock konnte nicht exklusiv erstellt werden (aktueller Lock: PID=$existingPid, Mode=$existingMode)."
}

function Update-AutopilotMainRunLock {
    param([Parameter(Mandatory)][string]$Phase)

    $lock = Read-AutopilotMainRunLock
    if ($null -eq $lock) { return }
    if (-not ($lock.PSObject.Properties.Name -contains "pid") -or [string]$lock.pid -ne [string]$PID) { return }

    $lock.phase = $Phase
    $lock.last_heartbeat_at = (Get-Date).ToString("o")
    $lock | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:AutopilotMainLockPath -Encoding UTF8
}

function Clear-AutopilotMainRunLock {
    $lock = Read-AutopilotMainRunLock
    if ($null -eq $lock) { return }
    if (($lock.PSObject.Properties.Name -contains "pid") -and [string]$lock.pid -eq [string]$PID) {
        Remove-Item -LiteralPath $script:AutopilotMainLockPath -Force -ErrorAction SilentlyContinue
    }
}

$script:AutopilotRunMode = Get-AutopilotRunMode
Register-AutopilotMainRunLock -Mode $script:AutopilotRunMode

# --- Load libraries ---
. (Join-Path $ScriptDir "src/lib/state-manager.ps1")
. (Join-Path $ScriptDir "src/lib/quota-manager.ps1")
. (Join-Path $ScriptDir "src/lib/cli-router.ps1")
. (Join-Path $ScriptDir "src/lib/memory-store.ps1")
. (Join-Path $ScriptDir "src/lib/deliberation-engine.ps1")
. (Join-Path $ScriptDir "src/lib/autopilot-session-manager.ps1")
. (Join-Path $ScriptDir "src/lib/autopilot-prompts.ps1")
. (Join-Path $ScriptDir "src/lib/github-client.ps1")
. (Join-Path $ScriptDir "src/lib/jules-client.ps1")
. (Join-Path $ScriptDir "src/phases/planning-wakeup.ps1")
. (Join-Path $ScriptDir "src/phases/monitoring-wakeup.ps1")
. (Join-Path $ScriptDir "src/phases/audit-wakeup.ps1")

# Dummy command/placeholder for backward compatibility check
function Get-VorceLagebildSummary {
    return "Dummy Lagebild"
}
function Invoke-RuntimeFileRetention {
    return $true
}

$requiredAutopilotCommands = @(
    "Get-VorceConfigPrompt",
    "Confirm-WorkingSessionsState",
    "Optimize-AutopilotMemories",
    "Invoke-PlanningWakeUp",
    "Invoke-MonitoringWakeUp",
    "Invoke-AuditWakeUp"
)

$missingAutopilotCommands = @($requiredAutopilotCommands | Where-Object {
    -not (Get-Command $_ -ErrorAction SilentlyContinue)
})
if ($missingAutopilotCommands.Count -gt 0) {
    throw "Autopilot startup guard failed. Missing commands: $($missingAutopilotCommands -join ', ')"
}

# --- Load config ---
$configPath = Join-Path $ScriptDir "config/autopilot-config.json"
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
Write-Host "  VORCE AUTOPILOT - AI CEO Orchestrator (Optimized)" -ForegroundColor Cyan
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
    try {
        Update-AutopilotMainRunLock -Phase "planning"
        Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        $summary = Get-QuotaSummary -Registry $QuotaRegistry
        Write-Host $summary -ForegroundColor DarkGray
    } finally {
        Clear-AutopilotMainRunLock
    }
    return
}

if ($MonitorOnce.IsPresent) {
    try {
        Update-AutopilotMainRunLock -Phase "monitoring"
        Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        $summary = Get-QuotaSummary -Registry $QuotaRegistry
        Write-Host $summary -ForegroundColor DarkGray
    } finally {
        Clear-AutopilotMainRunLock
    }
    return
}

# --- Main loop ---
$lastPlanTime = [datetime]::MinValue
$lastMonTime = [datetime]::MinValue

if (-not $SkipPlanningOnStart.IsPresent) {
    # Default: Force planning on start.
    $lastMonTime = Get-Date

    # Synchronisiere State direkt beim Start
    $State.last_monitoring_at = $lastMonTime.ToString('o')
    $State.last_planning_at = (Get-Date).AddDays(-1).ToString('o')
    Save-AutopilotState -State $State

    Write-Host "[INIT] Starte mit erzwungener Planungs-Phase (SkipPlanningOnStart ist nicht aktiv)." -ForegroundColor Yellow
} else {
    Write-Host "[INIT] SkipPlanningOnStart aktiv: Verwende Zeitstempel aus dem State-Speicher." -ForegroundColor Yellow
    if ($State.last_planning_at) {
        try {
            $lastPlanTime = [datetimeoffset]::Parse($State.last_planning_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
        } catch {
            Write-Warning "[INIT] Konnte last_planning_at nicht parsen: $_"
        }
    }
    if ($State.last_monitoring_at) {
        try {
            $lastMonTime = [datetimeoffset]::Parse($State.last_monitoring_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
        } catch {
            Write-Warning "[INIT] Konnte last_monitoring_at nicht parsen: $_"
        }
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

    if (-not (Test-PrimaryProvidersAvailable -Registry $QuotaRegistry)) {
        Write-Host ""
        Write-Host "==========================================================================" -ForegroundColor Red
        Write-Host "  [QUOTA LIMIT] Beide Primaer-Anbieter (Codex & Gemini) sind nicht verfuegbar!" -ForegroundColor Red
        Write-Host "  Automatische Pause von 60 Minuten vor dem naechsten Versuch..." -ForegroundColor Yellow
        Write-Host "==========================================================================" -ForegroundColor Red
        Write-Host ""

        $pauseSeconds = 3600
        $pauseUntil = (Get-Date).AddSeconds($pauseSeconds)
        Write-Host "[LOOP] Pause bis $($pauseUntil.ToString('HH:mm:ss')) (in 60.0 min)..." -ForegroundColor Yellow

        $remainingPause = $pauseSeconds
        while ($remainingPause -gt 0) {
            Start-Sleep -Seconds 10
            $remainingPause -= 10
        }
        continue
    }

    $planDue = ($now - $lastPlanTime).TotalMinutes -ge $planMinutes
    $monDue = ($now - $lastMonTime).TotalMinutes -ge $monMinutes

    if ($planDue) {
        try {
            Update-AutopilotMainRunLock -Phase "planning"
            Invoke-PlanningWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastPlanTime = Get-Date
        } catch {
            Write-Host "[LOOP] Planning-Fehler: $_" -ForegroundColor Red
            Write-Host "[LOOP] StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Planning wake-up failed" -Context $_.Exception.Message
            $lastPlanTime = Get-Date
            $State.last_planning_at = $lastPlanTime.ToString('o')
            Save-AutopilotState -State $State
            Write-Host "[LOOP] Planning fehlgeschlagen; naechster Planning-Versuch erst nach $planMinutes min." -ForegroundColor Yellow
        }

        # Planning hat Prioritaet
        if ($monDue) {
            Write-Host "[LOOP] Monitoring verschoben - Planning hat Prioritaet." -ForegroundColor DarkGray
            $monDue = $false
        }

        # Asynchroner Audit-Lauf durch den QA Manager direkt nach dem Planning
        try {
            Update-AutopilotMainRunLock -Phase "audit"
            Invoke-AuditWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        } catch {
            Write-Host "[LOOP] Audit-Fehler: $_" -ForegroundColor Red
        }
    }

    if ($monDue) {
        try {
            Update-AutopilotMainRunLock -Phase "monitoring"
            Invoke-MonitoringWakeUp -State $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $lastMonTime = Get-Date
        } catch {
            Write-Host "[LOOP] Monitoring-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Monitoring wake-up failed" -Context $_.Exception.Message
            $lastMonTime = Get-Date
            $State.last_monitoring_at = $lastMonTime.ToString('o')
            Save-AutopilotState -State $State
            Write-Host "[LOOP] Monitoring fehlgeschlagen; naechster Monitoring-Versuch erst nach $monMinutes min." -ForegroundColor Yellow
        }
    }

    # --- Periodic TMP cleanup ---
    $loopCount++
    if ($loopCount % $cleanupEveryN -eq 0) {
        Remove-OrphanedTmpFiles -Directory $ScriptDir -OlderThanMinutes 5
        # Clean var/log / var/db TMP files too
        Remove-OrphanedTmpFiles -Directory $script:VarLogDir -OlderThanMinutes 5
        Remove-OrphanedTmpFiles -Directory $script:VarDbDir -OlderThanMinutes 5
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
    Write-Host ("[LOOP] Naechste Termine: Planning={0} | Monitoring={1}" -f $nextPlan.ToString("HH:mm:ss"), $nextMon.ToString("HH:mm:ss")) -ForegroundColor DarkGray
    $loopMsg = "[LOOP] Naechster Wake-Up ({0}): {1} (in {2} min)" -f $nextType, $nextTimeStr, $sleepMin
    Write-Host $loopMsg -ForegroundColor DarkGray
    Write-Host ""

    Save-AutopilotState -State $State
    Update-AutopilotMainRunLock -Phase "sleeping"
    $remainingSleep = [Math]::Max(1, [int]$sleepSeconds)
    while ($remainingSleep -gt 0) {
        Start-Sleep -Seconds 1
        $remainingSleep--
    }
}

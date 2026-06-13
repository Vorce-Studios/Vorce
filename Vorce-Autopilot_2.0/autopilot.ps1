# Vorce-Autopilot/autopilot.ps1
# Vorce Autopilot - AI CEO Orchestrator
# Main entry point with timer-based wake-up loop

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnce,
    [switch]$CheckAndDoingOnce,
    [switch]$AuditOnce,
    [switch]$OptimizeOnce,
    [switch]$SkipPlanningOnStart,
    [int]$PlanningIntervalOverride,
    [int]$CheckAndDoingIntervalOverride
)

Set-StrictMode -Version Latest
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$script:VarLogDir = Join-Path $ScriptDir "var/log"
$script:VarDbDir = Join-Path $ScriptDir "var/db"
$script:AutopilotLiveLogPath = Join-Path $script:VarLogDir "autopilot-live.log"
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

# --- Load libraries ---
. (Join-Path $ScriptDir "src/lib/state/state-manager.ps1")
. (Join-Path $ScriptDir "src/lib/engines/quota-manager.ps1")
. (Join-Path $ScriptDir "src/core/cli-router.ps1")
. (Join-Path $ScriptDir "src/lib/state/memory-store.ps1")
. (Join-Path $ScriptDir "src/lib/engines/deliberation-engine.ps1")
. (Join-Path $ScriptDir "src/lib/state/autopilot-session-manager.ps1")
. (Join-Path $ScriptDir "src/core/autopilot-prompts.ps1")
. (Join-Path $ScriptDir "src/lib/integrations/github-client.ps1")
. (Join-Path $ScriptDir "src/lib/integrations/jules-client.ps1")
. (Join-Path $ScriptDir "src/lib/utils/naming-convention.ps1")
. (Join-Path $ScriptDir "src/lib/utils/project-manager.ps1")
. (Join-Path $ScriptDir "src/lib/utils/planning-utils.ps1")
. (Join-Path $ScriptDir "src/lib/utils/checkdoing-utils.ps1")
. (Join-Path $ScriptDir "src/core/Invoke-MainRun.ps1")

# Dummy command/placeholder for backward compatibility check
function Get-VorceLagebildSummary {
    return "Dummy Lagebild"
}
function Invoke-RuntimeFileRetention {
    return $true
}

# Guard-Check: Nur die Kern-Bibliotheken pruefen.
# Die alten Wakeup-Funktionen werden jetzt lazy in den Legacy-Fallback-SUB-RUNs geladen.
$requiredAutopilotCommands = @(
    "Get-VorceConfigPrompt",
    "Confirm-WorkingSessionsState",
    "Optimize-AutopilotMemories",
    "Invoke-MainRun"
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
$checkMinutes = if ($CheckAndDoingIntervalOverride -gt 0) { $CheckAndDoingIntervalOverride } else { $Config.wake_intervals.check_and_doing_minutes }

# --- Banner ---
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  VORCE AUTOPILOT - AI CEO Orchestrator (Optimized)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
$planStr = $planMinutes.ToString().PadLeft(4)
$checkStr = $checkMinutes.ToString().PadLeft(4)
Write-Host "  Planning Interval:   $planStr min" -ForegroundColor Cyan
Write-Host "  Check&Doing Interval:$checkStr min" -ForegroundColor Cyan
if ($DryRun.IsPresent) {
    Write-Host "  Mode: DRY RUN (keine echten API-Calls)" -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# --- Initialize state (includes startup cleanup) ---
$State = Initialize-AutopilotState
$QuotaRegistry = Read-QuotaRegistry

# --- Single-shot modes (V2.0: Nutzen die neue MAIN-RUN Architektur) ---
if ($PlanOnce.IsPresent) {
    $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-01_Planning/MAIN-RUN-01_Planning.ps1"
    & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

if ($CheckAndDoingOnce.IsPresent) {
    $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-02_CheckAndDoing/MAIN-RUN-02_CheckAndDoing.ps1"
    & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

if ($AuditOnce.IsPresent) {
    $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-03_Audit/MAIN-RUN-03_Audit.ps1"
    & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

if ($OptimizeOnce.IsPresent) {
    $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-04_Optimizer/MAIN-RUN-04_Optimizer.ps1"
    & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
    $summary = Get-QuotaSummary -Registry $QuotaRegistry
    Write-Host $summary -ForegroundColor DarkGray
    return
}

# --- Main loop ---
$lastPlanTime = [datetime]::MinValue
$lastMonTime = [datetime]::MinValue
$lastMemoryOptTime = [datetime]::MinValue

if (-not $SkipPlanningOnStart.IsPresent) {
    # Default: Force planning on start.
    $lastMonTime = Get-Date

    # Synchronisiere State direkt beim Start
    $State.last_monitoring_at = $lastMonTime.ToString('o')
    # Setze last_planning_at in die Vergangenheit, damit Planungs-Phase sofort triggert
    $lastPlanTime = (Get-Date).AddDays(-1)
    $State.last_planning_at = $lastPlanTime.ToString('o')
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

    $Config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $planMinutes = if ($PlanningIntervalOverride -gt 0) { $PlanningIntervalOverride } else { $Config.wake_intervals.planning_minutes }
    $checkMinutes = if ($CheckAndDoingIntervalOverride -gt 0) { $CheckAndDoingIntervalOverride } else { $Config.wake_intervals.check_and_doing_minutes }

    # Sync timestamps from State in case they were modified (e.g. Session Split)
    if ($State.last_planning_at) {
        try { $lastPlanTime = [datetimeoffset]::Parse($State.last_planning_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime } catch {}
    }

    $planDue = ($now - $lastPlanTime).TotalMinutes -ge $planMinutes
    $checkDue = ($now - $lastMonTime).TotalMinutes -ge $checkMinutes

    $memOptMinutes = if ($Config.wake_intervals.PSObject.Properties.Name -contains "memory_optimization_minutes") { [int]$Config.wake_intervals.memory_optimization_minutes } else { 60 }
    $memOptDue = ($now - $lastMemoryOptTime).TotalMinutes -ge $memOptMinutes

    if ($planDue) {
        try {
            $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-01_Planning/MAIN-RUN-01_Planning.ps1"
            $mainRunResult = & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $actualMainRunResult = if ($mainRunResult -is [System.Array]) { $mainRunResult[-1] } else { $mainRunResult }

            # Warte bis alle SUB-RUNs completed sind (Invoke-MainRun already waits via Wait-Job)
            if ($null -ne $actualMainRunResult -and $actualMainRunResult.status -eq "completed") {
                # Nur setzen, wenn alle SUB-RUNs erfolgreich waren
                $State.last_planning_at = (Get-Date).ToString('o')
            } else {
                # Fallback: Zeitstempel auf vor 5 Minuten setzen für Backoff
                $State.last_planning_at = (Get-Date).AddSeconds(-5).ToString('o')
                $statusStr = if ($null -ne $actualMainRunResult) { $actualMainRunResult.status } else { "unknown" }
                Write-Host "[LOOP] Planning MAIN-RUN nicht komplett erfolgreich (status=$statusStr), Backoff aktiviert." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[LOOP] Planning-Fehler: $_" -ForegroundColor Red
            Write-Host "[LOOP] StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "Planning MAIN-RUN failed" -Context $_.Exception.Message
            # Backoff for 5 minutes on error
            $lastPlanTime = (Get-Date).AddMinutes(-($planMinutes - 5))
            $State.last_planning_at = $lastPlanTime.ToString('o')
        }

        # Planning hat Prioritaet
        if ($checkDue) {
            Write-Host "[LOOP] Check&Doing verschoben - Planning hat Prioritaet." -ForegroundColor DarkGray
            $checkDue = $false
        }

        # Asynchroner Audit-Lauf (MAIN-RUN-03)
        try {
            $auditScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-03_Audit/MAIN-RUN-03_Audit.ps1"
            & $auditScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        } catch {
            Write-Host "[LOOP] Audit-Fehler: $_" -ForegroundColor Red
        }

        # Asynchroner Optimizer-Lauf (MAIN-RUN-04)
        try {
            $optScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-04_Optimizer/MAIN-RUN-04_Optimizer.ps1"
            & $optScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        } catch {
            Write-Host "[LOOP] Optimizer-Fehler: $_" -ForegroundColor Red
        }
    }

    if ($memOptDue) {
        $lastMemoryOptTime = Get-Date
        try {
            $memOptScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-05_MemoryOptimization/MAIN-RUN-05_MemoryOptimization.ps1"
            & $memOptScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
        } catch {
            Write-Host "[LOOP] MemoryOptimization-Fehler: $_" -ForegroundColor Red
        }
    }

    if ($checkDue) {
        try {
            $mainRunScript = Join-Path $ScriptDir "src/runs/MAIN-RUN-02_CheckAndDoing/MAIN-RUN-02_CheckAndDoing.ps1"
            $checkRunResult = & $mainRunScript -GlobalState $State -Config $Config -QuotaRegistry $QuotaRegistry -DryRun:$DryRun
            $actualCheckRunResult = if ($checkRunResult -is [System.Array]) { $checkRunResult[-1] } else { $checkRunResult }

            # Warte bis alle SUB-RUNs completed sind (Invoke-MainRun already waits via Wait-Job)
            if ($null -ne $actualCheckRunResult -and $actualCheckRunResult.status -eq "completed") {
                $lastMonTime = Get-Date
                $State.last_check_and_doing_at = $lastMonTime.ToString('o')
            } else {
                # Fallback: Zeitstempel auf vor 5 Minuten setzen für Backoff
                $lastMonTime = (Get-Date).AddSeconds(-5)
                $State.last_check_and_doing_at = $lastMonTime.ToString('o')
                $statusStr = if ($null -ne $actualCheckRunResult) { $actualCheckRunResult.status } else { "unknown" }
                Write-Host "[LOOP] Check&Doing MAIN-RUN nicht komplett erfolgreich (status=$statusStr), Backoff aktiviert." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[LOOP] Check&Doing-Fehler: $_" -ForegroundColor Red
            Add-ErrorLog -State $State -Message "CheckAndDoing MAIN-RUN failed" -Context $_.Exception.Message
            # Backoff for 5 minutes on error
            $lastMonTime = (Get-Date).AddMinutes(-($checkMinutes - 5))
            $State.last_check_and_doing_at = $lastMonTime.ToString('o')
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
    $nextMon = if ($lastMonTime -eq [datetime]::MinValue) { (Get-Date).AddMinutes($checkMinutes) } else { $lastMonTime.AddMinutes($checkMinutes) }
    $nextWake = @($nextPlan, $nextMon) | Sort-Object | Select-Object -First 1
    $sleepSeconds = [Math]::Max(10, [double]($nextWake - (Get-Date)).TotalSeconds)

    if ($nextWake -eq $nextPlan) { $nextType = "Planning" } else { $nextType = "Check&Doing" }
    $sleepMin = [Math]::Round($sleepSeconds / 60, 1)
    $nextTimeStr = $nextWake.ToString("HH:mm:ss")
    $loopMsg = "[LOOP] Naechster Wake-Up ({0}): {1} (in {2} min)" -f $nextType, $nextTimeStr, $sleepMin
    Write-Host $loopMsg -ForegroundColor DarkGray
    Write-Host ""

    Save-AutopilotState -State $State
    $wakeupFile = Join-Path $ScriptDir "autopilot.wakeup"
    $remainingSleep = [Math]::Max(1, [int]$sleepSeconds)

    $julesPulseInterval = 120 # Lightweight Jules API Poll every 2 minutes
    $lastJulesPulse = Get-Date

    while ($remainingSleep -gt 0) {
        if (Test-Path $wakeupFile) {
            Remove-Item $wakeupFile -Force -ErrorAction SilentlyContinue
            Write-Host "[LOOP] Wake-Up Trigger erkannt! Ueberspringe Sleep." -ForegroundColor Yellow
            # Force run next iteration
            $lastPlanTime = [datetime]::MinValue
            $lastMonTime = [datetime]::MinValue
            break
        }

        $nowPulse = Get-Date
        if (($nowPulse - $lastJulesPulse).TotalSeconds -ge $julesPulseInterval) {
            $lastJulesPulse = $nowPulse
            try {
                if (Get-Command Get-JulesSession -ErrorAction SilentlyContinue) {
                    $activeSessions = Get-AllJulesSessions -PageSize 20 -MaxPages 1 -ApiKey $env:JULES_API_KEY
                    $changed = $false
                    foreach ($sess in $activeSessions) {
                        if (@("COMPLETED", "FAILED", "AWAITING_USER_FEEDBACK") -contains [string]$sess.state) {
                            $changed = $true
                            break
                        }
                    }
                    if ($changed) {
                        Write-Host "[LOOP] Jules-Pulse hat Status-Updates erkannt! Setze Wake-Up Trigger." -ForegroundColor Yellow
                        New-Item -Path $wakeupFile -ItemType File -Force | Out-Null
                    }
                }
            } catch {
                # Ignore pulse errors
            }
        }

        Start-Sleep -Seconds 1
        $remainingSleep--
    }
}

# scripts/codex-cli/Start-Autopilot.ps1
# Zentrales Start-Skript für den Vorce Autopilot
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnce,
    [switch]$MonitorOnce,
    [switch]$NoStopExisting,
    [switch]$NoInitialPlanning,
    [switch]$NoControlConsole,
    [switch]$ShowAutopilotWindow,
    [switch]$HideAutopilotWindow,
    [int]$PlanningIntervalOverride,
    [int]$MonitoringIntervalOverride
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$DashboardDir = Join-Path $ScriptDir "dashboard"
. (Join-Path $ScriptDir "lib\autopilot-prompts.ps1")
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$StartLogPath = Join-Path $LogDir ("start-autopilot-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$script:StartedProcessIds = @()

function Write-StartLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format o), $Level, $Message
    Add-Content -Path $StartLogPath -Value $line -Encoding UTF8
}

function Write-InitStatus {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    Write-Host $Message -ForegroundColor $Color
    Write-StartLog -Message $Message -Level $Level
}

trap {
    $message = "Unhandled start error at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-StartLog -Message $message -Level "ERROR"
    Write-Host "[ERROR] $message" -ForegroundColor Red
    Write-Host "[ERROR] Start-Log: $StartLogPath" -ForegroundColor Yellow
    Stop-StartedAutopilotProcesses
    break
}

function Register-StartedAutopilotProcess {
    param([AllowNull()]$Process)

    if ($null -eq $Process) { return }
    $script:StartedProcessIds = @($script:StartedProcessIds + [int]$Process.Id | Select-Object -Unique)
}

function Stop-StartedAutopilotProcesses {
    if ($script:StartedProcessIds.Count -eq 0) { return }

    Write-StartLog -Message "Cleaning up started PIDs: $($script:StartedProcessIds -join ', ')"
    foreach ($processId in @($script:StartedProcessIds)) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Resolve-PowerShellHost {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return (Get-Command powershell -ErrorAction Stop).Source
}

function Get-ManagedAutopilotProcess {
    param(
        [Parameter(Mandatory)][string]$Pattern
    )

    $rootPattern = [regex]::Escape(($ScriptDir -replace '\\', '/'))
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.CommandLine -and
        (([string]$_.CommandLine -replace '\\', '/') -match $rootPattern) -and
        ($_.CommandLine -match $Pattern)
    })
}

function Get-AutopilotSuiteProcess {
    $rootPattern = [regex]::Escape(($ScriptDir -replace '\\', '/'))
    $dashboardPattern = [regex]::Escape(($DashboardDir -replace '\\', '/'))
    $patterns = @(
        'autopilot\.ps1',
        'interval-stats\.ps1',
        'run-visible-codex-session\.ps1',
        'run-visible-ceo-phase\.ps1',
        'npm(\.cmd)?\s+run\s+dev',
        'vite[\\/]bin[\\/]vite\.js',
        'codex(\.cmd|\.ps1|\.exe)?\s',
        'gemini(\.cmd|\.ps1|\.exe)?\s',
        'openai[\\/]codex'
    )

    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        if ($_.ProcessId -eq $PID -or -not $_.CommandLine) { return $false }
        $commandLine = [string]$_.CommandLine -replace '\\', '/'
        $belongsToSuite = ($commandLine -match $rootPattern) -or ($commandLine -match $dashboardPattern)
        if (-not $belongsToSuite) { return $false }

        foreach ($pattern in $patterns) {
            if ($commandLine -match $pattern) { return $true }
        }
        return $false
    })
}

function Stop-AutopilotSuiteProcesses {
    $processes = @(Get-AutopilotSuiteProcess | Sort-Object ProcessId -Unique)
    if ($processes.Count -eq 0) {
        Write-InitStatus "[INIT] Keine alten Autopilot-Prozesse gefunden." -Color DarkGray
        return
    }

    Write-InitStatus "[INIT] Beende alte Autopilot-Prozesse: $($processes.ProcessId -join ', ')" -Color Yellow
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        } catch {
            Write-Warning "[INIT] Prozess $($process.ProcessId) konnte nicht beendet werden: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds 2
}

function Show-AutopilotSuiteStatus {
    $processes = @(Get-AutopilotSuiteProcess | Sort-Object ProcessId -Unique)
    if ($processes.Count -eq 0) {
        Write-Host "[CONTROL] Keine Autopilot-Prozesse aktiv." -ForegroundColor Yellow
        return
    }

    Write-Host "[CONTROL] Aktive Suite-Prozesse: $($processes.ProcessId -join ', ')" -ForegroundColor Cyan
    Write-StartLog -Message "Control status active PIDs: $($processes.ProcessId -join ', ')"
}

function Get-AutopilotControlStateSummary {
    $statePath = Join-Path $ScriptDir "autopilot-state.json"
    if (-not (Test-Path -LiteralPath $statePath)) {
        return "[STATE] Noch kein autopilot-state.json gefunden."
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $lastBeat = [datetimeoffset]::MinValue
        $hasLastBeat = $false
        if ($state.last_heartbeat) {
            try {
                $lastBeat = [datetimeoffset]::Parse([string]$state.last_heartbeat, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $hasLastBeat = $true
            } catch {
                $hasLastBeat = [datetimeoffset]::TryParse([string]$state.last_heartbeat, [ref]$lastBeat)
            }
        }
        $beatAge = if ($hasLastBeat) {
            "{0:N0}m" -f ((Get-Date) - $lastBeat.LocalDateTime).TotalMinutes
        } else {
            "n/a"
        }
        $delegCount = @($state.active_delegations).Count
        $reviewCount = @($state.review_queue).Count
        $decisionCount = @($state.decisions_pending).Count
        $sessionId = [string]$state.session_id
        $time = Get-Date -Format "HH:mm:ss"
        return "[STATE $time] Session=$sessionId Beat=$beatAge Delegierungen=$delegCount Review=$reviewCount Entscheidungen=$decisionCount"
    } catch {
        return "[STATE] Fehler beim Lesen von autopilot-state.json: $($_.Exception.Message)"
    }
}

function Wait-AutopilotControlConsole {
    $previousTreatControlCAsInput = [Console]::TreatControlCAsInput
    [Console]::TreatControlCAsInput = $true

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " VORCE AUTOPILOT CONTROL" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " Q = komplette Suite beenden" -ForegroundColor Cyan
    Write-Host " Ctrl+C = komplette Suite beenden" -ForegroundColor Cyan
    Write-Host " S = aktive Prozesse anzeigen" -ForegroundColor Cyan
    Write-Host " W = sofortigen Autopilot Wake-Up triggern" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
    Write-StartLog -Message "Control console active."
    Write-Host (Get-AutopilotControlStateSummary) -ForegroundColor DarkGray

    try {
        while ($true) {
            if (-not [Console]::KeyAvailable) {
                Start-Sleep -Milliseconds 500
                continue
            }

            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "C" -and ($key.Modifiers -band [ConsoleModifiers]::Control)) {
                Write-Host "[CONTROL] Ctrl+C erkannt. Beende Vorce Autopilot Suite..." -ForegroundColor Yellow
                Write-StartLog -Message "Control requested suite stop via Ctrl+C."
                Stop-AutopilotSuiteProcesses
                Write-Host "[CONTROL] Suite beendet." -ForegroundColor Green
                Write-StartLog -Message "Suite stopped by control console."
                return
            }

            switch ($key.Key) {
                "Q" {
                    Write-Host "[CONTROL] Beende Vorce Autopilot Suite..." -ForegroundColor Yellow
                    Write-StartLog -Message "Control requested suite stop."
                    Stop-AutopilotSuiteProcesses
                    Write-Host "[CONTROL] Suite beendet." -ForegroundColor Green
                    Write-StartLog -Message "Suite stopped by control console."
                    return
                }
                "S" {
                    Show-AutopilotSuiteStatus
                }
                "W" {
                    $wakeupFile = Join-Path $ScriptDir "autopilot.wakeup"
                    Set-Content -Path $wakeupFile -Value (Get-Date -Format o) -Encoding UTF8
                    Write-Host "[CONTROL] Wake-Up Trigger geschrieben: $wakeupFile" -ForegroundColor Green
                    Write-StartLog -Message "Control wrote wakeup trigger: $wakeupFile"
                }
            }
        }
    } finally {
        [Console]::TreatControlCAsInput = $previousTreatControlCAsInput
    }
}

function Test-LocalPortListening {
    param([Parameter(Mandatory)][int]$Port)

    try {
        return $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
    } catch {
        return $false
    }
}

function Wait-LocalPortFree {
    param(
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-LocalPortListening -Port $Port)) { return $true }
        Start-Sleep -Milliseconds 500
    }

    return -not (Test-LocalPortListening -Port $Port)
}

function Test-DashboardHealth {
    param(
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $index = Invoke-WebRequest -Uri "http://127.0.0.1:5173" -UseBasicParsing -TimeoutSec 3
            $registry = Invoke-WebRequest -Uri "http://127.0.0.1:5173/registry.json" -UseBasicParsing -TimeoutSec 3
            $localhost = Invoke-WebRequest -Uri "http://localhost:5173" -UseBasicParsing -TimeoutSec 3
            if ($index.StatusCode -eq 200 -and $registry.StatusCode -eq 200 -and $localhost.StatusCode -eq 200) {
                return $true
            }
        } catch {
            Start-Sleep -Milliseconds 750
        }
    }

    return $false
}

$PowerShellHost = Resolve-PowerShellHost

if ([string]::IsNullOrWhiteSpace($env:JULES_API_KEY)) {
    $persistedJulesApiKey = [Environment]::GetEnvironmentVariable("JULES_API_KEY", "User")
    if ([string]::IsNullOrWhiteSpace($persistedJulesApiKey)) {
        $persistedJulesApiKey = [Environment]::GetEnvironmentVariable("JULES_API_KEY", "Machine")
    }
    if (-not [string]::IsNullOrWhiteSpace($persistedJulesApiKey)) {
        $env:JULES_API_KEY = $persistedJulesApiKey
    }
}

Write-Host "=====================================" -ForegroundColor Green
Write-Host " STARTE VORCE AUTOPILOT SUITE" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-StartLog -Message "Starting Vorce Autopilot Suite from $ScriptDir"

# Git-Branch überprüfen
$currentBranch = git branch --show-current 2>$null
if ($null -ne $currentBranch -and $currentBranch.Trim() -ne "main") {
    Write-Warning "[INIT] Das Repository befindet sich nicht auf dem Branch 'main', sondern auf '$($currentBranch.Trim())'!"
    Write-Warning "[INIT] Dies kann dazu fuehren, dass Autopilot-Skripte fehlen oder veraltet sind."

    # Pruefen, ob uncommittete Aenderungen vorliegen
    $gitStatus = git status --porcelain 2>$null
    if ([string]::IsNullOrWhiteSpace($gitStatus)) {
        Write-InitStatus "[INIT] Keine uncommitteten Aenderungen. Wechsle automatisch auf 'main'..." -Color Yellow
        git checkout main 2>&1 | Out-Null
        $currentBranch = git branch --show-current 2>$null
        if ($currentBranch.Trim() -eq "main") {
            Write-InitStatus "[INIT] Erfolgreich auf 'main' gewechselt." -Color Green
        } else {
            Write-InitStatus "[INIT] Wechsel auf 'main' fehlgeschlagen. Bitte manuell 'git checkout main' ausfuehren!" -Color Red -Level "ERROR"
        }
    } else {
        Write-InitStatus "[INIT] Uncommittete Aenderungen vorhanden. Wechsel auf 'main' uebersprungen. Bitte manuell bereinigen und 'git checkout main' ausfuehren!" -Color Yellow -Level "WARN"
    }
}

if (-not $NoStopExisting.IsPresent) {
    Stop-AutopilotSuiteProcesses
    Wait-LocalPortFree -Port 5173 | Out-Null
}

# 1. Dashboard-Server im Hintergrund starten
Write-InitStatus "[INIT] Starte Dashboard Web-Server (Vite)..."
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-StartLog -Message "npm command not available; dashboard not started." -Level "WARN"
    Write-Warning "[INIT] npm ist nicht verfuegbar. Dashboard-Server wird nicht gestartet."
} elseif (Test-LocalPortListening -Port 5173) {
    if (Test-DashboardHealth -TimeoutSeconds 5) {
        Write-InitStatus "[INIT] Dashboard Web-Server laeuft bereits und antwortet auf http://127.0.0.1:5173." -Color DarkGray
    } else {
        Write-InitStatus "[INIT] Port 5173 ist belegt, aber Dashboard antwortet nicht sauber. Starte Suite bitte ohne -NoStopExisting neu." -Color Yellow -Level "WARN"
    }
} else {
    try {
        $dashboardProcess = Start-Process $PowerShellHost -ArgumentList @("-NoExit", "-NoProfile", "-Command", "Set-Location -LiteralPath '$DashboardDir'; npm run dev -- --host 0.0.0.0") -WindowStyle Hidden -PassThru
        Register-StartedAutopilotProcess -Process $dashboardProcess
        Write-StartLog -Message "Dashboard started. PID=$($dashboardProcess.Id)"
        if (Test-DashboardHealth -TimeoutSeconds 20) {
            Write-InitStatus "[INIT] Dashboard Health OK: http://localhost:5173 und http://127.0.0.1:5173" -Color Green
        } else {
            Write-InitStatus "[INIT] Dashboard wurde gestartet, antwortet aber noch nicht auf http://127.0.0.1:5173." -Color Yellow -Level "WARN"
        }
    } catch {
        Write-StartLog -Message "Dashboard start failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# 2. Sync-Prozess im Hintergrund starten
Write-InitStatus "[INIT] Starte Dashboard-Sync Service..."
$syncProcesses = @(Get-ManagedAutopilotProcess -Pattern 'interval-stats\.ps1')
if ($syncProcesses.Count -gt 0) {
    Write-InitStatus "[INIT] Dashboard-Sync Service laeuft bereits (PID $($syncProcesses[0].ProcessId))." -Color DarkGray
} else {
    try {
        $syncProcess = Start-Process $PowerShellHost -ArgumentList @("-NoExit", "-NoProfile", "-File", (Join-Path $ScriptDir "phases\interval-stats.ps1")) -WindowStyle Hidden -PassThru
        Register-StartedAutopilotProcess -Process $syncProcess
        Write-StartLog -Message "Dashboard sync started. PID=$($syncProcess.Id)"
    } catch {
        Write-StartLog -Message "Dashboard sync start failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# 3. Autopilot-Backend autonom starten
Write-InitStatus "[INIT] Starte Autopilot Backend Loop..."
$AutopilotFile = Join-Path $ScriptDir "autopilot.ps1"
$AutopilotArgs = @("-NoExit", "-NoProfile", "-File", $AutopilotFile)
if ($DryRun.IsPresent) { $AutopilotArgs += "-DryRun" }
if ($PlanOnce.IsPresent) { $AutopilotArgs += "-PlanOnce" }
if ($MonitorOnce.IsPresent) { $AutopilotArgs += "-MonitorOnce" }
if ($NoInitialPlanning.IsPresent) { $AutopilotArgs += "-SkipPlanningOnStart" }
if ($PlanningIntervalOverride -gt 0) { $AutopilotArgs += @("-PlanningIntervalOverride", [string]$PlanningIntervalOverride) }
if ($MonitoringIntervalOverride -gt 0) { $AutopilotArgs += @("-MonitoringIntervalOverride", [string]$MonitoringIntervalOverride) }
$autopilotProcesses = @(Get-ManagedAutopilotProcess -Pattern 'autopilot\.ps1')
if ($autopilotProcesses.Count -gt 0) {
    Write-InitStatus "[INIT] Autopilot Backend Loop laeuft bereits (PID $($autopilotProcesses[0].ProcessId))." -Color DarkGray
} else {
    $autopilotWindowStyle = if ($HideAutopilotWindow.IsPresent) { "Hidden" } else { "Normal" }
    if ($ShowAutopilotWindow.IsPresent) { $autopilotWindowStyle = "Normal" }
    try {
        $autopilotProcess = Start-Process $PowerShellHost -ArgumentList $AutopilotArgs -WindowStyle $autopilotWindowStyle -PassThru
        Register-StartedAutopilotProcess -Process $autopilotProcess
        Write-StartLog -Message "Autopilot backend started. PID=$($autopilotProcess.Id) WindowStyle=$autopilotWindowStyle Args=$($AutopilotArgs -join ' ')"
    } catch {
        Write-StartLog -Message "Autopilot backend start failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

Write-Host "-------------------------------------"
Write-Host "[READY] Dashboard verfuegbar unter: http://localhost:5173" -ForegroundColor Green
Write-Host "[READY] Autopilot-Loop laeuft in einem separaten PowerShell-Fenster." -ForegroundColor Green
Write-Host "[READY] Codex-Planning-Sessions werden automatisch in separaten sichtbaren Fenstern gestartet." -ForegroundColor Green
Write-Host "[READY] Start-Log: $StartLogPath" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-StartLog -Message "Start sequence completed."

if (-not $NoControlConsole.IsPresent) {
    Wait-AutopilotControlConsole
}

# autopilot.ps1 (Vorce 3.0)
# Haupt-Einstiegspunkt für den VORCE Autopilot Loop
[CmdletBinding()]
param(
    [switch]$DryRun,
    [int]$IntervalMinutes = 15
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$global:VorceRoot = $PSScriptRoot
$global:VarDir    = Join-Path $global:VorceRoot "var"
$global:SrcDir    = Join-Path $global:VorceRoot "src"
$global:LibDir    = Join-Path $global:SrcDir "lib"
$LogDir = Join-Path $global:VarDir "log"
$DbDir  = Join-Path $global:VarDir "db"

# --- Health-Check ---
$requiredDirs = @($global:VarDir, $LogDir, $DbDir,
    (Join-Path $global:VarDir "run-states"),
    (Join-Path $global:VarDir "tmp"),
    (Join-Path $DbDir "proposals"))
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# --- 1. Core Modules laden ---
. (Join-Path $global:VorceRoot "src/lib/utils/StatusPrinter.ps1")
. (Join-Path $global:VorceRoot "src/lib/state/StateManager.ps1")

# --- 2. Rolling Log System ---
function Rotate-Logs {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $logs = Get-ChildItem -Path $LogDir -Filter "autopilot_*.log" | Sort-Object LastWriteTime -Descending
    if ($logs.Count -ge 10) {
        $logs[9..($logs.Count-1)] | Remove-Item -Force
    }
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogPath = Join-Path $LogDir "autopilot_$Timestamp.log"
Rotate-Logs

function Write-VorceLog {
    param([string]$Message, [string]$Status = "INFO", [ConsoleColor]$Color = "White")
    Write-VorceStep -Message $Message -Status $Status
    $Line = "[$((Get-Date).ToString('HH:mm:ss'))] [$Status] $Message"
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
}

Write-VorceHeader -Title "VORCE AUTOPILOT 3.0" -Icon "🤖"

# --- 3. Initialisierung ---
Write-VorceLog "Lade Konfiguration..." -Status "INFO"
$configPath = Join-Path $global:VarDir "config/autopilot-config.json"
if (-not (Test-Path $configPath)) {
    Write-VorceLog "Konfiguration nicht gefunden: $configPath" -Status "ERROR"
    return
}

$GlobalState = Read-VorceGlobalState
Write-VorceLog "Global State geladen (v$($GlobalState.version))." -Status "OK"

# --- 4. Main Loop ---
Write-VorceLog "Starte Orchestrierung (Intervall: $IntervalMinutes min)..." -Status "RUN"

while ($true) {
    try {
        # --- Orchestrator Aufruf ---
        $orchestratorPath = Join-Path $global:VorceRoot "src/orchestrator/Vorce-Orchestrator.ps1"
        if (Test-Path $orchestratorPath) {
            & $orchestratorPath -GlobalState $GlobalState
        } else {
            Write-VorceLog "Orchestrator nicht gefunden: $orchestratorPath" -Status "ERROR"
        }

    } catch {
        Write-VorceLog "[CRITICAL] Fehler im Loop: $($_.Exception.Message)" -Status "ERROR"
    }

    $wakeupFile = Join-Path $ScriptDir "autopilot.wakeup"
    $remainingSeconds = $IntervalMinutes * 60
    
    Write-VorceLog "[IDLE] Naechster Lauf in $IntervalMinutes Minuten..." "Gray"
    
    while ($remainingSeconds -gt 0) {
        if (Test-Path $wakeupFile) {
            Remove-Item $wakeupFile -Force
            Write-VorceLog "[WAKEUP] Wakeup-Signal erkannt!" "Yellow"
            break
        }
        Start-Sleep -Seconds 1
        $remainingSeconds--
    }
}

# autopilot.ps1 (Vorce 3.0)
# Haupt-Einstiegspunkt für den VORCE Autopilot Loop
[CmdletBinding()]
param(
    [switch]$DryRun,
    [int]$IntervalMinutes = 15
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$VarDir = Join-Path $ScriptDir "var"
$LogDir = Join-Path $VarDir "log"
$DbDir = Join-Path $VarDir "db"

# --- 1. Core Modules laden ---
. (Join-Path $ScriptDir "src/lib/StatusPrinter.ps1")
. (Join-Path $ScriptDir "src/lib/StateManager.ps1")

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
$configPath = Join-Path $VarDir "config/autopilot-config.json"
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
        $orchestratorPath = Join-Path $ScriptDir "src/orchestrator/Vorce-Orchestrator.ps1"
        if (Test-Path $orchestratorPath) {
            & $orchestratorPath -GlobalState $GlobalState
        } else {
            Write-VorceLog "Orchestrator nicht gefunden: $orchestratorPath" -Status "ERROR"
        }

    } catch {
        Write-VorceLog "[CRITICAL] Fehler im Loop: $($_.Exception.Message)" "Red"
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

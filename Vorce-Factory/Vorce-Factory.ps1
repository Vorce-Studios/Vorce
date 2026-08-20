# Vorce-Factory.ps1 (Vorce 3.0)
# Haupt-Einstiegspunkt fÃ¼r den VORCE Factory Loop
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$RunOnce,
    [switch]$StartupSequence,
    [string]$ResumeRunId,
    [int]$StartupDelaySeconds = 8,
    [int]$IntervalMinutes = 15,
    [ValidateSet(
        "MAIN-RUN-01_Planning",
        "MAIN-RUN-02_CheckAndDoing",
        "MAIN-RUN-03_Audit",
        "MAIN-RUN-04_Optimizer",
        "MAIN-RUN-05_MemoryOptimization"
    )]
    [string]$ForceMainRun
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$global:VorceRoot = $PSScriptRoot
$global:VarDir    = Join-Path $global:VorceRoot "var"
$global:SrcDir    = Join-Path $global:VorceRoot "src"
$global:LibDir    = Join-Path $global:SrcDir "lib"
$LogDir = Join-Path $global:VarDir "log"
$DbDir  = Join-Path $global:VarDir "db"

. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "logging/Write-Log.ps1")

. (Join-Path $global:LibDir "state/StateManager.ps1")

# --- Health-Check ---
$requiredDirs = @($global:VarDir, $LogDir, $DbDir,
    (Join-Path $global:VarDir "run-states"),
    (Join-Path $global:VarDir "tmp"),
    (Join-Path $DbDir "proposals"))
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Clean-TmpFiles {
    param([int]$MaxAgeHours = 24)

    $tmpDir = Join-Path $global:VarDir "tmp"
    if (-not (Test-Path $tmpDir)) { return }

    $cutoffTime = (Get-Date).AddHours(-$MaxAgeHours)
    $oldFiles = Get-ChildItem -Path $tmpDir -File | Where-Object { $_.CreationTime -lt $cutoffTime }

    if ($oldFiles.Count -gt 0) {
        Write-VorceStep -Message "Bereinige alte tmp-Dateien (>$MaxAgeHours Stunden)..." -Status "INFO"
        foreach ($file in $oldFiles) {
            try {
                Remove-Item $file.FullName -Force
                Write-VorceStep -Message "GelÃ¶scht: $($file.Name)" -Status "INFO"
            } catch {
                Write-VorceStep -Message "Konnte $($file.Name) nicht lÃ¶schen: $($_.Exception.Message)" -Status "WARN"
            }
        }
    }
}

function Enable-DebugMode {
    param([bool]$Enabled)
    $script:debugMode = $Enabled

    # Lade Config fÃ¼r Debug-Einstellungen
    $configPath = Join-Path $global:VarDir "config/autopilot-config.json"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.debug_mode) {
                $script:debugMode = [bool]$config.debug_mode
            }
        } catch {
            # Fehler beim Lesen der Config ignoriert, nutze Parameter
        }
    }
}

# Globale Debug-Flag initialisieren
$script:debugMode = $false


$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$LogPath = Join-Path $LogDir "autopilot_$Timestamp.log"
Rotate-Logs

function Write-VorceLog {
    param([string]$Message, [string]$Status = "INFO", [ConsoleColor]$Color = "White")
    Write-VorceStep -Message $Message -Status $Status
    $Line = "[$((Get-Date).ToString('HH:mm:ss'))] [$Status] $Message"
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
}

Enable-DebugMode -Enabled $false
Write-VorceLog "FÃ¼hre Startup Cleanup aus..." -Status "RUN"
Clean-TmpFiles -MaxAgeHours 24

Write-VorceHeader -Title "VORCE FACTORY 3.0" -Icon "ðŸ­"

# --- 3. Initialisierung ---
Write-VorceLog "Lade Konfiguration..." -Status "INFO"
$configPath = Join-Path $global:VarDir "config/autopilot-config.json"
if (-not (Test-Path $configPath)) {
    Write-VorceLog "Konfiguration nicht gefunden: $configPath" -Status "ERROR"
    return
}

$GlobalState = Read-VorceGlobalState
Write-VorceLog "Global State geladen (v$($GlobalState.version))." -Status "OK"

function Invoke-VorceOrchestrator {
    param(
        [string]$MainRunName,
        [string]$RunId
    )

    $orchestratorPath = Join-Path $global:VorceRoot "src/orchestrator/Vorce-Orchestrator.ps1"
    if (-not (Test-Path $orchestratorPath)) {
        Write-VorceLog "Orchestrator nicht gefunden: $orchestratorPath" -Status "ERROR"
        return
    }

    $GlobalState = Read-VorceGlobalState
    if ($RunId) {
        & $orchestratorPath -GlobalState $GlobalState -DryRun:$DryRun -ResumeRunId $RunId
    } elseif ([string]::IsNullOrWhiteSpace($MainRunName)) {
        & $orchestratorPath -GlobalState $GlobalState -DryRun:$DryRun
    } else {
        & $orchestratorPath -GlobalState $GlobalState -DryRun:$DryRun -ForceMainRun $MainRunName
    }
}

# --- 4. Main Loop ---
Write-VorceLog "Starte Orchestrierung (Intervall: $IntervalMinutes min)..." -Status "RUN"

if ($StartupSequence -and -not $ForceMainRun) {
    Write-VorceLog "[STARTUP] Erzwinge Planning RUN beim Start..." -Status "RUN"
    Invoke-VorceOrchestrator -MainRunName "MAIN-RUN-01_Planning"
    if (-not $DryRun) {
        Write-VorceLog "[STARTUP] Warte $StartupDelaySeconds Sekunden vor Check & Doing..." -Status "INFO"
        Start-Sleep -Seconds $StartupDelaySeconds
    }
    Write-VorceLog "[STARTUP] Erzwinge Check & Doing RUN beim Start..." -Status "RUN"
    Invoke-VorceOrchestrator -MainRunName "MAIN-RUN-02_CheckAndDoing"

    if ($DryRun -or $RunOnce) {
        Write-VorceLog "Startsequenz abgeschlossen." -Status "OK"
        return
    }
}

while ($true) {
    try {
        $effectiveResumeRunId = $ResumeRunId
        if (-not $effectiveResumeRunId -and -not $ForceMainRun) {
            $resumable = Get-VorceResumableMainRun
            if ($resumable) { $effectiveResumeRunId = [string]$resumable.id }
Enable-DebugMode -Enabled $false
Write-VorceStep -Message "FÃ¼hre Startup Cleanup aus..." -Status "RUN"
Clean-TmpFiles -MaxAgeHours 24

        }
        Invoke-VorceOrchestrator -MainRunName $ForceMainRun -RunId $effectiveResumeRunId
        $ResumeRunId = $null

    } catch {
        Write-VorceLog "[CRITICAL] Fehler im Loop: $($_.Exception.Message)" -Status "ERROR"
    }

    if ($DryRun -or $RunOnce) {
        Write-VorceLog "Einzellauf abgeschlossen." -Status "OK"
        break
    }

    $wakeupFile = Join-Path $global:VorceRoot "autopilot.wakeup"
    $remainingSeconds = $IntervalMinutes * 60

    Write-VorceLog "[IDLE] Naechster Lauf in $IntervalMinutes Minuten..." -Status "INFO"

    while ($remainingSeconds -gt 0) {
        if (Test-Path $wakeupFile) {
            Remove-Item $wakeupFile -Force
            Write-VorceLog "[WAKEUP] Wakeup-Signal erkannt!" -Status "RUN"
            break
        }
        Start-Sleep -Seconds 1
        $remainingSeconds--
    }
}

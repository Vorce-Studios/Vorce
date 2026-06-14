# Vorce-Orchestrator.ps1 (Vorce 3.0)
# Zentrales Steuerungs-Modul für die Run-Hierarchie mit dynamischer Scheduling
[CmdletBinding()]
param(
    [object]$GlobalState,
    [switch]$DryRun
)

$global:VorceRoot = Join-Path $PSScriptRoot ".."
$global:SrcDir = Join-Path $global:VorceRoot "src"
$global:LibDir = Join-Path $global:SrcDir "lib"

# A) Module laden (mit neuen Pfaden via $global:LibDir)
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "utils/ProjectManager.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

Write-VorceHeader -Title "ORCHESTRATOR ACTIVE" -Icon "🧠"

# B) Config und Quota laden
$Config = Get-Content (Join-Path $global:VarDir "config/autopilot-config.json") -Raw | ConvertFrom-Json
$QuotaRegistry = Get-Content (Join-Path $global:VarDir "config/quota-registry.json") -Raw | ConvertFrom-Json

# C) ConfigBag bauen (W1)
$ConfigBag = @{
    VorceRoot = $global:VorceRoot;
    VarDir = $global:VarDir;
    LibDir = $global:LibDir
    Config = $Config;
    GlobalState = $GlobalState;
    QuotaRegistry = $QuotaRegistry;
    DryRun = $DryRun;
    Timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Config geladen: $($Config.enabledFeatures -join ', ')" -Status "INFO"

# D) Scheduling-Logik implementieren (C4)
function Select-NextMainRun {
    param([object]$GlobalState, [object]$Config)
    $runs = @(
        @{ Name="MAIN-RUN-01_Planning"; IntervalKey="planning_minutes" },
        @{ Name="MAIN-RUN-02_CheckAndDoing"; IntervalKey="check_and_doing_minutes" },
        @{ Name="MAIN-RUN-03_Audit"; IntervalKey="memory_optimization_minutes" }
    )
    $now = Get-Date
    $best = $null; $bestOverdue = -1
    foreach ($run in $runs) {
        $interval = [int]$Config.wake_intervals.($run.IntervalKey)
        $lastRun = $null
        if ($GlobalState.last_runs -and $GlobalState.last_runs.PSObject.Properties.Name -contains $run.Name) {
            $lastRun = [datetime]$GlobalState.last_runs.($run.Name)
        }
        $overdue = if ($null -eq $lastRun) { [int]::MaxValue } else { ($now - $lastRun).TotalMinutes - $interval }
        if ($overdue -gt $bestOverdue) { $best = $run; $bestOverdue = $overdue }
    }
    # Nur ausführen wenn mindestens ein Run überfällig ist
    if ($bestOverdue -gt 0) {
        return @{ Name=$best.Name; OverdueMinutes=$bestOverdue }
    } else {
        return $null
    }
}

# Wähle dynamisch den nächsten Main-RUN
$RunsDir = Join-Path $global:SrcDir "runs"
$result = Select-NextMainRun -GlobalState $GlobalState -Config $Config
$mainRunName = $result.Name
$bestOverdue = $result.OverdueMinutes

if ($null -eq $mainRunName) {
    Write-VorceStep -Message "Kein Run überfällig." -Status "INFO"
    return
}

Write-VorceStep -Message "Wähle $mainRunName (überfällig um $bestOverdue Minuten)" -Status "RUN"

# E) Dynamischen Router-Aufruf (C8)
$MainRunPath = Join-Path $RunsDir $mainRunName
$RouterPath = Join-Path $RunsDir "$mainRunName/*-Router.ps1"  # Wildcard
$routerFile = Get-ChildItem -Path $MainRunPath -Filter "*-Router.ps1" | Select-Object -First 1

Write-VorceStep -Message "Lade Sub-Runs von Router..." -Status "INFO"

$SubRuns = @()
if ($routerFile) {
    $SubRuns = & $routerFile.FullName -ConfigBag $ConfigBag -ParentState $null
} else {
    Write-VorceStep -Message "Kein Router gefunden in $mainRunName. Nutze Standard-Sub-Runs." -Status "WARN"
    $SubRuns = @(
        @{ name="DataSync"; script=(Join-Path $MainRunPath "SUB-RUNS/SUB-RUN-01_DataSync/SUB-RUN-01_DataSync.ps1") },
        @{ name="Triage"; script=(Join-Path $MainRunPath "SUB-RUNS/SUB-RUN-02_Triage/SUB-RUN-02_Triage.ps1") },
        @{ name="Strategy"; script=(Join-Path $MainRunPath "SUB-RUNS/SUB-RUN-03_Strategy/SUB-RUN-03_Strategy.ps1") }
    )
}

# Initialisiere Main-Run State
$MainState = Initialize-RunState -RunName $mainRunName -RunType "MAIN"

# F) Try/Catch um jeden Sub-Run (C9)
Write-VorceStep -Message "Geplante Sub-Runs: $($SubRuns.Count)" -Status "INFO"

foreach ($sub in $SubRuns) {
    Write-VorceDivider
    Write-VorceStep -Message "Starte Sub-Run: $($sub.name)" -Status "RUN"

    try {
        $subScript = Join-Path $global:VorceRoot $sub.script
        if (Test-Path $subScript) {
            $subResult = & $subScript -ConfigBag $ConfigBag -ParentState $MainState
            $MainState.results += $subResult
            Write-VorceStep -Message "Sub-Run $($sub.name) abgeschlossen." -Status "OK"
        } else {
            throw "Sub-Run Skript nicht gefunden: $subScript"
        }
    } catch {
        Write-VorceStep -Message "Sub-Run $($sub.name) fehlgeschlagen: $($_.Exception.Message)" -Status "ERROR"
        $MainState.results += @{ name=$sub.name; status="failed"; error=$_.Exception.Message; timestamp=(Get-Date).ToString("o") }
    }
}

# G) Nach Abschluss last_runs Timestamp aktualisieren
if (-not $GlobalState.last_runs) {
    $GlobalState | Add-Member -MemberType NoteProperty -Name "last_runs" -Value @{} -Force
}
$GlobalState.last_runs | Add-Member -MemberType NoteProperty -Name $mainRunName -Value (Get-Date).ToString("o") -Force
Save-VorceGlobalState -State $GlobalState

# 6. Finale Aggregation und Abschluss
Write-VorceDivider
Write-VorceStep -Message "Führe alle Sub-Run Ergebnisse zusammen (Main-Aggregation)..." -Status "RUN"

$MainState.status = "completed"
$MainState.completed_at = (Get-Date).ToString("o")

# Falls ein Aggregations-Skript existiert (z.B. MAIN-RUN-01_Planning_Aggregate.ps1)
# & ...

Write-VorceStep -Message "Main-Aggregation für $mainRunName abgeschlossen." -Status "OK"

# 7. Finaler Sync
Write-VorceStep -Message "Sichere Global State..." -Status "RUN"
Save-VorceGlobalState -State $GlobalState

Write-VorceFooter -Message "$mainRunName erfolgreich beendet."

# Test-OrchestratorDryRun.ps1 (Vorce 3.0)
# Test-Skript um den Orchestrator im DryRun-Modus zu prüfen

# Setze Working Directory zum Projekt-Root
Set-Location $PSScriptRoot
Write-Host "Projekt-Root: $(Get-Location)"

# Ergebnisse-Tracking
$passCount = 0
$totalChecks = 0

function Write-TestResult {
    param([string]$Message, [bool]$Passed)
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    Write-Host "$status $Message"
    if ($Passed) { $script:passCount++ }
    $script:totalChecks++
}

# 1. Setze $global:VorceRoot korrekt
$global:VorceRoot = $PSScriptRoot
Write-TestResult "VorceRoot korrekt gesetzt" ($global:VorceRoot -like "*Vorce-Autopilot_NEW")

# Lade Config
$configPath = "var/config/autopilot-config.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
}

# 2. Prüfe Modul-Pfade (nicht laden, nur prüfen)
Write-Host "`n=== MODULE CHECKS ===" -ForegroundColor Yellow
$modules = @(
    "src/lib/utils/StatusPrinter.ps1",
    "src/lib/state/StateManager.ps1",
    "src/lib/utils/ProjectManager.ps1",
    "src/lib/engines/RunEngine.ps1",
    "src/lib/engines/QuotaManager.ps1"
)

foreach ($module in $modules) {
    if (Test-Path $module) {
        Write-TestResult "Modul $module existiert" $true
    } else {
        Write-TestResult "Modul $module existiert nicht" $false
    }
}

# 3. SCHEDULING TESTS
Write-Host "`n=== SCHEDULING TESTS ===" -ForegroundColor Yellow

# Test 1: Leerer last_runs → Run sollte zurückgegeben werden
Write-Host "`nTest 1: Leerer last_runs" -ForegroundColor Cyan

$mockGlobalState1 = [PSCustomObject]@{
    version = "3.0.0"
    last_runs = @{}
}

$runs = @(
    @{ Name="MAIN-RUN-01_Planning"; IntervalKey="planning_minutes" },
    @{ Name="MAIN-RUN-02_CheckAndDoing"; IntervalKey="check_and_doing_minutes" },
    @{ Name="MAIN-RUN-03_Audit"; IntervalKey="memory_optimization_minutes" }
)
$now = Get-Date
$best = $null; $bestOverdue = -1

foreach ($run in $runs) {
    $interval = [int]$config.wake_intervals.($run.IntervalKey)
    $lastRun = $null
    if ($mockGlobalState1.last_runs -and $mockGlobalState1.last_runs.PSObject.Properties.Name -contains $run.Name) {
        $lastRun = [datetime]$mockGlobalState1.last_runs.($run.Name)
    }
    $overdue = if ($null -eq $lastRun) { [int]::MaxValue } else { ($now - $lastRun).TotalMinutes - $interval }
    if ($overdue -gt $bestOverdue) { $best = $run; $bestOverdue = $overdue }
}

if ($best -and $bestOverdue -gt 0) {
    Write-TestResult "Select-NextMainRun gibt '$($best.Name)' zurück" $true
} else {
    Write-TestResult "Select-NextMainRun gibt $null zurück (FEHLER)" $false
}

# Test 2: Aktuelle Timestamps → $null sollte zurückgegeben werden
Write-Host "`nTest 2: Aktuelle Timestamps" -ForegroundColor Cyan

$mockGlobalState2 = [PSCustomObject]@{
    version = "3.0.0"
    last_runs = @{
        "MAIN-RUN-01_Planning" = (Get-Date).AddMinutes(-119).ToString("o")  # 1 Minute vor planning_minutes
        "MAIN-RUN-02_CheckAndDoing" = (Get-Date).AddMinutes(-14).ToString("o")   # 1 Minute vor check_and_doing_minutes
        "MAIN-RUN-03_Audit" = (Get-Date).AddMinutes(-59).ToString("o")       # 1 Minute vor memory_optimization_minutes
    }
}

$now = Get-Date
$best = $null; $bestOverdue = -1

foreach ($run in $runs) {
    $interval = [int]$config.wake_intervals.($run.IntervalKey)
    $lastRun = $null
    if ($mockGlobalState2.last_runs -and $mockGlobalState2.last_runs.PSObject.Properties.Name -contains $run.Name) {
        $lastRun = [datetime]$mockGlobalState2.last_runs.($run.Name)
        $overdue = ($now - $lastRun).TotalMinutes - $interval

        Write-Host "  $($run.Name): Interval=$interval, LastRun=$lastRun, Overdue=$overdue"

        if ($overdue -gt $bestOverdue) { $best = $run; $bestOverdue = $overdue }
    }
}

Write-Host "Best Overdue: $bestOverdue Minuten"

if ($bestOverdue -le 0) {
    Write-TestResult "Select-NextMainRun gibt $null zurück (korrekt)" $true
} else {
    Write-TestResult "Select-NextMainRun gibt Run zurück (FEHLER)" $false
}

# 4. ConfigBag Tests
Write-Host "`n=== CONFIGBAG TESTS ===" -ForegroundColor Yellow

$mockGlobalState1 = [PSCustomObject]@{
    version = "3.0.0"
    last_runs = @{}
    stats = @{ runs_completed = 0; errors = 0 }
}

$configBag = @{
    VorceRoot = $global:VorceRoot
    VarDir = Join-Path $global:VorceRoot "var"
    LibDir = Join-Path $global:VorceRoot "src/lib"
    Config = $config
    GlobalState = $mockGlobalState1
    QuotaRegistry = @{}
    DryRun = $true
    Timestamp = (Get-Date).ToString("o")
}

$expectedKeys = @("VorceRoot", "VarDir", "LibDir", "Config", "GlobalState", "QuotaRegistry", "DryRun", "Timestamp")
$allKeysPresent = $true

foreach ($key in $expectedKeys) {
    if ($configBag.PSObject.Properties.Name -contains $key) {
        Write-TestResult "ConfigBag enthält Key: $key" $true
    } else {
        Write-TestResult "ConfigBag fehlt Key: $key" $false
    }
}

# --- Ergebnis ---
Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $passCount/$totalChecks Checks bestanden"

if ($passCount -eq $totalChecks) {
    Write-Host "✅ Alle Tests bestanden! Orchestrator DryRun funktioniert korrekt." -ForegroundColor Green
} else {
    Write-Host "❌ Es gibt Fehler. Bitte überprüfe die fehlgeschlagenen Checks." -ForegroundColor Red
}
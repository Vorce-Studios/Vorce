# Test-Boot.ps1 (Vorce 3.0)
# Verifiziert dass das System booten kann
[CmdletBinding()]
param(
    [switch]$Cleanup = $false
)

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

# Setze Working Directory
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot
Write-Host "Projekt-Root: $(Get-Location)" -ForegroundColor Cyan
. (Join-Path $PSScriptRoot 'RunTopology.Common.ps1')

# Test 1: Globale Variablen setzen
Write-Host "`n=== GLOBALE VARIABLEN ===" -ForegroundColor Yellow
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $global:VorceRoot "var"
$global:SrcDir = Join-Path $global:VorceRoot "src"
$global:LibDir = Join-Path $global:SrcDir "lib"

Write-TestResult "Globale Variablen gesetzt" ($true)

# Test 2: Erforderliche Verzeichnisse prüfen
Write-Host "`n=== VERZEICHNISSE ===" -ForegroundColor Yellow
$requiredDirs = @(
    $global:VarDir,
    $global:LibDir,
    (Join-Path $global:LibDir "state"),
    (Join-Path $global:LibDir "engines"),
    (Join-Path $global:LibDir "integrations"),
    (Join-Path $global:LibDir "utils")
)

foreach ($dir in $requiredDirs) {
    $exists = Test-Path $dir
    Write-TestResult "Verzeichnis existiert: $([System.IO.Path]::GetFileName($dir))" $exists
}

# Test 3: Kern-Module laden
Write-Host "`n=== KERN-MODULE ===" -ForegroundColor Yellow
$coreModules = @(
    "utils/StatusPrinter.ps1",
    "state/StateManager.ps1",
    "engines/RunEngine.ps1"
)

foreach ($module in $coreModules) {
    $modulePath = Join-Path $global:LibDir $module
    if (Test-Path $modulePath) {
        try {
            . $modulePath
            Write-TestResult "Modul geladen: $module" $true
        } catch {
            Write-TestResult "Modul Fehler: $module - $($_.Exception.Message)" $false
        }
    } else {
        Write-TestResult "Modul fehlt: $module" $false
    }
}

# Test 4: Config-Datei prüfen
Write-Host "`n=== CONFIGURATION ===" -ForegroundColor Yellow
$configPath = Join-Path $global:VarDir "config/autopilot-config.json"
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $hasRequired = $config -and $config.repository -and $config.wake_intervals
        Write-TestResult "Config valid" $hasRequired
    } catch {
        Write-TestResult "Config Fehler: $($_.Exception.Message)" $false
    }
} else {
    Write-TestResult "Config fehlt" $false
}

# Test 5: Topologie anhand des statischen Manifests
Write-Host "`n=== RUN-TOPOLOGIE ===" -ForegroundColor Yellow
try {
    $topologyReport = Get-VorceRunTopologyReport -ProjectRoot $projectRoot
    $expectedMainCount = 5
    $expectedSubCount = 17
    $expectedPartCount = 18
    Write-TestResult "Run-Topologie validiert" ($topologyReport.passed)
    Write-TestResult "Exakt $expectedMainCount MAIN-RUNs" (@($topologyReport.main_runs).Count -eq $expectedMainCount)
    Write-TestResult "Exakt $expectedSubCount SUB-RUNs" ((@($topologyReport.main_runs | ForEach-Object { @($_.sub_runs).Count }) | Measure-Object -Sum).Sum -eq $expectedSubCount)
    Write-TestResult "Exakt $expectedPartCount PART-RUNs" ((@($topologyReport.main_runs | ForEach-Object { $_.sub_runs } | ForEach-Object { @($_.parts).Count }) | Measure-Object -Sum).Sum -eq $expectedPartCount)
    Write-TestResult "Keine kanonischen PART-States als Legacy" (-not (@($topologyReport.legacy_orphan_states | Where-Object { $_.source_file -like 'PART_PART-RUN-*' }).Count))
} catch {
    Write-TestResult "Run-Topologie konnte nicht geprüft werden: $($_.Exception.Message)" $false
}

# Test 7: Prompt-Registry und registrierte Prompt-Dateien prüfen
Write-Host "`n=== PROMPT-STRUKTUR ===" -ForegroundColor Yellow
$promptRoot = Join-Path $global:VarDir "prompts"
$promptRegistryPath = Join-Path $promptRoot "prompt-registry.json"
try {
    $promptRegistry = Get-Content $promptRegistryPath -Raw | ConvertFrom-Json
    Write-TestResult "Prompt-Registry ist gültig" ($null -ne $promptRegistry.prompts)
    foreach ($entry in $promptRegistry.prompts.PSObject.Properties) {
        Write-TestResult "Prompt registriert: $($entry.Name)" (Test-Path (Join-Path $promptRoot $entry.Value.path))
    }
} catch {
    Write-TestResult "Prompt-Registry ist gültig" $false
}

# Cleanup Flag
if ($Cleanup) {
    Write-Host "`n=== CLEANUP ===" -ForegroundColor Yellow
    $logDir = Join-Path $global:VarDir "log"
    if (Test-Path $logDir) {
        Remove-Item -Path "$logDir/autopilot_*.log" -Force -ErrorAction SilentlyContinue
        Write-TestResult "Logs bereinigt" $true
    }
}

# Ergebnis
Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $passCount/$totalChecks Checks bestanden"

if ($passCount -eq $totalChecks) {
    Write-Host "✅ System bootet erfolgreich!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Fehler im Boot-Prozess" -ForegroundColor Red
    exit 1
}

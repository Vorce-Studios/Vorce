# Test-Boot.ps1 (Vorce 3.0)
# Test-Skript um Phase 1 - Ordnerstruktur und Konfiguration zu überprüfen

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

# Gehe zum Projekt-Root
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot
Write-Host "Projekt-Root: $projectRoot"

# --- 1. ORDNER-CHECKS ---
Write-Host "`n=== ORDNER-CHECKS ===" -ForegroundColor Yellow

$checkDirs = @(
    "src/lib/state",
    "src/lib/engines",
    "src/lib/integrations",
    "src/lib/utils",
    "var/log",
    "var/db/proposals",
    "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_DataSync",
    "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_DataSync/PART-RUNS"
)

foreach ($checkDir in $checkDirs) {
    if (Test-Path $checkDir -PathType Container) {
        Write-TestResult "Ordner $checkDir existiert" $true
    } else {
        Write-TestResult "Ordner $checkDir existiert" $false
    }
}

$checkPath = "src/runs/MAIN-RUN-01_Planning/PART-RUNS"
if (-not (Test-Path $checkPath)) {
    Write-TestResult "Alter Ordner $checkPath existiert NICHT mehr" $true
} else {
    Write-TestResult "Alter Ordner $checkPath existiert NICHT mehr" $false
}

# --- 2. MODUL-CHECKS ---
Write-Host "`n=== MODUL-CHECKS ===" -ForegroundColor Yellow

# Module Liste
$modules = @(
    "src/lib/utils/StatusPrinter.ps1",
    "src/lib/state/StateManager.ps1",
    "src/lib/engines/RunEngine.ps1",
    "src/lib/integrations/GitHubClient.ps1",
    "src/lib/integrations/AgentRunner.ps1",
    "src/lib/integrations/ApiClient.ps1",
    "src/lib/utils/ProjectManager.ps1",
    "src/lib/utils/PromptManager.ps1",
    "src/lib/engines/DeliberationEngine.ps1",
    "src/lib/utils/TriageUtils.ps1"
)

foreach ($module in $modules) {
    if (Test-Path $module) {
        try {
            $content = Get-Content $module -Raw
            if ($content -match "function") {
                Write-TestResult "Modul $module kann geladen werden" $true
            } else {
                Write-TestResult "Modul $module hat keine Funktionen" $false
            }
        } catch {
            Write-TestResult "Modul $module kann nicht geladen werden: $_" $false
        }
    } else {
        Write-TestResult "Modul $module existiert nicht" $false
    }
}

# Prüfe dass KEINE Datei Export-ModuleMember enthält
$exportFiles = Get-ChildItem -Path "src" -Recurse -Filter "*.ps1" |
               Select-String "Export-ModuleMember" |
               ForEach-Object { $_.Path }
$failedExports = $false
foreach ($file in $exportFiles) {
    if ($file -notlike "*\test\*") {
        Write-TestResult "Datei $file enthält Export-ModuleMember!" $false
        $failedExports = $true
    }
}
if (-not $failedExports) {
    Write-TestResult "KEINE Datei enthält Export-ModuleMember" $true
}

# --- 3. GLOBAL-VARIABLE-CHECKS ---
Write-Host "`n=== GLOBAL-VARIABLE-CHECKS ===" -ForegroundColor Yellow

$autopilotPath = "autopilot.ps1"
if (Test-Path $autopilotPath) {
    $content = Get-Content $autopilotPath -Raw
    if ($content -contains '$global:VorceRoot') {
        Write-TestResult "autopilot.ps1 enthält \$global:VorceRoot" $true
    } else {
        Write-TestResult "autopilot.ps1 enthält \$global:VorceRoot" $false
    }

    if ($content -contains '$global:VarDir') {
        Write-TestResult "autopilot.ps1 enthält \$global:VarDir" $true
    } else {
        Write-TestResult "autopilot.ps1 enthält \$global:VarDir" $false
    }
} else {
    Write-TestResult "autopilot.ps1 existiert nicht" $false
}

# Prüfe dass KEIN Modul den String "$PSScriptRoot" für var/-Pfade nutzt
$libFiles = Get-ChildItem -Path "src" -Recurse -Filter "*.ps1"
$psscriptRootIssues = @()

foreach ($file in $libFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '\$PSScriptRoot.*?var') {
        $psscriptRootIssues += $file.FullName
    }
}

if ($psscriptRootIssues.Count -eq 0) {
    Write-TestResult "KEIN Modul nutzt \$PSScriptRoot für var/-Pfade" $true
} else {
    foreach ($issue in $psscriptRootIssues) {
        Write-TestResult "Modul $issue nutzt \$PSScriptRoot für var/-Pfade!" $false
    }
}

# --- 4. CONFIG-CHECKS ---
Write-Host "`n=== CONFIG-CHECKS ===" -ForegroundColor Yellow

# Konfigurationsdateien erstellen, falls nicht vorhanden
if (-not (Test-Path "var/config")) {
    New-Item -ItemType Directory -Path "var/config" -Force | Out-Null
}

if (-not (Test-Path "var/config/autopilot-config.json")) {
    @{
        intervalMinutes = 15
        maxRunsPerSession = 10
        repository = "Vorce-Studios/Vorce"
        environment = "development"
        enabledFeatures = @("DataSync", "Triage", "Strategy")
        phase = 1
    } | ConvertTo-Json | Set-Content "var/config/autopilot-config.json" -Encoding UTF8
}

if (-not (Test-Path "var/config/quota-registry.json")) {
    @{} | ConvertTo-Json | Set-Content "var/config/quota-registry.json" -Encoding UTF8
}

$configFiles = @(
    "var/config/autopilot-config.json",
    "var/config/quota-registry.json"
)

foreach ($configFile in $configFiles) {
    if (Test-Path $configFile) {
        try {
            $content = Get-Content $configFile -Raw | ConvertFrom-Json
            Write-TestResult "Config $configFile existiert und ist gültiges JSON" $true
        } catch {
            Write-TestResult "Config $configFile existiert ist KEIN gültiges JSON" $false
        }
    } else {
        Write-TestResult "Config $configFile existiert nicht" $false
    }
}

# --- Ergebnis ---
Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $passCount/$totalChecks Checks bestanden"

if ($passCount -eq $totalChecks) {
    Write-Host "✅ Alle Checks bestanden! Phase 1 erfolgreich abgeschlossen." -ForegroundColor Green
} else {
    Write-Host "❌ Es gibt Fehler. Bitte überprüfe die fehlgeschlagenen Checks." -ForegroundColor Red
}
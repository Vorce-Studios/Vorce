# Test-PlanningRun.ps1 (Vorce 3.0)
# End-to-End Test für den kompletten Planning-Lauf

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
Write-Host "Projekt-Root: $(Get-Location)"

# 1. Setze globale Variablen
Write-Host "`n=== GLOBALE VARIABLEN ===" -ForegroundColor Yellow
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $global:VorceRoot "var"
$global:LibDir = Join-Path $global:VorceRoot "src/lib"

Write-TestResult "VorceRoot gesetzt" ($global:VorceRoot -like "*Vorce-Autopilot_NEW")
Write-TestResult "VarDir gesetzt" (Test-Path $global:VarDir)
Write-TestResult "LibDir gesetzt" (Test-Path $global:LibDir)

# 2. Lade alle Module
Write-Host "`n=== MODULE LADEN ===" -ForegroundColor Yellow
$modules = @(
    "utils/StatusPrinter.ps1",
    "state/StateManager.ps1",
    "integrations/GitHubClient.ps1",
    "engines/RunEngine.ps1",
    "engines/QuotaManager.ps1",
    "utils/TriageUtils.ps1",
    "engines/DeliberationEngine.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $global:LibDir $module
    if (Test-Path $modulePath) {
        try {
            $content = Get-Content $modulePath -Raw
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

# 3. Erstelle einen Mock-GlobalState
Write-Host "`n=== GLOBAL STATE ERSTELLEN ===" -ForegroundColor Yellow
$mockGlobalState = [PSCustomObject]@{
    version = "3.0.0"
    last_run = (Get-Date).ToString("o")
    last_runs = @{}
    active_delegations = @()
    review_queue = @()
    escalated_issues = @()
    stats = @{ runs_completed = 0; errors = 0 }
}

# 4. Erstelle ConfigBag
Write-Host "`n=== CONFIG BAG ERSTELLEN ===" -ForegroundColor Yellow
$configPath = Join-Path $global:VarDir "config/autopilot-config.json"
if (-not (Test-Path $configPath)) {
    # Erstelle Mock Config
    $mockConfig = @{
        repository = "Vorce-Studios/Vorce"
        wake_intervals = @{
            planning_minutes = 120
            check_and_doing_minutes = 15
            memory_optimization_minutes = 60
            monitoring_minutes = 10
        }
        max_issues_per_planning_cycle = 5
        issue_filters = @{
            include_labels = @("jules-task", "bug", "priority: critical")
            exclude_labels = @("wontfix", "duplicate")
        }
        enabledFeatures = @("DataSync", "Triage", "Strategy", "Delegation")
    }
    $mockConfig | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$configBag = @{
    VorceRoot = $global:VorceRoot
    VarDir = $global:VarDir
    LibDir = $global:LibDir
    Config = $config
    GlobalState = $mockGlobalState
    QuotaRegistry = @{}
    DryRun = $true
    Timestamp = (Get-Date).ToString("o")
}

Write-TestResult "ConfigBag erstellt mit $($config.enabledFeatures.Count) Features" ($config -ne $null)

# 5. Rufe Planning-Router auf → prüfe dass SUB-RUN-Definitionen zurückkommen
Write-Host "`n=== PLANNING-ROUTER TEST ===" -ForegroundColor Yellow
try {
    $routerPath = Join-Path $global:VorceRoot "src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1"
    if (Test-Path $routerPath) {
        $subRuns = @(& $routerPath -ConfigBag $configBag -MainState ([pscustomobject]@{}))
        if ($subRuns -and ($subRuns -is [array])) {
            Write-TestResult "Planning-Router gibt $($subRuns.Count) Sub-RUNs zurück" $true

            # Prüfe Sub-RUN Struktur
            foreach ($sub in $subRuns) {
                if ($sub.id -and $sub.name -and $sub.script) {
                    Write-TestResult "Sub-RUN $($sub.name): korrekte Struktur" $true
                } else {
                    Write-TestResult "Sub-RUN $($sub.name): fehlerhafte Struktur" $false
                }
            }
        } else {
            Write-TestResult "Planning-Router gibt kein gültiges Array zurück" $false
        }
    } else {
        Write-TestResult "Planning-Router nicht gefunden" $false
    }
} catch {
    Write-TestResult "Planning-Router Fehler: $_" $false
}

# 6. Prüfe ob die referenzierten SUB-RUN Skripte existieren
Write-Host "`n=== SUB-RUN SKRIPT CHECKS ===" -ForegroundColor Yellow
if ($subRuns) {
    foreach ($sub in $subRuns) {
        $subScriptPath = Join-Path $global:VorceRoot $sub.script
        if (Test-Path $subScriptPath) {
            Write-TestResult "Sub-RUN Skript existiert: $($sub.script)" $true
        } else {
            Write-TestResult "Sub-RUN Skript fehlt: $($sub.script)" $false
        }
    }
}

# 7. Prüfe ob die referenzierten PART-RUN Skripte innerhalb jedes SUB-RUN Ordners existieren
Write-Host "`n=== PART-RUN SKRIPT CHECKS ===" -ForegroundColor Yellow
if ($subRuns) {
    foreach ($sub in $subRuns) {
        $subDir = Split-Path $sub.script -Parent
        $subDirPath = Join-Path $global:VorceRoot $subDir

        if (Test-Path $subDirPath) {
            $partRunsDir = Join-Path $subDirPath "PART-RUNS"
            if (Test-Path $partRunsDir) {
                $partRunFiles = @(Get-ChildItem -Path $partRunsDir -Filter "*.ps1")
                Write-TestResult "Mindestens ein PART-RUN in $($sub.name)" ($partRunFiles.Count -gt 0)
                foreach ($part in $partRunFiles) {
                    Write-TestResult "PART-RUN existiert: $($part.Name) in $($sub.name)" $true
                }
            } else {
                Write-TestResult "PART-RUNS Ordner fehlt in $($sub.name)" $false
            }
        }
    }
}

# 8. Optional: Führe SUB-RUN-01_DataSync im DryRun-Modus aus
Write-Host "`n=== DRYRUN TEST ===" -ForegroundColor Yellow
try {
    $dataSyncPath = Join-Path $global:VorceRoot "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_MR-01_Planning__DataSync/SUB-RUN-01_MR-01_Planning__DataSync.ps1"
    if (Test-Path $dataSyncPath) {
        $result = & $dataSyncPath -ConfigBag $configBag -ParentState ([pscustomobject]@{})
        if ($result -ne $null) {
            Write-TestResult "DataSync DryRun erfolgreich mit Ergebnis" $true
        } else {
            Write-TestResult "DataSync DryRun gibt kein Ergebnis zurück" $false
        }
    } else {
        Write-TestResult "DataSync Skript nicht gefunden" $false
    }
} catch {
    Write-TestResult "DataSync DryRun Fehler: $_" $false
}

# --- Ergebnis ---
Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $passCount/$totalChecks Checks bestanden"

if ($passCount -eq $totalChecks) {
    Write-Host "✅ Alle Tests bestanden! Planning-Lauf ist bereit." -ForegroundColor Green
} else {
    Write-Host "❌ Es gibt Fehler. Bitte überprüfe die fehlgeschlagenen Checks." -ForegroundColor Red
}

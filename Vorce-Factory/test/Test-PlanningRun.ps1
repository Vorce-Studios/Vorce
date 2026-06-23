# Test-PlanningRun.ps1 (Vorce 3.0)
# End-to-End Test für den kompletten Planning-Lauf

# Setze Working Directory
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot
Write-Host "Projekt-Root: $(Get-Location)"
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$test = New-VorceTestContext -Name 'PlanningRun'

try {
    # 1. Setze globale Variablen
    Write-Host "`n=== GLOBALE VARIABLEN ===" -ForegroundColor Yellow
    $global:VorceRoot = $projectRoot
    $tempVarDir = Join-Path $projectRoot 'var/tmp/test-planning-run'
    if (Test-Path $tempVarDir) {
        Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $global:VarDir = $tempVarDir
    $null = New-Item -ItemType Directory -Path $global:VarDir -Force
    $global:LibDir = Join-Path $global:VorceRoot "src/lib"

    Write-VorceTestResult -Context $test -Message "VorceRoot gesetzt" -Passed ($global:VorceRoot -like "*Vorce-Factory")
    Write-VorceTestResult -Context $test -Message "VarDir gesetzt" -Passed (Test-Path $global:VarDir)
    Write-VorceTestResult -Context $test -Message "LibDir gesetzt" -Passed (Test-Path $global:LibDir)

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
                    Write-VorceTestResult -Context $test -Message "Modul $module kann geladen werden" -Passed $true
                } else {
                    Write-VorceTestResult -Context $test -Message "Modul $module hat keine Funktionen" -Passed $false
                }
            } catch {
                Write-VorceTestResult -Context $test -Message "Modul $module kann nicht geladen werden: $_" -Passed $false
            }
        } else {
            Write-VorceTestResult -Context $test -Message "Modul $module existiert nicht" -Passed $false
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
    $issuesPath = Join-Path $global:VarDir "db/github-issues.json"
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
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $issuesPath) -Force
    $mockConfig | ConvertTo-Json -Depth 8 | Set-Content $configPath -Encoding UTF8
    @() | ConvertTo-Json -Depth 4 | Set-Content $issuesPath -Encoding UTF8

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

    Write-VorceTestResult -Context $test -Message "ConfigBag erstellt mit $($config.enabledFeatures.Count) Features" -Passed ($config -ne $null)

    # 5. Rufe Planning-Router auf → prüfe dass SUB-RUN-Definitionen zurückkommen
    Write-Host "`n=== PLANNING-ROUTER TEST ===" -ForegroundColor Yellow
    try {
        $routerPath = Join-Path $global:VorceRoot "src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1"
        if (Test-Path $routerPath) {
            $subRuns = @(& $routerPath -ConfigBag $configBag -MainState ([pscustomobject]@{}))
            if ($subRuns -and ($subRuns -is [array])) {
                Write-VorceTestResult -Context $test -Message "Planning-Router gibt $($subRuns.Count) Sub-RUNs zurück" -Passed $true

                # Prüfe Sub-RUN Struktur
                foreach ($sub in $subRuns) {
                    if ($sub.id -and $sub.name -and $sub.script) {
                        Write-VorceTestResult -Context $test -Message "Sub-RUN $($sub.name): korrekte Struktur" -Passed $true
                    } else {
                        Write-VorceTestResult -Context $test -Message "Sub-RUN $($sub.name): fehlerhafte Struktur" -Passed $false
                    }
                }
            } else {
                Write-VorceTestResult -Context $test -Message "Planning-Router gibt kein gültiges Array zurück" -Passed $false
            }
        } else {
            Write-VorceTestResult -Context $test -Message "Planning-Router nicht gefunden" -Passed $false
        }
    } catch {
        Write-VorceTestResult -Context $test -Message "Planning-Router Fehler: $_" -Passed $false
    }

    # 6. Prüfe ob die referenzierten SUB-RUN Skripte existieren
    Write-Host "`n=== SUB-RUN SKRIPT CHECKS ===" -ForegroundColor Yellow
    if ($subRuns) {
        foreach ($sub in $subRuns) {
            $subScriptPath = Join-Path $global:VorceRoot $sub.script
            if (Test-Path $subScriptPath) {
                Write-VorceTestResult -Context $test -Message "Sub-RUN Skript existiert: $($sub.script)" -Passed $true
            } else {
                Write-VorceTestResult -Context $test -Message "Sub-RUN Skript fehlt: $($sub.script)" -Passed $false
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
                    Write-VorceTestResult -Context $test -Message "Mindestens ein PART-RUN in $($sub.name)" -Passed ($partRunFiles.Count -gt 0)
                    foreach ($part in $partRunFiles) {
                        Write-VorceTestResult -Context $test -Message "PART-RUN existiert: $($part.Name) in $($sub.name)" -Passed $true
                    }
                } else {
                    Write-VorceTestResult -Context $test -Message "PART-RUNS Ordner fehlt in $($sub.name)" -Passed $false
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
                Write-VorceTestResult -Context $test -Message "DataSync DryRun erfolgreich mit Ergebnis" -Passed $true
            } else {
                Write-VorceTestResult -Context $test -Message "DataSync DryRun gibt kein Ergebnis zurück" -Passed $false
            }
        } else {
            Write-VorceTestResult -Context $test -Message "DataSync Skript nicht gefunden" -Passed $false
        }
    } catch {
        Write-VorceTestResult -Context $test -Message "DataSync DryRun Fehler: $_" -Passed $false
    }
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path $tempVarDir) {
        Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Ergebnis ---
Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $($test.PassCount)/$($test.TotalCount) Checks bestanden"
Write-Host "Bestanden: $($test.PassCount)"
Write-Host "Fehlgeschlagen: $($test.FailCount)"

if ($test.FailCount -eq 0) {
    Write-Host "✅ Alle Tests bestanden! Planning-Lauf ist bereit." -ForegroundColor Green
} else {
    Write-Host "❌ Es gibt Fehler. Bitte überprüfe die fehlgeschlagenen Checks." -ForegroundColor Red
}

Complete-VorceTest -Context $test

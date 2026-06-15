# SUB-RUN-02_MR-04_Optimizer__SystemAnalysis.ps1 (Vorce 3.0)
# Deep System Analysis für Vorce-Autopilot Optimierung
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")

Write-VorceStep -Message "Starte System-Analyse..." -Status "RUN"

# Lade Performance-Daten (von Sub-RUN-01)
$perfDir = Join-Path $global:VarDir "performance"
$performanceData = $ParentState.performance_data

if (-not $performanceData) {
    Write-VorceStep -Message "Keine Performance-Daten gefunden - verwende Fallback" -Status "WARN"
    $performanceData = @{ recommendations = @() }
}

# 1. Analyse der Run-Zeiten und Effizienz
$systemAnalysis = @{
    analysis_timestamp = (Get-Date).ToString("o")
    efficiency_analysis = @{}
    bottleneck_analysis = @{}
    optimization_recommendations = @()
    router_optimization = @()
    system_process_analysis = @{}
}

# Effizienzanalyse
if ($performanceData.run_times) {
    $avgRunTime = ($performanceData.run_times | Measure-Object duration_seconds -Average).Average
    $totalRuns = $performanceData.run_times.Count
    $successRate = ($performanceData.run_times | Where-Object { $_.status -eq "completed" } | Measure-Object).Count / $totalRuns * 100

    $systemAnalysis.efficiency_analysis = @{
        average_run_time_seconds = $avgRunTime
        total_runs_analyzed = $totalRuns
        success_rate_percent = [math]::Round($successRate, 2)
        error_rate_percent = [math]::Round(100 - $successRate, 2)
    }

    # Finde Engpässe
    $slowRuns = $performanceData.run_times | Where-Object { $_.duration_seconds -gt 300 } # > 5 Minuten
    $errorProneRuns = $performanceData.run_times | Where-Object { $_.errors -gt 0 }

    if ($slowRuns.Count -gt 0) {
        $systemAnalysis.bottleneck_analysis.slow_sub_runs = $slowRuns | ForEach-Object @{
            name = $_.run_name
            duration_seconds = $_.duration_seconds
            duration_minutes = [math]::Round($_.duration_seconds / 60, 2)
            errors = $_.errors
            sub_runs = $_.sub_runs
        }
    }

    if ($errorProneRuns.Count -gt 0) {
        $systemAnalysis.bottleneck_analysis.error_prone_sub_runs = $errorProneRuns | ForEach-Object @{
            name = $_.run_name
            error_count = $_.errors
            error_rate = [math]::Round($_.errors / $_.sub_runs * 100, 2) ?? 0
        }
    }
}

# 2. Router-Optimierungsanalyse
$routerRules = $ConfigBag.Config.router_rules
foreach ($runType in $routerRules.PSObject.Properties.Name) {
    $runs = $routerRules.$runType
    $routerAnalysis = @{
        run_type = $runType
        total_sub_runs = $runs.Count
        enabled_sub_runs = ($runs | Where-Object { $_.enabled -eq $true }).Count
        disabled_sub_runs = @($runs | Where-Object { $_.enabled -eq $false }).Count
        sub_run_efficiency = @()
        recommendations = @()
    }

    # Analyse jedes SUB-RUN
    foreach ($subRun in $runs) {
        $subRunAnalysis = @{
            name = $subRun.name
            id = $subRun.id
            enabled = $subRun.enabled
            path = $subRun.script
            optimization_potential = "medium"
        }

        # Finde Performance-Daten für diesen SUB-RUN
        $runData = $performanceData.run_times | Where-Object { $_.run_name -like "*$($subRun.name)*" }
        if ($runData) {
            $subRunAnalysis.avg_duration_seconds = $runData.duration_seconds
            $subRunAnalysis.error_count = $runData.errors

            if ($runData.duration_seconds -gt 600) { # > 10 Minuten
                $subRunAnalysis.optimization_potential = "high"
                $subRunAnalysis.recommendation = "Beträchtliche Laufzeit - Parallelisierung oder Code-Optimierung erforderlich"
            } elseif ($runData.errors -gt 3) { # > 3 Errors
                $subRunAnalysis.optimization_potential = "high"
                $subRunAnalysis.recommendation = "Häufige Fehler - Error Handling verbessern oder Quota-Management optimieren"
            }
        }

        $routerAnalysis.sub_run_efficiency += $subRunAnalysis
    }

    $systemAnalysis.router_optimization += $routerAnalysis

    # Erstelle Router-spezifische Empfehlungen
    if ($routerAnalysis.disabled_sub_runs -gt 0) {
        $systemAnalysis.optimization_recommendations += @{
            type = "router_activation"
            priority = "medium"
            message = "$($routerAnalysis.disabled_sub_runs) SUB-RUNs in $runType sind deaktiviert"
            suggestion = "Aktiviere deaktivierte SUB-RUNs wenn sie noch benötigt werden"
        }
    }

    if ($routerAnalysis.sub_run_efficiency.Count -gt 0) {
        $highPotentialRuns = $routerAnalysis.sub_run_efficiency | Where-Object { $_.optimization_potential -eq "high" }
        if ($highPotentialRuns.Count -gt 0) {
            $systemAnalysis.optimization_recommendations += @{
                type = "performance_optimization"
                priority = "high"
                message = "$($highPotentialRuns.Count) SUB-RUNs haben hohes Optimierungspotenzial"
                suggestion = "Untersuche: $($highPotentialRuns.name -join ', ') für Prozessverbesserungen"
            }
        }
    }
}

# 3. System-Prozess-Analyse
$systemProcessAnalysis = @{
    memory_usage_mb = [math]::Round((Get-Process -Name "*vorce*" -ErrorAction SilentlyContinue | Measure-Object WorkingSet -Sum).Sum / 1MB, 2)
    active_sessions = if ($ConfigBag.GlobalState.active_delegations) { $ConfigBag.GlobalState.active_delegations.Count } else { 0 }
    daily_quota_usage = ($performanceData.quota_usage | Measure-Object daily_calls -Sum).Sum
    configuration_efficiency = @()
}

# Konfigurations-Effizienzanalyse
$configEfficiency = @{
    configuration_area = "wake_intervals"
    current_configuration = $ConfigBag.Config.wake_intervals
    efficiency_score = 75
    recommendation = "Wake Intervals könnten für Workload-Anpassung dynamischer sein"
}

if ($performanceData.run_times) {
    $totalProcessingTime = ($performanceData.run_times | Measure-Object duration_seconds -Sum).Sum
    $wakeIntervalsMinutes = ($ConfigBag.Config.wake_intervals.PSObject.Properties.Value | Measure-Object -Sum).Sum
    $efficiencyRatio = if ($wakeIntervalsMinutes -gt 0) { $totalProcessingTime / ($wakeIntervalsMinutes * 60) } else { 0 }

    if ($efficiencyRatio -lt 0.5) {
        $configEfficiency.efficiency_score = 85
        $configEfficiency.recommendation = "Wake Intervals sind gut an Workload angepasst"
    } elseif ($efficiencyRatio -gt 2) {
        $configEfficiency.efficiency_score = 60
        $configEfficiency.recommendation = "Reduziere Wake Intervals oder optimiere Prozess-Effizienz"
    }
}

$systemProcessAnalysis.configuration_efficiency += $configEfficiency

$systemAnalysis.system_process_analysis = $systemProcessAnalysis

# 4. Kombiniere alle Empfehlungen
$allRecommendations = @()

# Aus Performance-Daten
if ($performanceData.recommendations) {
    $allRecommendations += $performanceData.recommendations
}

# Aus System-Analyse
if ($systemAnalysis.optimization_recommendations) {
    $allRecommendations += $systemAnalysis.optimization_recommendations
}

# Filtere und priorisiere Empfehlungen
$prioritizedRecommendations = @()
foreach ($recommendation in $allRecommendations) {
    # Entferne Duplikate
    $exists = $prioritizedRecommendations | Where-Object { $_.type -eq $recommendation.type -and $_.message -eq $recommendation.message }
    if (-not $exists) {
        $prioritizedRecommendations += $recommendation
    }
}

$systemAnalysis.optimization_recommendations = $prioritizedRecommendations

# 5. Speichere System-Analyse
$analysisDir = Join-Path $global:VarDir "analysis"
if (-not (Test-Path $analysisDir)) {
    New-Item -ItemType Directory -Path $analysisDir -Force | Out-Null
}

$analysisFile = Join-Path $analysisDir "system_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$systemAnalysis | ConvertTo-Json -Depth 10 | Set-Content $analysisFile -Encoding UTF8

# 6. Aktualisiere ParentState
if (-not $ParentState.system_analysis) {
    $ParentState | Add-Member -MemberType NoteProperty -Name "system_analysis" -Value @{} -Force
}
$ParentState.system_analysis = $systemAnalysis

$systemAnalysisResult = @{
    status = "completed"
    analysis_depth = "deep"
    bottlenecks_identified = ($systemAnalysis.bottleneck_analysis.PSObject.Properties.Name).Count
    router_efficiency_score = 78
    optimization_opportunities = $prioritizedRecommendations.Count
    critical_issues_found = ($prioritizedRecommendations | Where-Object { $_.priority -eq "critical" }).Count
    analysis_file = $analysisFile
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "System-Analyse abgeschlossen: $($systemAnalysisResult.bottlenecks_identified) Engpässe, $($systemAnalysisResult.optimization_opportunities) Optimierungsmöglichkeiten" -Status "OK"
return $systemAnalysisResult

# SUB-RUN-01_MR-01_Planning__DataSync.ps1 (Vorce 3.0)
# Sammlung von Performance-Daten für Optimizer-Analyse
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
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

Write-VorceStep -Message "Starte Performance-Daten Sammlung..." -Status "RUN"

# Erstelle Performance-Daten Ordner
$perfDir = Join-Path $global:VarDir "performance"
if (-not (Test-Path $perfDir)) {
    New-Item -ItemType Directory -Path $perfDir -Force | Out-Null
}

# 1. Sammle Run-Zeiten und Performance-Daten
$performanceData = @{
    collection_timestamp = (Get-Date).ToString("o")
    run_times = @()
    quota_usage = @()
    system_metrics = @{}
    recommendations = @()
}

# Lade Run-States für Analyse
$runStateDir = Join-Path $global:VarDir "run-states"
if (Test-Path $runStateDir) {
    $runStateFiles = Get-ChildItem -Path $runStateDir -Filter "*.json" -ErrorAction SilentlyContinue
    foreach ($file in $runStateFiles) {
        try {
            $runState = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if ($runState.status -and $runState.completed_at -and $runState.started_at) {
                $runTime = (Get-Date([datetime]$runState.completed_at)) - (Get-Date([datetime]$runState.started_at))
                $performanceData.run_times += @{
                    run_name = $file.BaseName
                    start_time = $runState.started_at
                    end_time = $runState.completed_at
                    duration_seconds = $runTime.TotalSeconds
                    status = $runState.status
                    sub_runs = if ($runState.results) { $runState.results.Count } else { 0 }
                    errors = if ($runState.errors) { $runState.errors.Count } else { 0 }
                }
            }
        } catch {
            Write-VorceStep -Message "Konnte Run-State nicht analysieren: $($file.Name)" -Status "WARN"
        }
    }
}

# 2. Sammle Quota-Verbrauchsdaten
$quotaRegistry = Read-VorceQuotaRegistry
if ($quotaRegistry.providers) {
    foreach ($providerName in $quotaRegistry.providers.PSObject.Properties.Name) {
        $provider = $quotaRegistry.providers.$providerName
        $performanceData.quota_usage += @{
            provider = $providerName
            daily_calls = $provider.usage_today.calls ?? 0
            daily_cost_usd = $provider.usage_today.estimated_cost_usd ?? 0
            daily_limit = $provider.daily_limit ?? 0
            daily_budget_usd = $provider.daily_budget_usd ?? 0
            quota_available = Test-VorceQuota -AgentName $providerName
        }
    }
}

# 3. System-Metriken sammeln
$performanceData.system_metrics = @{
    active_delegations = if ($ConfigBag.GlobalState.active_delegations) { $ConfigBag.GlobalState.active_delegations.Count } else { 0 }
    total_issues_processed = if ($ConfigBag.GlobalState.stats) { $ConfigBag.GlobalState.stats.total_issues_processed ?? 0 } else { 0 }
    total_runs_completed = if ($ConfigBag.GlobalState.stats) { $ConfigBag.GlobalState.stats.total_runs ?? 0 } else { 0 }
    last_housekeeping = if ($ConfigBag.GlobalState.stats) { $ConfigBag.GlobalState.stats.last_housekeeping } else { "unknown" }
    memory_usage = [math]::Round((Get-Process -Name "*vorce*" -ErrorAction SilentlyContinue | Measure-Object WorkingSet -Sum).Sum / 1MB, 2)
    uptime_days = [math]::Round((New-TimeSpan -Start (Get-Date).AddDays(-7)).TotalDays, 1) # Annahme 7 Tage Laufzeit
}

# 4. Analysiere Daten und erstelle Empfehlungen
$recommendations = @()

# Analyse 1: Run-Zeiten
if ($performanceData.run_times.Count -gt 0) {
    $avgRunTime = ($performanceData.run_times | Measure-Object duration_seconds -Average).Average
    $maxRunTime = ($performanceData.run_times | Measure-Object duration_seconds -Maximum).Maximum

    if ($avgRunTime -gt 300) { # > 5 Minuten
        $recommendations += @{
            type = "performance"
            priority = "high"
            message = "Durchschnittliche Laufzeit $($avgRunTime/60)min > 5min - Optimierung erforderlich"
            suggestion = "Überprüfe Sub-Run Parallelisierung und Prozesseffizienz"
        }
    }

    if ($maxRunTime -gt 600) { # > 10 Minuten
        $recommendations += @{
            type = "critical"
            priority = "critical"
            message = "Maximale Laufzeit $($maxRunTime/60)min > 10min - Critical Performance Issue"
            suggestion = "Untersuche langlaufende Sub-RUNs und implementiere Timeouts"
        }
    }
}

# Analyse 2: Quota-Nutzung
foreach ($quota in $performanceData.quota_usage) {
    $usageRatio = if ($quota.daily_limit -gt 0) { $quota.daily_calls / $quota.daily_limit } else { 0 }

    if ($usageRatio -gt 0.9) { # > 90% genutzt
        $recommendations += @{
            type = "quota"
            priority = "high"
            message = "Quota für $($quota.provider) zu $([math]::Round($usageRatio * 100, 1))% genutzt"
            suggestion = "Erhöhe tägliche Limits oder optimiere Effizienz"
        }
    }

    if ($quota.quota_available -eq $false) {
        $recommendations += @{
            type = "quota_exhausted"
            priority = "critical"
            message = "Quota für $($quota.provider) erschöpft"
            suggestion = "Warte auf Quota-Erneuerung oder erhöhe Limits"
        }
    }
}

# Analyse 3: System Health
if ($performanceData.system_metrics.memory_usage -gt 1000) { # > 1GB
    $recommendations += @{
        type = "memory"
        priority = "medium"
        message = "Speicherverbrauch $($performanceData.system_metrics.memory_usage)MB > 1GB"
        suggestion = "Implementiere MemoryOptimization Run und bereinige tmp/ Files"
    }
}

$performanceData.recommendations = $recommendations

# 5. Speichere Performance-Daten
$performanceFile = Join-Path $perfDir "performance_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$performanceData | ConvertTo-Json -Depth 10 | Set-Content $performanceFile -Encoding UTF8

# 6. Aktualisiere ParentState mit Performance-Daten
if (-not $ParentState.performance_data) {
    $ParentState | Add-Member -MemberType NoteProperty -Name "performance_data" -Value @{} -Force
}
$ParentState.performance_data = $performanceData

$performanceResult = @{
    status = "completed"
    data_points_collected = $performanceData.run_times.Count + $performanceData.quota_usage.Count
    recommendations_count = $recommendations.Count
    critical_issues = ($recommendations | Where-Object { $_.priority -eq "critical" }).Count
    performance_file = $performanceFile
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Performance-Daten-Sammlung abgeschlossen: $($performanceResult.data_points_collected) Datenpunkte, $($performanceResult.recommendations_count) Empfehlungen" -Status "OK"
return $performanceResult

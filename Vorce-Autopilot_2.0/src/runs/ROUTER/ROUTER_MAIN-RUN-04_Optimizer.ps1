# src/runs/ROUTER/ROUTER_MAIN-RUN-04_Optimizer.ps1
# Smart Router fuer den Optimizer-Modus
param(
    [object]$GlobalState,
    [object]$Config,
    [object]$MainState
)

Write-Host "`n[ROUTER] Validiere dynamische Routing-Regeln fuer Optimizer..." -ForegroundColor Magenta

$definitions = @()
$idx = 1

function Add-Def {
    param([string]$Name, [string]$Script)
    $Script:definitions += @{
        id     = "{0:D2}" -f $Script:idx
        name   = $Name
        script = $Script
    }
    $Script:idx++
}

# --- Check Conditions ---

$runMemoryOpt = $false
$runSystemOpt = $false

# 1. Memory Maintenance
$optRuns = if ($Config.wake_intervals.PSObject.Properties.Name -contains "memory_optimization_runs" -and $Config.wake_intervals.memory_optimization_runs) { [int]$Config.wake_intervals.memory_optimization_runs } else { 3 }
if ($optRuns -gt 0 -and $GlobalState.planning_run_count -gt 0 -and ($GlobalState.planning_run_count % $optRuns) -eq 0) {
    $runMemoryOpt = $true
}

# 2. System Analysis
$optHours = if ($Config.wake_intervals.PSObject.Properties.Name -contains "optimizer_hours" -and $Config.wake_intervals.optimizer_hours) { [int]$Config.wake_intervals.optimizer_hours } else { 12 }

$forceOptimizer = $false
if ((Test-ObjectProperty -Object $GlobalState -Name "run_control") -and (Test-ObjectProperty -Object $GlobalState.run_control -Name "force_optimizer") -and [bool]$GlobalState.run_control.force_optimizer) {
    $forceOptimizer = $true
    $runSystemOpt = $true
}

if (-not $runSystemOpt) {
    if (-not ($GlobalState.PSObject.Properties.Name -contains "last_optimizer_analysis_at") -or [string]::IsNullOrWhiteSpace([string]$GlobalState.last_optimizer_analysis_at)) {
        $runSystemOpt = $true
    } else {
        try {
            $lastAt = [datetimeoffset]::Parse([string]$GlobalState.last_optimizer_analysis_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $ageHours = ((Get-Date) - $lastAt.LocalDateTime).TotalHours
            if ($ageHours -ge $optHours) {
                $runSystemOpt = $true
            }
        } catch {
            $runSystemOpt = $true
        }
    }
}

# --- Route Definitions ---

if (-not $runMemoryOpt -and -not $runSystemOpt) {
    Write-Host "[ROUTER] Optimizer uebersprungen (Keine Intervalle faellig und kein Force-Run)." -ForegroundColor DarkGray
    return $definitions
}

# DataSync laeuft, wenn mindestens eine Optimierung aktiv ist
Add-Def -Name "DataSync" -Script "src/runs/SUB-RUN/SUB-RUN-01_MR-04_Optimizer__DataSync.ps1"
Write-Host "[ROUTER]   -> DataSync: ENABLED" -ForegroundColor Green

if ($runMemoryOpt) {
    Add-Def -Name "MemoryMaintenance" -Script "src/runs/SUB-RUN/SUB-RUN-02_MR-04_Optimizer__MemoryMaintenance.ps1"
    Write-Host "[ROUTER]   -> MemoryMaintenance: ENABLED (Planning Run: $($GlobalState.planning_run_count))" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> MemoryMaintenance: DISABLED (Nicht faellig)" -ForegroundColor DarkGray
}

if ($runSystemOpt) {
    Add-Def -Name "SystemAnalysis" -Script "src/runs/SUB-RUN/SUB-RUN-03_MR-04_Optimizer__SystemAnalysis.ps1"
    if ($forceOptimizer) {
        Write-Host "[ROUTER]   -> SystemAnalysis: ENABLED (Force run requested)" -ForegroundColor Green
    } else {
        Write-Host "[ROUTER]   -> SystemAnalysis: ENABLED ($optHours Stunden Intervall erreicht)" -ForegroundColor Green
    }
    # Speichere die force-Info fuer den Sub-Run
    $MainState | Add-Member -MemberType NoteProperty -Name "ForceOptimizer" -Value $forceOptimizer -Force
} else {
    Write-Host "[ROUTER]   -> SystemAnalysis: DISABLED (Intervall nicht erreicht)" -ForegroundColor DarkGray
}

return $definitions

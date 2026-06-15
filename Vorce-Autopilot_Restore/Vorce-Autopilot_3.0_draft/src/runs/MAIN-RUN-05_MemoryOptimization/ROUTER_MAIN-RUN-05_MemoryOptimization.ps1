# src/runs/ROUTER/ROUTER_MAIN-RUN-05_MemoryOptimization.ps1
param(
    [object]$GlobalState,
    [object]$Config,
    [object]$MainState
)

Write-Host "`n[ROUTER] Validiere dynamische Routing-Regeln fuer Memory Optimization..." -ForegroundColor Magenta

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

# 1. Memory Maintenance ist immer aktiv in diesem MAIN-RUN
Add-Def -Name "MemoryMaintenance" -Script "src/runs/MAIN-RUN-05_MemoryOptimization/SUB-RUNS/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance/SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance.ps1"
Write-Host "[ROUTER]   -> MemoryMaintenance: ENABLED" -ForegroundColor Green

return $definitions

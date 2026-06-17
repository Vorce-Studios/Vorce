# Test Strategy Phase with real configuration
$global:VorceRoot = "."
$global:VarDir = "var"
$global:LibDir = "src/lib"

# Load config
$configPath = "test-strategy-config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Create ConfigBag
$configBag = @{
    DryRun = $config.DryRun
    VorceRoot = $config.VorceRoot
    VarDir = $config.VarDir
    LibDir = $config.LibDir
    Config = $config.Config
    GlobalState = $config.GlobalState
    QuotaRegistry = $config.QuotaRegistry
    Timestamp = $config.Timestamp
}

# ParentState
$parentState = @{ status = "test" }

# Load required modules
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")

Write-VorceHeader -Title "Vorce-Factory Test" -Subtitle "Strategy Phase Dry Run"
Write-VorceStep -Message "Starte Test der Strategy-Phase mit $($config.Config.run_settings.sub_runs.'SUB-RUN-03_MR-01_Planning__Strategy'.max_parallel) parallelen Jobs" -Status "RUN"

# Run the Strategy Phase
$result = & (Join-Path $global:VorceRoot "src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/SUB-RUN-03_MR-01_Planning__Strategy.ps1") -ConfigBag $configBag -ParentState $parentState

Write-Host "`n=== Ergebnis ==="
Write-Host ($result | ConvertTo-Json -Depth 10) -ForegroundColor Green

Write-VorceStep -Message "Test abgeschlossen" -Status "OK"
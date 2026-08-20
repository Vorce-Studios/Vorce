# Test State Recovery
$global:VorceRoot = "C:\Users\Vinyl\Desktop\VJMapper\VJMapper\Vorce-Factory"
$global:VarDir = Join-Path $global:VorceRoot "var"

# Load StateManager
. (Join-Path $global:VorceRoot "src\lib\state\StateManager.ps1")

# Test 1: Initialize Run State
Write-Host "Test 1: Initialize Run State..." -ForegroundColor Cyan
$testState = Initialize-RunState -RunName "TEST-Recovery" -RunType "TEST"
Write-Host "Initialized: $($testState.id)" -ForegroundColor Green

# Test 2: Update and Save State
Write-Host "Test 2: Update and Save State..." -ForegroundColor Cyan
$testState.status = "completed"
$testState.completed_at = (Get-Date).ToString("o")
$testState.results = @(@{ test = "success"; timestamp = (Get-Date).ToString("o") })
Save-VorceRunState -State $testState
Write-Host "State saved to: TEST_TEST-Recovery.json" -ForegroundColor Green

# Test 3: Read Global State
Write-Host "Test 3: Read Global State..." -ForegroundColor Cyan
$globalState = Read-VorceGlobalState
if ($globalState) {
    Write-Host "Global State loaded: version $($globalState.version)" -ForegroundColor Green
    Write-Host "Last runs: $($globalState.last_runs.Count)" -ForegroundColor Green
} else {
    Write-Host "Failed to load Global State" -ForegroundColor Red
}

# Test 4: Save Global State
Write-Host "Test 4: Save Global State..." -ForegroundColor Cyan
$globalState.last_run = (Get-Date).ToString("o")
Save-VorceGlobalState -State $globalState
Write-Host "Global State saved" -ForegroundColor Green

# Cleanup
$testFilePath = Join-Path $global:VarDir "run-states\TEST_TEST-Recovery.json"
if (Test-Path $testFilePath) {
    Remove-Item $testFilePath -Force
    Write-Host "Cleaned up test file" -ForegroundColor Yellow
}

Write-Host "State Recovery Tests COMPLETED" -ForegroundColor Green
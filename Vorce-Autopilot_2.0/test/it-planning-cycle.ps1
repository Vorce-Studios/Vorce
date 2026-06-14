# Integration Test for Planning Cycle

$script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$script:PlanningWakeupPath = Join-Path $script:RepoRoot "src/phases/planning-wakeup.ps1"

Write-Host "Running Planning Cycle Integration Test (Dry Run)..." -ForegroundColor Cyan

# We run the planning script with -DryRun to simulate execution without side effects
& pwsh -NoProfile -ExecutionPolicy Bypass -File $script:PlanningWakeupPath -DryRun

if ($LASTEXITCODE -eq 0) {
    Write-Host "Integration Test Passed: Planning cycle dry run executed successfully." -ForegroundColor Green
} else {
    Write-Host "Integration Test Failed: Planning cycle dry run returned exit code $LASTEXITCODE." -ForegroundColor Red
}

# Quick test for CLI router with real Gemini call
Set-StrictMode -Version Latest

$ScriptDir = Join-Path $PSScriptRoot ".."
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")

$q = Read-QuotaRegistry
$result = Invoke-CliTask -QuotaRegistry $q -TaskType "monitoring" -Prompt "Say only: test successful"

Write-Host ""
Write-Host "=== Result ===" -ForegroundColor Cyan
Write-Host "Success:       $($result.success)"
Write-Host "Provider:      $($result.provider)"
Write-Host "Model Tier:    $($result.model)"

if ($result.stats) {
    Write-Host ""
    Write-Host "=== Parsed Stats ===" -ForegroundColor Green
    Write-Host "Real Cost USD: $($result.stats.real_cost_usd)"
    Write-Host "Input Tokens:  $($result.stats.input_tokens)"
    Write-Host "Output Tokens: $($result.stats.output_tokens)"
    Write-Host "Model Used:    $($result.stats.model_used)"
}

Write-Host ""
$summary = Get-QuotaSummary -Registry $q
Write-Host $summary -ForegroundColor DarkGray

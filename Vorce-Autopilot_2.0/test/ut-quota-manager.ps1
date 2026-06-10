# Unit tests for quota-manager.ps1

$script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$script:QuotaManagerPath = Join-Path $script:RepoRoot "src/lib/quota-manager.ps1"

. $script:QuotaManagerPath

$TestRegistry = [pscustomobject]@{
    last_updated = (Get-Date).ToString("o")
    providers = [pscustomobject]@{
        gemini_cli = [pscustomobject]@{
            available = $true
            limits = [pscustomobject]@{
                requests_per_minute = 15
                requests_per_day = 1500
            }
        }
    }
}

$Result = Test-ProviderAvailable -Registry $TestRegistry -ProviderName "gemini_cli"

if ($Result) {
    Write-Host "Test Passed: Provider is available" -ForegroundColor Green
} else {
    Write-Host "Test Failed: Provider should be available" -ForegroundColor Red
}

$TestRegistry.providers.gemini_cli.available = $false
$Result2 = Test-ProviderAvailable -Registry $TestRegistry -ProviderName "gemini_cli"

if (-not $Result2) {
    Write-Host "Test Passed: Provider is unavailable" -ForegroundColor Green
} else {
    Write-Host "Test Failed: Provider should be unavailable" -ForegroundColor Red
}

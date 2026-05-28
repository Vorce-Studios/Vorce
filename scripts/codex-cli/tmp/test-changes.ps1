Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $ScriptDir "lib\memory-store.ps1")

Write-Host "=== Test 1: Format-MemoryBlock (nur critical) ===" -ForegroundColor Cyan
$block = Format-MemoryBlock
Write-Host "--- Block Content ---"
Write-Host $block
Write-Host "--- Block Length: $($block.Length) chars ---"
Write-Host ""

Write-Host "=== Test 2: Search-Memories 'cargo' ===" -ForegroundColor Cyan
$result = Search-Memories -Query "cargo"
Write-Host $result
Write-Host ""

Write-Host "=== Test 3: Search-Memories 'Issue PR' ===" -ForegroundColor Cyan
$result2 = Search-Memories -Query "Issue PR"
Write-Host $result2
Write-Host ""

Write-Host "=== Test 4: Get-MemorySummary ===" -ForegroundColor Cyan
$summary = Get-MemorySummary
Write-Host $summary
Write-Host ""

Write-Host "=== Test 5: Verify Provider Routing ===" -ForegroundColor Cyan
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")
$reg = Read-QuotaRegistry

$tasks = @("monitoring", "planning", "code_review", "debugging", "complex_review")
foreach ($t in $tasks) {
    $route = Resolve-CliProvider -QuotaRegistry $reg -TaskType $t
    if ($route) {
        Write-Host "  $t -> $($route.provider):$($route.model_tier)" -ForegroundColor Green
    } else {
        Write-Host "  $t -> KEIN PROVIDER!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Alle Tests abgeschlossen ===" -ForegroundColor Green

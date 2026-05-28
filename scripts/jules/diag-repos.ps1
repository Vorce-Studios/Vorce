Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
$apiKey = Get-JulesApiKey
$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 3)
Write-Host "Total sessions: $($sessions.Count)"
$repos = @{}
$states = @{}
foreach ($s in $sessions) {
    $src = $s.sourceContext.source
    if ($null -eq $src) { $src = "unknown" }
    $repos[$src] = [int]$repos[$src] + 1
    
    $state = $s.state
    $states["$src : $state"] = [int]$states["$src : $state"] + 1
}

Write-Host "`n--- REPOSITORIES ---"
foreach ($k in $repos.Keys) {
    Write-Host "  $k : $($repos[$k])"
}

Write-Host "`n--- STATES BY REPO ---"
foreach ($k in $states.Keys) {
    Write-Host "  $k : $($states[$k])"
}

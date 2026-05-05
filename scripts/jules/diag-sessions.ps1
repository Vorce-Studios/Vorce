Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")

$apiKey = Get-JulesApiKey

Write-Host "--- JULES DIAGNOSTIC ---" -ForegroundColor Cyan
$sessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 1)

Write-Host "Total raw sessions fetched: $($sessions.Count)"

foreach ($session in $sessions) {
    $state = [string](Get-JulesObjectPropertyValue -Object $session -Name "state")
    $sourceContext = Get-JulesObjectPropertyValue -Object $session -Name "sourceContext"
    $githubRepoContext = Get-JulesObjectPropertyValue -Object $sourceContext -Name "githubRepoContext"
    $repo = [string](Get-JulesObjectPropertyValue -Object $githubRepoContext -Name "repository")
    $name = [string](Get-JulesObjectPropertyValue -Object $session -Name "name")

    Write-Host "Session: $name"
    Write-Host "  State: '$state'"
    Write-Host "  Repo:  '$repo'"
}

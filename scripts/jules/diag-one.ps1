Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
$apiKey = Get-JulesApiKey
$sessions = Get-AllJulesSessions -ApiKey $apiKey -PageSize 1
$sessions | ConvertTo-Json -Depth 10

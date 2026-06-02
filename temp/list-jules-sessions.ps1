
. (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)) "scripts/jules/jules-api.ps1")
Get-AllJulesSessions | ConvertTo-Json

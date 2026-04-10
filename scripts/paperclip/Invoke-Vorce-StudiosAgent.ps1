[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Role
)

$target = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\ops\paperclip')).Path 'Invoke-Vorce-StudiosAgent.ps1'
& $target -Role $Role
exit $LASTEXITCODE

[CmdletBinding()]
param(
    [switch]$StartServer
)

$target = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\ops\paperclip')).Path 'Initialize-Vorce-Studios.ps1'
& $target @PSBoundParameters
exit $LASTEXITCODE

# Test-RunHierarchy.ps1 (Vorce 3.0)
[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Split-Path -Parent $PSScriptRoot } else { $ProjectRoot }
$nodeScript = Join-Path $PSScriptRoot 'Test-RunHierarchy.mjs'

$output = & node $nodeScript $ProjectRoot
Write-Host $output
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

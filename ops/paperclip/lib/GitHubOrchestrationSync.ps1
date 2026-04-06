Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')

function Get-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    # Mock or wrap gh label list
    return @()
}

function Ensure-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    # Simplified: could call gh label create ...
    return $true
}

function Ensure-VorceStudiosProjectFields {
    # Stub for field sync
    return $true
}

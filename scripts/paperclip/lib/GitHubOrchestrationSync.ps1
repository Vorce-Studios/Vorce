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

function Sync-VorceStudiosIssueToGitHub {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][object]$Issue
    )

    $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$Issue.description)
    if (-not $metadata.ContainsKey('gh_issue')) {
        return $null
    }

    $issueNumber = [int]$metadata['gh_issue']

    # We might not have a session, but we want to sync the status to GitHub Project
    return Sync-VorceIssueTracking -Repository $Context.Repository -IssueNumber $issueNumber -Session $null -LatestActivity $null
}

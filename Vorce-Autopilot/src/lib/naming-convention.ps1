# Vorce issue and pull request naming convention helpers.

Set-StrictMode -Version Latest

function Test-VorceDefaultIssueTitle {
    param([AllowNull()][string]$Title)
    return -not [string]::IsNullOrWhiteSpace($Title) -and $Title -match '^\*D\*\*-(?!000)\d{3}_.+'
}

function Test-VorceMasterIssueTitle {
    param([AllowNull()][string]$Title)
    return -not [string]::IsNullOrWhiteSpace($Title) -and $Title -match '^M\.\.\.-(?!000)\d{3}_.+'
}

function Test-VorceSubIssueTitle {
    param([AllowNull()][string]$Title)
    return -not [string]::IsNullOrWhiteSpace($Title) -and $Title -match '^___M-(?!000)\d{3}_s[1-9]\d*_.+'
}

function Test-VorceIssueTitle {
    param([AllowNull()][string]$Title)
    return (Test-VorceDefaultIssueTitle -Title $Title) -or
        (Test-VorceMasterIssueTitle -Title $Title) -or
        (Test-VorceSubIssueTitle -Title $Title)
}

function Test-VorcePullRequestTitle {
    param([AllowNull()][string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title) -or -not $Title.StartsWith("PR_")) { return $false }
    return Test-VorceIssueTitle -Title $Title.Substring(3)
}

function ConvertTo-VorceTitleSlug {
    param([Parameter(Mandatory)][string]$Title)

    $slug = $Title.Trim()
    $slug = $slug -replace '^PR_', ''
    $slug = $slug -replace '^\*D\*\*-\d{3}_', ''
    $slug = $slug -replace '^M\.\.\.-\d{3}_', ''
    $slug = $slug -replace '^___M-\d{3}_s\d+_', ''
    $slug = $slug -replace '^VOR-\d{3}_(MAIs|StIs|User)_', ''
    $slug = $slug -replace '^__VOR-\d{3}_SubI_', ''
    $slug = $slug -replace '^MF-StIs_', ''
    $slug = $slug -replace '[^A-Za-z0-9]+', '-'
    $slug = $slug.Trim('-')

    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "Autopilot-Task"
    }
    return $slug
}

function Get-VorceIssueId {
    param([AllowNull()][string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $null }
    $match = [regex]::Match($Title, '^(?:\*D\*\*-|M\.\.\.-)(\d{3})_')
    if (-not $match.Success) {
        $match = [regex]::Match($Title, '^___M-(\d{3})_s\d+_')
    }
    if (-not $match.Success) { return $null }
    return [int]$match.Groups[1].Value
}

function Get-NextVorceIssueId {
    param([object[]]$Issues = @())

    $ids = @($Issues | ForEach-Object {
        $title = if ($_ -is [string]) { [string]$_ } elseif ($null -ne $_ -and $_.PSObject.Properties.Name -contains "title") { [string]$_.title } else { "" }
        if ((Test-VorceDefaultIssueTitle -Title $title) -or (Test-VorceMasterIssueTitle -Title $title)) {
            Get-VorceIssueId -Title $title
        }
    })
    if ($ids.Count -eq 0) { return 1 }
    return ([int]($ids | Measure-Object -Maximum).Maximum) + 1
}

function Format-VorceIssueTitle {
    param(
        [Parameter(Mandatory)][ValidateSet("default", "master", "sub_issue")][string]$Type,
        [Parameter(Mandatory)][string]$Title,
        [int]$Id,
        [int]$ParentMasterId,
        [int]$SubIndex
    )

    if (Test-VorceIssueTitle -Title $Title) { return $Title }
    $slug = ConvertTo-VorceTitleSlug -Title $Title

    switch ($Type) {
        "default" {
            if ($Id -lt 1 -or $Id -gt 999) { throw "Default-Issue benoetigt eine ID zwischen 001 und 999." }
            return "*D**-{0:D3}_{1}" -f $Id, $slug
        }
        "master" {
            if ($Id -lt 1 -or $Id -gt 999) { throw "Master-Issue benoetigt eine ID zwischen 001 und 999." }
            return "M...-{0:D3}_{1}" -f $Id, $slug
        }
        "sub_issue" {
            if ($ParentMasterId -lt 1 -or $ParentMasterId -gt 999) { throw "Sub-Issue benoetigt eine ParentMasterId zwischen 001 und 999." }
            if ($SubIndex -lt 1) { throw "Sub-Issue benoetigt einen SubIndex ab 1." }
            return "___M-{0:D3}_s{1}_{2}" -f $ParentMasterId, $SubIndex, $slug
        }
    }
}

function Format-VorcePullRequestTitle {
    param([Parameter(Mandatory)][string]$IssueTitle)
    if (-not (Test-VorceIssueTitle -Title $IssueTitle)) {
        throw "PR-Titel kann nicht erzeugt werden: Issue-Titel entspricht nicht der Vorce-Namenskonvention: $IssueTitle"
    }
    return "PR_$IssueTitle"
}

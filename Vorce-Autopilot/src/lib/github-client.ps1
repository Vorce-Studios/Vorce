# Vorce-Autopilot/src/lib/github-client.ps1
Set-StrictMode -Version Latest

function Get-GitHubIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 50
    )

    $issuesRaw = gh issue list --repo $Repository --state open --json number,title,labels,assignees,body --limit $Limit 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub Issue-List fehlgeschlagen: $issuesRaw"
    }

    if ([string]::IsNullOrWhiteSpace($issuesRaw)) {
        return @()
    }

    $issues = $issuesRaw | Out-String | ConvertFrom-Json
    return @($issues)
}

function New-GitHubIssue {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [string[]]$Labels = @()
    )

    $labelStr = $Labels -join ","
    $issueUrl = gh issue create --repo $Repository --title $Title --body $Body --label $labelStr 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub Issue-Erstellung fehlgeschlagen: $issueUrl"
    }

    return $issueUrl
}

function Get-GitHubPullRequests {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 100
    )

    $prsRaw = gh pr list --repo $Repository --state open --json number,title,headRefName,baseRefName,mergeable,statusCheckRollup,isDraft,url,updatedAt --limit $Limit 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub PR-List fehlgeschlagen: $prsRaw"
    }

    if ([string]::IsNullOrWhiteSpace($prsRaw)) {
        return @()
    }

    $prs = $prsRaw | Out-String | ConvertFrom-Json
    return @($prs)
}

function New-GitHubIssueComment {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Body
    )

    $commentUrl = gh issue comment $IssueNumber --repo $Repository --body $Body 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub Kommentar-Erstellung fehlgeschlagen: $commentUrl"
    }

    return $commentUrl
}

function Invoke-GitFetchPrune {
    git fetch --prune
}

function Get-GitGoneBranches {
    $branches = git branch -vv | Where-Object { $_ -match ": gone\]" } | ForEach-Object {
        $_.Trim().Split(" ")[0]
    }
    return @($branches)
}

function Delete-GitBranch {
    param(
        [Parameter(Mandatory)][string]$BranchName,
        [switch]$Force
    )

    $flag = if ($Force) { "-D" } else { "-d" }
    git branch $flag $BranchName
}

# Vorce-Autopilot/src/lib/github-client.ps1
Set-StrictMode -Version Latest

function Get-GitHubIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 50
    )

    $issuesRaw = gh issue list --repo $Repository --state open --json number,title,labels,assignees,body --limit $Limit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "GitHub Issue-List fehlgeschlagen: $issuesRaw"
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($issuesRaw)) {
        return @()
    }

    $issues = $issuesRaw | Out-String | ConvertFrom-Json
    return @($issues)
}

function Get-AllGitHubIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 1000
    )

    $issuesRaw = gh issue list --repo $Repository --state all --json number,title,labels,assignees,body,state --limit $Limit 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "GitHub Issue-Gesamtliste fehlgeschlagen: $issuesRaw"
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($issuesRaw)) { return @() }
    return @($issuesRaw | Out-String | ConvertFrom-Json)
}

function New-GitHubIssue {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [string[]]$Labels = @()
    )

    if (-not (Test-VorceIssueTitle -Title $Title)) {
        throw "GitHub Issue-Erstellung blockiert: Titel entspricht nicht der Vorce-Namenskonvention: $Title"
    }

    # Ensure all target labels exist on the repository before creating the issue
    foreach ($lbl in $Labels) {
        if (-not [string]::IsNullOrWhiteSpace($lbl)) {
            try {
                gh label create $lbl --repo $Repository --color "CCCCCC" --description "Auto-created by Autopilot" 2>&1 | Out-Null
            } catch {
                # Ignore errors (e.g., if label already exists)
            }
        }
    }

    $safeBody = if ([string]::IsNullOrWhiteSpace($Body)) { "Autopilot-created issue. Details were not provided by the planning agent; inspect the linked planning run before delegation." } else { $Body }
    $labelStr = $Labels -join ","
    if ([string]::IsNullOrWhiteSpace($labelStr)) {
        $issueUrl = gh issue create --repo $Repository --title $Title --body $safeBody 2>&1
    } else {
        $issueUrl = gh issue create --repo $Repository --title $Title --body $safeBody --label $labelStr 2>&1
    }
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
        Write-Warning "GitHub PR-List fehlgeschlagen: $prsRaw"
        return @()
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

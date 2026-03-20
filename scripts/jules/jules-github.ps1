Set-StrictMode -Version Latest

$script:JulesIssueBlockStart = "<!-- jules-session:begin -->"
$script:JulesIssueBlockEnd = "<!-- jules-session:end -->"

function Assert-GitHubCli {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "gh CLI wurde nicht gefunden."
    }
}

function Get-RepositoryFromGitRemote {
    $remoteUrl = git config --get remote.origin.url 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
        return $null
    }

    if ($remoteUrl -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+?)(?:\.git)?$") {
        return "{0}/{1}" -f $Matches["owner"], $Matches["repo"]
    }

    return $null
}

function Resolve-GitHubRepository {
    param([string]$Repository)

    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        return $Repository.Trim()
    }

    $detected = Get-RepositoryFromGitRemote
    if (-not [string]::IsNullOrWhiteSpace($detected)) {
        return $detected
    }

    throw "GitHub-Repository konnte nicht ermittelt werden. Bitte -Repository owner/repo angeben."
}

function Get-JulesSourceNameForRepository {
    param([string]$Repository, [string]$SourceName)

    if (-not [string]::IsNullOrWhiteSpace($SourceName)) {
        return $SourceName.Trim()
    }

    return "sources/github/$(Resolve-GitHubRepository -Repository $Repository)"
}

function Invoke-GitHubApiJson {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [AllowNull()][object]$Body,
        [switch]$AllowEmptyResponse
    )

    Assert-GitHubCli

    $tempFile = $null
    try {
        $allArgs = @($Arguments)
        if ($PSBoundParameters.ContainsKey("Body")) {
            $tempFile = [System.IO.Path]::GetTempFileName()
            $Body | ConvertTo-Json -Depth 50 | Set-Content -Path $tempFile -Encoding UTF8 -NoNewline
            $allArgs += @("--input", $tempFile)
        }

        $output = & gh @allArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw (($output | Out-String).Trim())
        }

        $text = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            if ($AllowEmptyResponse) { return $null }
            return $null
        }

        return $text | ConvertFrom-Json
    } finally {
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item -Path $tempFile -Force
        }
    }
}

function Get-GitHubIssue {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber)

    Assert-GitHubCli
    $output = & gh issue view $IssueNumber --repo $Repository --json number,title,body,url,state,labels 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }

    return (($output | Out-String) | ConvertFrom-Json)
}

function Get-GitHubIssueComments {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber)

    $comments = Invoke-GitHubApiJson -Arguments @("api", "repos/$Repository/issues/$IssueNumber/comments")
    if ($null -eq $comments) { return @() }
    return @($comments)
}

function Set-GitHubIssueBody {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][string]$Body)

    Invoke-GitHubApiJson -Arguments @("api", "repos/$Repository/issues/$IssueNumber", "--method", "PATCH") -Body @{ body = $Body } -AllowEmptyResponse | Out-Null
}

function Add-GitHubIssueComment {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][string]$Body)

    Invoke-GitHubApiJson -Arguments @("api", "repos/$Repository/issues/$IssueNumber/comments", "--method", "POST") -Body @{ body = $Body } | Out-Null
}

function Remove-GitHubIssueLabel {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][string]$LabelName)

    try {
        Invoke-GitHubApiJson -Arguments @("api", "repos/$Repository/issues/$IssueNumber/labels/$([uri]::EscapeDataString($LabelName))", "--method", "DELETE") -AllowEmptyResponse | Out-Null
    } catch {
        Write-JulesWarn "Label '$LabelName' konnte nicht entfernt werden: $($_.Exception.Message)"
    }
}

function Format-MarkdownValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "_n/a_" }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "_n/a_" }
    if ($text -match "^https?://") { return $text }

    return ('`{0}`' -f $text)
}

function Format-JulesIssueTrackingBlock {
    param([Parameter(Mandatory)][hashtable]$Fields)

    $lines = @(
        $script:JulesIssueBlockStart,
        "<!-- jules-session-id: $($Fields.SessionId) -->",
        "<!-- jules-session-name: $($Fields.SessionName) -->",
        "## Jules Automation",
        "- Jules Session ID: $(Format-MarkdownValue -Value $Fields.SessionId)",
        "- Jules Session Name: $(Format-MarkdownValue -Value $Fields.SessionName)",
        "- Jules Session URL: $(Format-MarkdownValue -Value $Fields.SessionUrl)",
        "- Jules Status: $(Format-MarkdownValue -Value $Fields.State)",
        "- Jules Automation: $(Format-MarkdownValue -Value $Fields.AutomationMode)",
        "- Plan Approval: $(Format-MarkdownValue -Value $Fields.RequirePlanApproval)",
        "- Start Branch: $(Format-MarkdownValue -Value $Fields.StartingBranch)",
        "- Jules Source: $(Format-MarkdownValue -Value $Fields.SourceName)",
        "- GitHub PR: $(Format-MarkdownValue -Value $Fields.PullRequestUrl)",
        "- Letzte Aktivitaet: $(Format-MarkdownValue -Value $Fields.LastActivitySummary)",
        "- Aktualisiert: $(Format-MarkdownValue -Value $Fields.UpdatedAt)",
        $script:JulesIssueBlockEnd
    )

    return ($lines -join "`n")
}

function Upsert-JulesIssueTrackingBlock {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber, [Parameter(Mandatory)][hashtable]$Fields)

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { "" } else { [string]$issue.body }
    $block = Format-JulesIssueTrackingBlock -Fields $Fields
    $pattern = [regex]::Escape($script:JulesIssueBlockStart) + ".*?" + [regex]::Escape($script:JulesIssueBlockEnd)

    if ($body -match $pattern) {
        $updatedBody = [regex]::Replace(
            $body,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $block },
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
    } elseif ([string]::IsNullOrWhiteSpace($body)) {
        $updatedBody = $block
    } else {
        $updatedBody = "{0}`n`n{1}" -f $body.TrimEnd(), $block
    }

    Set-GitHubIssueBody -Repository $Repository -IssueNumber $IssueNumber -Body $updatedBody
}

function Get-JulesSessionReferenceFromIssue {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber)

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { "" } else { [string]$issue.body }

    if ($body -match "<!-- jules-session-name: (?<name>s.+?) -->") {
        $name = $Matches["name"].Trim()
        return @{
            SessionName = $name
            SessionId   = Resolve-JulesSessionId -SessionIdOrName $name
        }
    }

    if ($body -match "<!-- jules-session-id: (?<id>[^ ]+?) -->") {
        $id = $Matches["id"].Trim()
        return @{
            SessionName = Resolve-JulesSessionName -SessionIdOrName $id
            SessionId   = $id
        }
    }

    foreach ($comment in (Get-GitHubIssueComments -Repository $Repository -IssueNumber $IssueNumber | Sort-Object created_at -Descending)) {
        $commentBody = [string]$comment.body
        if ($commentBody -match 'sessions/(?<id>[^)\s`]+)') {
            $id = $Matches["id"].Trim()
            return @{
                SessionName = "sessions/$id"
                SessionId   = $id
            }
        }
    }

    return $null
}

function Convert-IssueToJulesPrompt {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [string]$Repository,
        [string]$AdditionalPrompt,
        [bool]$AutoCreatePr
    )

    $labels = @()
    if ($Issue.labels) {
        $labels = @($Issue.labels | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $body = if ($null -eq $Issue.body) { "" } else { [string]$Issue.body }
    $parts = @(
        "Issue #$($Issue.number): $($Issue.title)",
        "Repository: $Repository",
        "Issue URL: $($Issue.url)"
    )

    if ($labels.Count -gt 0) {
        $parts += "Labels: $($labels -join ', ')"
    }

    $parts += ""
    $parts += $body

    if (-not [string]::IsNullOrWhiteSpace($AdditionalPrompt)) {
        $parts += ""
        $parts += "---"
        $parts += $AdditionalPrompt.Trim()
    }

    if ($AutoCreatePr) {
        $parts += ""
        $parts += "---"
        $parts += "**IMPORTANT:** Wenn du die Pull-Request-Beschreibung fuer dieses Issue erstellst, musst du exakt diesen Block mit der echten GitHub-Issue-Nummer aufnehmen:"
        $parts += "## Verlinktes Issue"
        $parts += "Fixes #$($Issue.number)"
        $parts += ""
        $parts += "Ersetze die GitHub-Issue-Nummer nicht durch eine ROADMAP- oder MF-Task-ID."
    }

    return (($parts -join "`n").Trim())
}

function Sync-JulesIssueTracking {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][object]$Session,
        [AllowNull()][object]$LatestActivity,
        [string]$StartingBranch,
        [string]$SourceName
    )

    $fields = @{
        SessionId           = Resolve-JulesSessionId -SessionIdOrName ([string]$Session.name)
        SessionName         = [string]$Session.name
        SessionUrl          = [string]$Session.url
        State               = [string]$Session.state
        AutomationMode      = [string]$Session.automationMode
        RequirePlanApproval = if ($null -eq $Session.requirePlanApproval) { $null } else { [bool]$Session.requirePlanApproval }
        StartingBranch      = $StartingBranch
        SourceName          = $SourceName
        PullRequestUrl      = Get-JulesSessionPullRequestUrl -Session $Session
        LastActivitySummary = Get-JulesActivitySummary -Activity $LatestActivity
        UpdatedAt           = if (-not [string]::IsNullOrWhiteSpace([string]$Session.updateTime)) { [string]$Session.updateTime } else { [string]$Session.createTime }
    }

    Upsert-JulesIssueTrackingBlock -Repository $Repository -IssueNumber $IssueNumber -Fields $fields
}

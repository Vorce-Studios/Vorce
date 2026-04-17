[CmdletBinding()]
param(
    [int[]]$IssueNumber,
    [string]$Repository = "Vorce-Studios/Vorce",
    [string]$LegacyRepository = "MrLongNight/MapFlow",
    [string]$LegacyProjectOwner = "MrLongNight",
    [int]$LegacyProjectNumber = 3,
    [string]$LegacyProjectTitle = "@Vorce Project Manager",
    [int]$IssueLimit = 200,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-github.ps1")

function Write-JulesWarn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning $Message
}

function BodyText {
    param([AllowNull()][string]$Body)
    if ($null -eq $Body) { return "" }
    return ([string]$Body).TrimStart([char]0xFEFF)
}

function CleanVal {
    param([AllowNull()][string]$Value, [int]$MaxLength = 220)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Replace("`r", "").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -match '^`(?<code>.+)`$') { $text = $Matches["code"].Trim() }
    if ($text -match '^\[(?<label>[^\]]+)\]\((?<url>https?://[^)]+)\)$') { $text = $Matches["url"].Trim() }
    if ($text -in @("_No response_", "_n/a_", "n/a", "N/A", "none", "None", "null", "Null")) { return $null }
    return Normalize-TrackingText -Value $text -MaxLength $MaxLength
}

function HeadingText {
    param([string]$Body, [string[]]$Names)
    $text = BodyText -Body $Body
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    foreach ($name in $Names) {
        $pattern = "(?ims)^#{2,3}\s+$([regex]::Escape($name))\s*$\s*(?<value>.*?)(?=^#{2,3}\s+|\z)"
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) { return $match.Groups["value"].Value.Trim() }
    }
    return $null
}

function ProjectFieldVal {
    param([string]$Body, [string]$Field)
    $block = HeadingText -Body $Body -Names @("Vorce Project Manager", "MapFlow Project Manager")
    if ([string]::IsNullOrWhiteSpace($block)) { return $null }
    $pattern = "(?ims)^###\s+$([regex]::Escape($Field))\s*$\s*(?<value>.*?)(?=^###\s+|\z)"
    $match = [regex]::Match($block, $pattern)
    if (-not $match.Success) { return $null }
    return CleanVal -Value $match.Groups["value"].Value
}

function SectionSummary {
    param([string]$Body, [string[]]$Names, [int]$MaxLength = 220)
    $block = HeadingText -Body $Body -Names $Names
    if ([string]::IsNullOrWhiteSpace($block)) { return $null }
    $lines = @(
        $block -split "`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notin @('---', '```', '```shell') }
    )
    if ($lines.Count -eq 0) { return $null }
    $picked = @()
    foreach ($line in $lines) {
        if ($line -match '^(?:[-*]|\d+\.)\s+') { continue }
        $picked += $line
        if (($picked -join " ").Length -ge $MaxLength) { break }
    }
    if ($picked.Count -eq 0) { $picked = @($lines[0]) }
    return CleanVal -Value ($picked -join " ") -MaxLength $MaxLength
}

function BulletVal {
    param([string]$Body, [string[]]$Labels, [string[]]$Sections, [int]$MaxLength = 180)
    $scope = if ($Sections -and $Sections.Count -gt 0) { HeadingText -Body $Body -Names $Sections } else { BodyText -Body $Body }
    if ([string]::IsNullOrWhiteSpace($scope)) { return $null }
    foreach ($label in $Labels) {
        $pattern = "(?im)^[\-\*\u2022]\s+$([regex]::Escape($label))\s*:\s*(?<value>.+?)\s*$"
        $match = [regex]::Match($scope, $pattern)
        if ($match.Success) { return CleanVal -Value $match.Groups["value"].Value -MaxLength $MaxLength }
    }
    return $null
}

function CommentVal {
    param([string]$Body, [string[]]$Names, [int]$MaxLength = 180)
    $text = BodyText -Body $Body
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    foreach ($name in $Names) {
        $pattern = "<!--\s*$([regex]::Escape($name)):\s*(?<value>.*?)\s*-->"
        $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return CleanVal -Value $match.Groups["value"].Value -MaxLength $MaxLength }
    }
    return $null
}

function FirstFromBodies {
    param([string[]]$Bodies, [scriptblock]$Getter)
    foreach ($body in $Bodies) {
        if ([string]::IsNullOrWhiteSpace($body)) { continue }
        $value = & $Getter $body
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

function LegacyNumber {
    param([string]$Body)
    $match = [regex]::Match((BodyText -Body $Body), 'Migrated from legacy issue MrLongNight/MapFlow#(?<number>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups["number"].Value
}

function TitleTaskId {
    param([string]$Title)
    $text = CleanVal -Value $Title -MaxLength 140
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -match '^__SI-\d+_MAI-\d+_(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^MAI-\d+_(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^I_(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^MFuser_#\d+-(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^MFusr_#\d+-(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^MF_#\d+-(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^MFsub_#\d+-(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^(?<id>[^:]+):') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    return $text
}

function ResolveTaskType {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels, [string]$Title, [string]$Body)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^Verification$' { return "Test" }
            '^Implementation$' { return "Feature" }
            '^(Bug|Feature|Fix|Polish|Refactor|Test)$' { return $candidate }
        }
    }
    $joinedLabels = (($Labels | ForEach-Object { [string]$_ }) -join " ").ToLowerInvariant()
    $titleText = ([string]$Title).ToLowerInvariant()
    $bodyText = (BodyText -Body $Body).ToLowerInvariant()
    if ($joinedLabels.Contains("bug") -or $titleText.Contains("[bug]") -or $bodyText.Contains("bug description")) { return "Bug" }
    if ($joinedLabels.Contains("refactoring")) { return "Refactor" }
    if ($joinedLabels.Contains("testing") -or $titleText.Contains("verify") -or $titleText.Contains("verification") -or $titleText.Contains("test") -or $titleText.Contains("qa")) { return "Test" }
    if ($joinedLabels.Contains("documentation")) { return "Polish" }
    if ($joinedLabels.Contains("feature-request") -or $joinedLabels.Contains("enhancement")) { return "Feature" }
    return $null
}

function ResolvePriority {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^(A|Critical|High)$' { return "A" }
            '^(B|Medium)$' { return "B" }
            '^(C|Low)$' { return "C" }
        }
    }
    foreach ($label in $Labels) {
        switch ([string]$label) {
            "priority: critical" { return "A" }
            "priority: high" { return "A" }
            "priority: medium" { return "B" }
            "priority: low" { return "C" }
        }
    }
    return $null
}

function ResolveAgent {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels, [AllowNull()][string]$SessionId, [string]$Body, [string]$Title)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^(Jules|AgentJules)$' { return "AgentJules" }
            '^(Gemini CLI|Codex / Gemini CLI)$' { return "Gemini CLI" }
            '^(Codex CLI|Codex)$' { return "Codex CLI" }
            '^Codex Web$' { return "Codex Web" }
            '^Maestro$' { return "Maestro" }
        }
    }
    if ($Labels -contains "jules-task") { return "AgentJules" }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) { return "AgentJules" }
    $text = ("{0} {1}" -f $Title, (BodyText -Body $Body)).ToLowerInvariant()
    if ($text.Contains("gemini cli")) { return "Gemini CLI" }
    return $null
}

function SessionIdVal {
    param([string]$Body)
    $value = CommentVal -Body $Body -Names @("jules-session-id") -MaxLength 80
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    return BulletVal -Body $Body -Labels @("Jules Session ID") -Sections @("Jules Automation", "Roadmap Task") -MaxLength 80
}

function Set-ProjectFieldByName {
    param([object]$Context, [string]$ItemId, [string]$FieldName, [AllowNull()][string]$Value)
    $field = Get-VorceProjectField -Context $Context -FieldName $FieldName
    if ($null -eq $field) { return }
    Set-VorceProjectFieldValue -Context $Context -ItemId $ItemId -Field $field -Value $Value
}

function Ensure-ProjectTextField {
    param([Parameter(Mandatory)][object]$Context, [Parameter(Mandatory)][string]$FieldName, [switch]$DryRun)

    $existing = Get-VorceProjectField -Context $Context -FieldName $FieldName
    if ($null -ne $existing) { return $existing }
    if ($DryRun.IsPresent) { return $null }

    $mutation = @'
mutation($projectId: ID!, $name: String!, $dataType: ProjectV2CustomFieldType!) {
  createProjectV2Field(input: { projectId: $projectId, name: $name, dataType: $dataType }) {
    projectV2Field {
      __typename
      ... on ProjectV2Field {
        id
        name
        dataType
      }
    }
  }
}
'@

    $data = Invoke-GitHubGraphQl -Query $mutation -Variables @{
        projectId = $Context.ProjectId
        name      = $FieldName
        dataType  = "TEXT"
    }

    $field = $data.createProjectV2Field.projectV2Field
    if ($null -ne $field -and -not [string]::IsNullOrWhiteSpace([string]$field.name)) {
        $Context.FieldsByName[[string]$field.name] = $field
        return $field
    }

    return $null
}

function Get-GitHubPullRequests {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [ValidateSet("open", "closed", "merged", "all")][string]$State = "open",
        [int]$Limit = 200
    )

    Assert-GitHubCli
    $output = & gh pr list --repo $Repository --state $State --limit $Limit --json number,title,body,url,state,isDraft,headRefName,updatedAt,mergeable,reviewDecision,labels 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }

    $items = (($output | Out-String) | ConvertFrom-Json)
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Add-LookupEntry {
    param([hashtable]$Lookup, [AllowNull()][string]$Key, [AllowNull()][object]$Value)
    if ($null -eq $Lookup -or [string]::IsNullOrWhiteSpace($Key) -or $null -eq $Value) {
        return
    }

    if (-not $Lookup.ContainsKey($Key)) {
        $Lookup[$Key] = New-Object System.Collections.Generic.List[object]
    }

    $Lookup[$Key].Add($Value) | Out-Null
}

function Get-LookupFirst {
    param([hashtable]$Lookup, [AllowNull()][string]$Key)
    if ($null -eq $Lookup -or [string]::IsNullOrWhiteSpace($Key) -or -not $Lookup.ContainsKey($Key)) {
        return $null
    }

    $values = @($Lookup[$Key])
    if ($values.Count -eq 0) { return $null }
    return $values[0]
}

function Parse-LegacyPrNumberFromMigratedPr {
    param([AllowNull()][object]$PullRequest)
    if ($null -eq $PullRequest) { return $null }

    foreach ($text in @([string]$PullRequest.title, [string]$PullRequest.body)) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $match = [regex]::Match($text, 'Migrated from (?:https://github\.com/)?MrLongNight/MapFlow/pull/(?<number>\d+)|Migrated from MapFlow PR #(?<legacy>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            if ($match.Groups["number"].Success) { return [int]$match.Groups["number"].Value }
            if ($match.Groups["legacy"].Success) { return [int]$match.Groups["legacy"].Value }
        }
    }

    return $null
}

function Parse-PullRequestNumberFromUrl {
    param([AllowNull()][string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $match = [regex]::Match($Url, 'github\.com/[^/]+/[^/]+/pull/(?<number>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups["number"].Value
}

function IsSpecificBranchName {
    param([AllowNull()][string]$Branch)
    $value = CleanVal -Value $Branch -MaxLength 120
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return ($value.ToLowerInvariant() -notin @("main", "master", "n/a", "none"))
}

function ResolveParentIssueNumber {
    param([string]$Body)

    $text = BodyText -Body $Body
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    foreach ($pattern in @(
        '(?im)^\s*Part of\s+(?:Vorce-Studios/Vorce)?#(?<number>\d+)\b',
        '(?im)^\s*Parent issue:\s*(?:Vorce-Studios/Vorce)?#(?<number>\d+)\b'
    )) {
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) { return [int]$match.Groups["number"].Value }
    }

    return $null
}

function Get-IssueParentNumber {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][int]$IssueNumber)

    $parts = $Repository.Split("/")
    $query = @'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      parent {
        number
      }
    }
  }
}
'@

    $data = Invoke-GitHubGraphQl -Query $query -Variables @{
        owner  = $parts[0]
        repo   = $parts[1]
        number = $IssueNumber
    }

    $parent = $data.repository.issue.parent
    if ($null -eq $parent) { return $null }
    return [int]$parent.number
}

function Ensure-SubIssueRelationship {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$ParentIssueNumber,
        [Parameter(Mandatory)][int]$ChildIssueNumber,
        [Parameter(Mandatory)][string]$ParentIssueId,
        [Parameter(Mandatory)][string]$ChildIssueId,
        [switch]$DryRun
    )

    if ($ParentIssueNumber -eq $ChildIssueNumber) {
        return "skipped_self"
    }

    $currentParent = Get-IssueParentNumber -Repository $Repository -IssueNumber $ChildIssueNumber
    if ($null -ne $currentParent) {
        if ($currentParent -eq $ParentIssueNumber) {
            return "already_linked"
        }

        Write-JulesWarn "Issue #$ChildIssueNumber hat bereits Parent #$currentParent und wird nicht nach #$ParentIssueNumber umgehaengt."
        return "skipped_existing_parent"
    }

    if ($DryRun.IsPresent) {
        return "would_link"
    }

    $mutation = @'
mutation($issueId: ID!, $subIssueId: ID!) {
  addSubIssue(input: { issueId: $issueId, subIssueId: $subIssueId, replaceParent: false }) {
    issue { number }
    subIssue { number parent { number } }
  }
}
'@

    Invoke-GitHubGraphQl -Query $mutation -Variables @{
        issueId    = $ParentIssueId
        subIssueId = $ChildIssueId
    } | Out-Null

    return "linked"
}

function QueueStateVal {
    param([string[]]$Bodies)
    $value = FirstFromBodies -Bodies $Bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-queue-state", "mapflow-queue-state") -MaxLength 80 }
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    return FirstFromBodies -Bodies $Bodies -Getter {
        param($b)
        BulletVal -Body $b -Labels @("Queue State") -Sections @("Vorce Project Manager", "MapFlow Project Manager") -MaxLength 80
    }
}

function RemoteStateVal {
    param([string[]]$Bodies)
    $value = FirstFromBodies -Bodies $Bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-remote-state", "mapflow-remote-state") -MaxLength 80 }
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    $value = FirstFromBodies -Bodies $Bodies -Getter {
        param($b)
        BulletVal -Body $b -Labels @("Remote State") -Sections @("Vorce Project Manager", "MapFlow Project Manager") -MaxLength 80
    }
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    return FirstFromBodies -Bodies $Bodies -Getter {
        param($b)
        BulletVal -Body $b -Labels @("Jules Status") -Sections @("Jules Automation") -MaxLength 80
    }
}

function LinkedPrVal {
    param([string[]]$Bodies)
    return FirstFromBodies -Bodies $Bodies -Getter {
        param($b)
        BulletVal -Body $b -Labels @("Linked PR", "GitHub PR") -Sections @("Vorce Project Manager", "MapFlow Project Manager", "Jules Automation") -MaxLength 220
    }
}

function Get-ProjectStatusMap {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][int]$ProjectNumber,
        [AllowNull()][string]$ProjectTitle,
        [Parameter(Mandatory)][string]$Repository
    )

    $repositoryParts = (Resolve-GitHubRepository -Repository $Repository).Split("/")
    $repositoryOwner = [string]$repositoryParts[0]
    $repositoryName = [string]$repositoryParts[1]

    $userQuery = @'
query($owner: String!, $number: Int!, $cursor: String) {
  user(login: $owner) {
    projectV2(number: $number) {
      id
      title
      items(first: 100, after: $cursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          content {
            __typename
            ... on Issue {
              number
              repository {
                name
                owner {
                  login
                }
              }
            }
          }
          fieldValues(first: 40) {
            nodes {
              __typename
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
'@

    $orgQuery = @'
query($owner: String!, $number: Int!, $cursor: String) {
  organization(login: $owner) {
    projectV2(number: $number) {
      id
      title
      items(first: 100, after: $cursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          content {
            __typename
            ... on Issue {
              number
              repository {
                name
                owner {
                  login
                }
              }
            }
          }
          fieldValues(first: 40) {
            nodes {
              __typename
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field {
                  ... on ProjectV2FieldCommon {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
'@

    $statusByIssueNumber = @{}
    $cursor = $null
    $ownerKind = $null
    $validatedTitle = $false

    do {
        $project = $null
        if ([string]::IsNullOrWhiteSpace($ownerKind) -or $ownerKind -eq "user") {
            try {
                $data = Invoke-GitHubGraphQl -Query $userQuery -Variables @{
                    owner  = $Owner
                    number = $ProjectNumber
                    cursor = $cursor
                }
                if ($null -ne $data.user.projectV2) {
                    $project = $data.user.projectV2
                    $ownerKind = "user"
                }
            } catch {
                $project = $null
            }
        }

        if ($null -eq $project -and ([string]::IsNullOrWhiteSpace($ownerKind) -or $ownerKind -eq "organization")) {
            try {
                $data = Invoke-GitHubGraphQl -Query $orgQuery -Variables @{
                    owner  = $Owner
                    number = $ProjectNumber
                    cursor = $cursor
                }
                if ($null -ne $data.organization.projectV2) {
                    $project = $data.organization.projectV2
                    $ownerKind = "organization"
                }
            } catch {
                $project = $null
            }
        }

        if ($null -eq $project) {
            if ($statusByIssueNumber.Count -gt 0) { break }
            throw "Legacy-Project '$Owner#$ProjectNumber' konnte nicht geladen werden."
        }

        if (-not $validatedTitle) {
            $validatedTitle = $true
            if (-not [string]::IsNullOrWhiteSpace($ProjectTitle) -and ([string]$project.title -ne $ProjectTitle)) {
                Write-JulesWarn "Legacy-Project '$Owner#$ProjectNumber' hat unerwarteten Titel '$([string]$project.title)'. Erwartet war '$ProjectTitle'."
            }
        }

        foreach ($item in @($project.items.nodes)) {
            if ($null -eq $item.content -or [string]$item.content.__typename -ne "Issue") {
                continue
            }

            if ([string]$item.content.repository.owner.login -ne $repositoryOwner -or [string]$item.content.repository.name -ne $repositoryName) {
                continue
            }

            $status = $null
            foreach ($fieldValue in @($item.fieldValues.nodes)) {
                if ([string]$fieldValue.__typename -ne "ProjectV2ItemFieldSingleSelectValue") {
                    continue
                }

                if ([string]$fieldValue.field.name -eq "Status" -and -not [string]::IsNullOrWhiteSpace([string]$fieldValue.name)) {
                    $status = [string]$fieldValue.name
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($status)) {
                $statusByIssueNumber[[int]$item.content.number] = $status
            }
        }

        $pageInfo = $project.items.pageInfo
        $cursor = if ($pageInfo.hasNextPage) { [string]$pageInfo.endCursor } else { $null }
    } while (-not [string]::IsNullOrWhiteSpace($cursor))

    return $statusByIssueNumber
}

function Add-UniqueValue {
    param([System.Collections.Generic.List[string]]$List, [AllowNull()][string]$Value)
    $clean = CleanVal -Value $Value -MaxLength 220
    if ([string]::IsNullOrWhiteSpace($clean)) { return }
    if (-not $List.Contains($clean)) {
        $List.Add($clean) | Out-Null
    }
}

function ResolveProjectStatus {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [string[]]$Labels,
        [AllowNull()][string]$QueueState,
        [AllowNull()][string]$RemoteState,
        [AllowNull()][string]$LinkedPrValue,
        [AllowNull()][object]$CurrentPr,
        [AllowNull()][object[]]$CurrentPrChecks,
        [bool]$HasChildren = $false
    )

    if (Test-GitHubIssueClosed -Issue $Issue) {
        return "Done"
    }

    if ($null -ne $CurrentPr) {
        $currentPrState = ([string]$CurrentPr.state).Trim().ToUpperInvariant()
        if ($currentPrState -eq "MERGED") { return "QA Test" }
        if ($currentPrState -eq "CLOSED") { return "PR CodeRework" }
        if ($currentPrState -eq "OPEN") {
            if ($CurrentPr.isDraft) { return "PR-Checks" }
            if (([string]$CurrentPr.reviewDecision).Trim().ToUpperInvariant() -eq "CHANGES_REQUESTED") { return "PR CodeRework" }

            $checkStates = @(
                $CurrentPrChecks |
                    ForEach-Object { ([string]$_.state).Trim().ToUpperInvariant() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )

            if (($checkStates | Where-Object { $_ -in @("FAILURE", "FAILED", "ERROR", "ACTION_REQUIRED", "CANCELLED", "TIMED_OUT") }).Count -gt 0) {
                return "PR CodeRework"
            }

            if (($checkStates | Where-Object { $_ -in @("PENDING", "IN_PROGRESS", "QUEUED", "STARTUP_FAILURE", "WAITING", "EXPECTED") }).Count -gt 0) {
                return "PR-Checks"
            }

            return "Review PR"
        }
    }

    $normalizedLabels = @(
        $Labels |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    $remote = ([string]$RemoteState).Trim().ToLowerInvariant()
    $queue = ([string]$QueueState).Trim().ToLowerInvariant()

    if ($normalizedLabels -contains "todo-userisu") { return "Todo" }
    if ($normalizedLabels -contains "status: needs-review") { return "Review PR" }
    if ($normalizedLabels -contains "status: blocked") { return "PR CodeRework" }
    if ($remote -in @("failed", "awaiting-user-feedback", "awaiting-plan-approval", "paused")) { return "PR CodeRework" }
    if ($normalizedLabels -contains "status: in-progress") {
        if ($remote -in @("merged", "completed", "closed")) { return "QA Test" }
        return "JulesSession"
    }
    if ($remote -in @("merged", "completed", "closed")) { return "QA Test" }
    if ($queue -in @("user-review", "approved-awaiting-dispatch", "issue-only", "not-started")) { return "Todo" }
    if (($normalizedLabels -contains "jules-task") -or ($remote -in @("queued", "planning", "in-progress", "running", "dispatched", "awaiting-session")) -or ($queue -in @("dispatched", "queued", "planning"))) {
        return "JulesSession"
    }
    if ($HasChildren) { return "JulesSession" }
    if (-not [string]::IsNullOrWhiteSpace($LinkedPrValue)) { return "QA Test" }
    return "Todo"
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$projectContext = Get-VorceProjectContext -Repository $resolvedRepository
if ($null -eq $projectContext) {
    throw "GitHub Project fuer '$resolvedRepository' konnte nicht ermittelt werden."
}

if (-not $DryRun.IsPresent) {
    Ensure-ProjectTextField -Context $projectContext -FieldName "Linked PR" | Out-Null
}

$issues = @(
    if ($IssueNumber) {
        $IssueNumber | ForEach-Object { Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $_ }
    } else {
        Get-GitHubIssues -Repository $resolvedRepository -State "all" -Limit $IssueLimit
    }
)

$legacyNumbers = @(
    $issues |
        ForEach-Object {
            $number = LegacyNumber -Body ([string]$_.body)
            if ($null -ne $number) { $number }
        } |
        Sort-Object -Unique
)

$legacyMap = @{}
if ($legacyNumbers.Count -gt 0) {
    foreach ($legacyIssue in @(Get-GitHubIssues -Repository $LegacyRepository -State "all" -Limit 500)) {
        $legacyMap[[int]$legacyIssue.number] = $legacyIssue
    }
}

$legacyProjectStatusByIssueNumber = @{}
if ($legacyNumbers.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($LegacyProjectOwner) -and $LegacyProjectNumber -gt 0) {
    try {
        $legacyProjectStatusByIssueNumber = Get-ProjectStatusMap -Owner $LegacyProjectOwner -ProjectNumber $LegacyProjectNumber -ProjectTitle $LegacyProjectTitle -Repository $LegacyRepository
    } catch {
        Write-JulesWarn "Legacy-Project-Status konnte nicht geladen werden: $($_.Exception.Message)"
    }
}

$currentPullRequests = @(
    Get-GitHubPullRequests -Repository $resolvedRepository -State "all" -Limit 200 |
        Sort-Object {
            try { [datetimeoffset]([string]$_.updatedAt) } catch { [datetimeoffset]::MinValue }
        } -Descending
)

$currentPrsByBranch = @{}
$currentPrsByLegacyNumber = @{}
$currentPrsByNumber = @{}
foreach ($pullRequest in $currentPullRequests) {
    $currentPrsByNumber[[int]$pullRequest.number] = $pullRequest
    if (IsSpecificBranchName -Branch ([string]$pullRequest.headRefName)) {
        Add-LookupEntry -Lookup $currentPrsByBranch -Key ([string]$pullRequest.headRefName) -Value $pullRequest
    }

    $legacyPrNumber = Parse-LegacyPrNumberFromMigratedPr -PullRequest $pullRequest
    if ($null -ne $legacyPrNumber) {
        Add-LookupEntry -Lookup $currentPrsByLegacyNumber -Key ([string]$legacyPrNumber) -Value $pullRequest
    }
}

$currentPrChecksByNumber = @{}
foreach ($pullRequest in @($currentPullRequests | Where-Object { [string]$_.state -eq "OPEN" })) {
    $currentPrChecksByNumber[[int]$pullRequest.number] = @(
        Get-GitHubPullRequestChecks -Repository $resolvedRepository -PullRequestUrl ([string]$pullRequest.url)
    )
}

$desiredParentByIssueNumber = @{}
foreach ($issue in $issues) {
    $parentNumber = ResolveParentIssueNumber -Body ([string]$issue.body)
    if ($null -ne $parentNumber) {
        $desiredParentByIssueNumber[[int]$issue.number] = $parentNumber
    }
}

$parentsWithChildren = @{}
foreach ($parentNumber in $desiredParentByIssueNumber.Values) {
    if ($null -ne $parentNumber) {
        $parentsWithChildren[[int]$parentNumber] = $true
    }
}

$issueContentIds = @{}

$results = foreach ($issue in @($issues | Sort-Object number)) {
    $number = [int]$issue.number
    $body = BodyText -Body ([string]$issue.body)
    $title = [string]$issue.title
    $labels = @(
        Get-GitHubIssueLabelNames -Issue $issue |
            ForEach-Object { [string]$_ }
    )

    $legacyNumber = LegacyNumber -Body $body
    $legacyBody = if ($null -ne $legacyNumber -and $legacyMap.ContainsKey($legacyNumber)) {
        BodyText -Body ([string]$legacyMap[$legacyNumber].body)
    } else {
        ""
    }
    $bodies = @($body, $legacyBody)

    $taskId = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "task_id" }
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        $taskId = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("MF-ID") -Sections @("Roadmap Task", "Roadmap Source") -MaxLength 140 }
    }
    if ([string]::IsNullOrWhiteSpace($taskId)) { $taskId = TitleTaskId -Title $title }

    $area = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "area" }
    if ([string]::IsNullOrWhiteSpace($area)) {
        $area = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Bereich", "Area") -Sections @("Roadmap Task") -MaxLength 180 }
    }
    if ([string]::IsNullOrWhiteSpace($area)) {
        $area = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Project Phase", "Projektphase") -MaxLength 120 }
    }

    $taskTypeSource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "task_type" }
    if ([string]::IsNullOrWhiteSpace($taskTypeSource)) {
        $taskTypeSource = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Typ", "Type") -Sections @("Roadmap Task") -MaxLength 40 }
    }
    $taskType = ResolveTaskType -ExplicitValue $taskTypeSource -Labels $labels -Title $title -Body $body

    $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "priority" }
    if ([string]::IsNullOrWhiteSpace($prioritySource)) {
        $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Prioritaet", "Priority") -Sections @("Roadmap Task") -MaxLength 40 }
    }
    if ([string]::IsNullOrWhiteSpace($prioritySource)) {
        $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Priority", "Severity") -MaxLength 60 }
    }
    $priority = ResolvePriority -ExplicitValue $prioritySource -Labels $labels

    $permitIssue = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "permit_issue" }
    if ($permitIssue -notin @("approved", "rejected", "clarification")) { $permitIssue = $null }

    $sessionId = FirstFromBodies -Bodies $bodies -Getter { param($b) SessionIdVal -Body $b }
    $agentSource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "agent" }
    $agent = ResolveAgent -ExplicitValue $agentSource -Labels $labels -SessionId $sessionId -Body $body -Title $title

    $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "work_branch" }
    if ([string]::IsNullOrWhiteSpace($workBranch)) {
        $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-work-branch", "mapflow-work-branch") -MaxLength 180 }
    }
    if ([string]::IsNullOrWhiteSpace($workBranch)) {
        $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Work Branch", "Branch", "Start Branch") -Sections @("Vorce Project Manager", "MapFlow Project Manager", "Jules Automation", "Roadmap Task") -MaxLength 180 }
    }

    $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "last_update" }
    if ([string]::IsNullOrWhiteSpace($lastUpdate)) {
        $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-last-update", "mapflow-last-update") -MaxLength 80 }
    }
    if ([string]::IsNullOrWhiteSpace($lastUpdate)) {
        $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Letztes Roadmap-Update", "Aktualisiert", "Last Update") -Sections @("Roadmap Task", "Jules Automation", "Vorce Project Manager", "MapFlow Project Manager") -MaxLength 80 }
    }

    $description = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "description" }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Beschreibung", "Task Description", "Description") -MaxLength 220 }
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Goal", "Ziel") -MaxLength 220 }
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Problem", "Bug Description", "Scope") -MaxLength 220 }
    }

    $subAgent = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "sub_agent" }
    $queueState = QueueStateVal -Bodies $bodies
    $remoteState = RemoteStateVal -Bodies $bodies
    $linkedPrFromBodies = LinkedPrVal -Bodies $bodies

    $currentPr = $null
    if (IsSpecificBranchName -Branch $workBranch) {
        $currentPr = Get-LookupFirst -Lookup $currentPrsByBranch -Key ([string]$workBranch)
    }

    $linkedPrNumber = Parse-PullRequestNumberFromUrl -Url $linkedPrFromBodies
    if ($null -eq $currentPr -and $null -ne $linkedPrNumber -and $linkedPrFromBodies -match 'github\.com/Vorce-Studios/Vorce/pull/') {
        if ($currentPrsByNumber.ContainsKey($linkedPrNumber)) {
            $currentPr = $currentPrsByNumber[$linkedPrNumber]
        }
    }
    if ($null -eq $currentPr -and $null -ne $linkedPrNumber) {
        $mappedCurrentPr = Get-LookupFirst -Lookup $currentPrsByLegacyNumber -Key ([string]$linkedPrNumber)
        if ($null -ne $mappedCurrentPr) {
            $currentPr = $mappedCurrentPr
        }
    }

    $linkedPrCandidates = New-Object System.Collections.Generic.List[string]
    if ($null -ne $currentPr) { Add-UniqueValue -List $linkedPrCandidates -Value ([string]$currentPr.url) }
    Add-UniqueValue -List $linkedPrCandidates -Value $linkedPrFromBodies
    $linkedPr = if ($linkedPrCandidates.Count -gt 0) {
        Normalize-TrackingText -Value ($linkedPrCandidates -join " | ") -MaxLength 220
    } else {
        $null
    }

    $currentPrChecks = @()
    if ($null -ne $currentPr -and $currentPrChecksByNumber.ContainsKey([int]$currentPr.number)) {
        $currentPrChecks = @($currentPrChecksByNumber[[int]$currentPr.number])
    }

    $legacyProjectStatus = if ($null -ne $legacyNumber -and $legacyProjectStatusByIssueNumber.ContainsKey($legacyNumber)) {
        [string]$legacyProjectStatusByIssueNumber[$legacyNumber]
    } else {
        $null
    }
    $status = if (-not [string]::IsNullOrWhiteSpace($legacyProjectStatus)) {
        $legacyProjectStatus
    } else {
        ResolveProjectStatus -Issue $issue -Labels $labels -QueueState $queueState -RemoteState $remoteState -LinkedPrValue $linkedPr -CurrentPr $currentPr -CurrentPrChecks $currentPrChecks -HasChildren:$parentsWithChildren.ContainsKey($number)
    }

    $issueContentId = Get-GitHubIssueContentId -Repository $resolvedRepository -IssueNumber $number
    $issueContentIds[$number] = $issueContentId
    $itemId = Ensure-VorceProjectItem -Context $projectContext -IssueContentId $issueContentId

    $updates = [ordered]@{
        "Status"        = $status
        "Linked PR"     = $linkedPr
        "task_id"       = $taskId
        "area"          = $area
        "task_type"     = $taskType
        "priority"      = $priority
        "permit_issue"  = $permitIssue
        "agent"         = $agent
        "jules_session" = $sessionId
        "work_branch"   = $workBranch
        "last_update"   = $lastUpdate
        "description"   = $description
        "sub_agent"     = $subAgent
    }

    $applied = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $updates.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
        if (-not $DryRun.IsPresent) {
            Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName ([string]$entry.Key) -Value ([string]$entry.Value)
        }
        $applied.Add(([string]$entry.Key)) | Out-Null
    }

    [pscustomobject]@{
        Type          = "Issue"
        IssueNumber   = $number
        Title         = $title
        LegacyIssue   = $legacyNumber
        LegacyStatus  = $legacyProjectStatus
        ParentIssue   = if ($desiredParentByIssueNumber.ContainsKey($number)) { $desiredParentByIssueNumber[$number] } else { $null }
        LinkedPr      = $linkedPr
        UpdatedFields = @($applied)
    }
}

$relationResults = foreach ($entry in @($desiredParentByIssueNumber.GetEnumerator() | Sort-Object Key)) {
    $childNumber = [int]$entry.Key
    $parentNumber = [int]$entry.Value
    if ($childNumber -eq $parentNumber) { continue }

    if (-not $issueContentIds.ContainsKey($parentNumber)) {
        $issueContentIds[$parentNumber] = Get-GitHubIssueContentId -Repository $resolvedRepository -IssueNumber $parentNumber
    }
    if (-not $issueContentIds.ContainsKey($childNumber)) {
        $issueContentIds[$childNumber] = Get-GitHubIssueContentId -Repository $resolvedRepository -IssueNumber $childNumber
    }

    $status = Ensure-SubIssueRelationship -Repository $resolvedRepository -ParentIssueNumber $parentNumber -ChildIssueNumber $childNumber -ParentIssueId ([string]$issueContentIds[$parentNumber]) -ChildIssueId ([string]$issueContentIds[$childNumber]) -DryRun:$DryRun.IsPresent

    [pscustomobject]@{
        Type        = "SubIssue"
        ParentIssue = $parentNumber
        ChildIssue  = $childNumber
        Result      = $status
    }
}

$results = @($results)
$relationResults = @($relationResults)
$results + $relationResults
